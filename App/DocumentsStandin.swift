import Foundation
import Darwin
import ColdcardCore

/// App Documents stand-ins for firmware MicroSD (`/sd`) and Virtual Disk (`/vdisk`).
///
/// USB Mass Storage gadget is out of scope. These folders are the Files-app
/// mapping. Ready To Sign (VD import) should read `directory(for: .virtDisk)
/// — drop a PSBT there; Auto opens it.
nonisolated enum SimulatorCardStandin {
    enum Volume: String, Equatable, Sendable, CaseIterable {
        case microSD = "MicroSD"
        case virtDisk = "VirtDisk"
    }

    /// Firmware `file_picker` default `max_size` (`actions.py`).
    static let listFilesMaxSize = 1_000_000
    /// Firmware `vdisk.host_done_handler`: `sz > 100`.
    static let autoPSBTMinSize = 101
    /// Firmware `MAX_UPLOAD_LEN_MK4` (4 MiB virtual disk).
    static let maxUploadLength = 4 * 1024 * 1024
    /// Q `ready2sign` / `file_picker` `max_size=MAX_TXN_LEN` (`version.py` MK4 alias, 2 MiB).
    static let psbtPickerMaxSize = 2 * 1024 * 1024
    /// Firmware `file_picker` `min_size=50` for Ready To Sign.
    static let psbtPickerMinSize = 50

    /// Override for tests; `nil` uses the app Documents directory.
    static var documentsRootOverride: URL?

    static func documentsRoot() -> URL {
        if let documentsRootOverride { return documentsRootOverride }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func directory(for volume: Volume) -> URL {
        documentsRoot().appendingPathComponent(volume.rawValue, isDirectory: true)
    }

    static func ensureDirectories() {
        for volume in Volume.allCases {
            let dir = directory(for: volume)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? seedVirtDiskIfNeeded()
    }

    /// Firmware `wipe_vdisk` / `wipe_microsd_card`: destroy contents and recreate the volume.
    static func wipe(_ volume: Volume) throws {
        let dir = directory(for: volume)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if volume == .virtDisk {
            try writeVirtDiskSkeleton()
        }
    }

    static func write(_ data: Data, named filename: String, to volume: Volume) throws -> URL {
        ensureDirectories()
        let url = directory(for: volume).appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Firmware `CardSlot.abs_path` lookup for `verify_signed_file_digest`.
    static func fileData(named filename: String, extraDirectory: URL? = nil) -> Data? {
        ensureDirectories()
        var candidates = Volume.allCases.map { directory(for: $0).appendingPathComponent(filename) }
        if let extraDirectory {
            candidates.append(extraDirectory.appendingPathComponent(filename))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    static func rename(_ file: ListedDiskFile, to newName: String) throws -> ListedDiskFile {
        try validateRename(newName)
        let dest = file.volumeDirectory.appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: dest.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: file.url, to: dest)
        return ListedDiskFile(volume: file.volume, filename: newName, size: file.size, url: dest)
    }

    /// Firmware `CardSlot.securely_blank_file`: zero, then delete.
    static func securelyDelete(_ file: ListedDiskFile) throws {
        if FileManager.default.fileExists(atPath: file.url.path) {
            let zeros = Data(repeating: 0, count: max(file.size, 1))
            try? zeros.write(to: file.url, options: .atomic)
            try FileManager.default.removeItem(at: file.url)
        }
    }

    /// Firmware `file_picker` / `list_files`: root files on SD and, when enabled, VirtDisk.
    static func listFilesForPicker(vdiskEnabled: Bool, minSize: Int = 0, maxSize: Int = listFilesMaxSize) -> [ListedDiskFile] {
        ensureDirectories()
        var volumes: [Volume] = [.microSD]
        if vdiskEnabled { volumes.append(.virtDisk) }
        var files: [ListedDiskFile] = []
        for volume in volumes {
            files.append(contentsOf: listRootFiles(on: volume, minSize: minSize, maxSize: maxSize))
        }
        files.sort { lhs, rhs in
            if lhs.menuLabel == rhs.menuLabel { return lhs.filename < rhs.filename }
            return lhs.menuLabel < rhs.menuLabel
        }
        let counts = Dictionary(grouping: files, by: \.filename).mapValues(\.count)
        return files.map { file in
            var copy = file
            if (counts[file.filename] ?? 0) > 1 {
                copy.menuLabel = "\(file.volume.rawValue)/\(file.filename)"
            }
            return copy
        }
    }

    static func listRootFiles(on volume: Volume, minSize: Int = 0, maxSize: Int = Int.max) -> [ListedDiskFile] {
        let dir = directory(for: volume)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { return nil }
            let size = values?.fileSize ?? (try? Data(contentsOf: url).count) ?? 0
            guard (minSize...maxSize).contains(size) else { return nil }
            return ListedDiskFile(volume: volume, filename: name, size: size, url: url)
        }
        .sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
    }

    /// Firmware `ready2sign` / `file_picker(suffix='.psbt', taster=is_psbt)` on one CardSlot volume.
    static func psbtFiles(on volume: Volume) -> [ListedDiskFile] {
        ensureDirectories()
        return listRootFiles(on: volume, minSize: psbtPickerMinSize, maxSize: psbtPickerMaxSize).compactMap { file in
            guard file.filename.lowercased().hasSuffix(".psbt") else { return nil }
            guard let data = try? Data(contentsOf: file.url) else { return nil }
            guard PSBT.isPSBTTaste(filename: file.filename, data: data) else { return nil }
            return file
        }
        .sorted { $0.filename < $1.filename }
    }

    /// Snapshot used by Enable & Auto (`vdisk.sample`): root files with sizes.
    static func sampleVirtDisk() -> [(filename: String, size: Int)] {
        listRootFiles(on: .virtDisk, minSize: 0, maxSize: Int.max).map { ($0.filename, $0.size) }
    }

    static func isAutoPSBTCandidate(filename: String, size: Int) -> Bool {
        if filename.hasPrefix(".") || size == 0 { return false }
        if size > maxUploadLength { return false }
        let lower = filename.lowercased()
        return lower.hasSuffix(".psbt") && size >= autoPSBTMinSize && !lower.contains("-signed")
    }

    static func validateRename(_ newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...32).contains(name.count) else {
            throw RenameError.length
        }
        for illegal in ["/", "\\", " "] where name.contains(illegal) {
            throw RenameError.illegalChar
        }
    }

    private static func seedVirtDiskIfNeeded() throws {
        let readme = directory(for: .virtDisk).appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try writeVirtDiskSkeleton()
        }
    }

    /// Firmware `mk4.make_psram_fs` README + `ident/version.txt`.
    private static func writeVirtDiskSkeleton() throws {
        let root = directory(for: .virtDisk)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = """

        COLDCARD Virtual Disk

        1) copy your PSBT file here.
        2) select from Coldcard menu & approve transaction.
        3) signed transaction file(s) will be saved here.

        """.replacingOccurrences(of: "\n", with: "\r\n")
        try Data(readme.utf8).write(to: root.appendingPathComponent("README.txt"), options: .atomic)
        let ident = root.appendingPathComponent("ident", isDirectory: true)
        try FileManager.default.createDirectory(at: ident, withIntermediateDirectories: true)
        let version = "1.0.0\r\nsimulator\r\n"
        try Data(version.utf8).write(to: ident.appendingPathComponent("version.txt"), options: .atomic)
    }

    enum RenameError: LocalizedError {
        case length
        case illegalChar

        var errorDescription: String? {
            switch self {
            case .length: "name must be 3 to 32 characters"
            case .illegalChar: "illegal char"
            }
        }
    }
}

nonisolated struct ListedDiskFile: Equatable, Identifiable, Sendable {
    var volume: SimulatorCardStandin.Volume
    var filename: String
    var size: Int
    var url: URL
    var menuLabel: String

    init(volume: SimulatorCardStandin.Volume, filename: String, size: Int, url: URL, menuLabel: String? = nil) {
        self.volume = volume
        self.filename = filename
        self.size = size
        self.url = url
        self.menuLabel = menuLabel ?? filename
    }

    var id: String { "\(volume.rawValue)/\(filename)" }
    var volumeDirectory: URL { SimulatorCardStandin.directory(for: volume) }
}

/// Watches Documents/VirtDisk for Enable & Auto (`vdisk.host_done_handler`).
@MainActor
final class VirtDiskAutoMonitor {
    var onNewPSBT: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var known: [(filename: String, size: Int)] = []
    private var ignore: Set<String> = []
    private var scanTask: Task<Void, Never>?

    func start() {
        stop()
        SimulatorCardStandin.ensureDirectories()
        let dir = SimulatorCardStandin.directory(for: .virtDisk)
        known = SimulatorCardStandin.sampleVirtDisk()
        ignore = Set(known.map(\.filename))
        let opened = open(dir.path, O_EVTONLY)
        guard opened >= 0 else { return }
        directoryFD = opened
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryFD >= 0 else { return }
            close(self.directoryFD)
            self.directoryFD = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        source?.cancel()
        source = nil
        ignore.removeAll()
        known = []
    }

    func noteWritten(filename: String) {
        ignore.insert(filename)
    }

    func resetAfterWipe() {
        ignore.removeAll()
        known = SimulatorCardStandin.sampleVirtDisk()
        ignore = Set(known.map(\.filename))
        if source != nil { start() }
    }

    func scanNow() {
        consume()
    }

    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.consume()
        }
    }

    private func consume() {
        let now = SimulatorCardStandin.sampleVirtDisk()
        if now.count == known.count,
           zip(now, known).allSatisfy({ $0.filename == $1.filename && $0.size == $1.size }) {
            return
        }
        ignore = ignore.intersection(Set(now.map(\.filename)))
        known = now
        for entry in now {
            if ignore.contains(entry.filename) { continue }
            guard SimulatorCardStandin.isAutoPSBTCandidate(filename: entry.filename, size: entry.size) else { continue }
            ignore.insert(entry.filename)
            let url = SimulatorCardStandin.directory(for: .virtDisk).appendingPathComponent(entry.filename)
            onNewPSBT?(url)
            break
        }
    }
}

/// Documents `VirtDisk/` folder. Ready To Sign (2) and Enable & Auto call this.
enum VirtualDiskFolder {
    static func directory() -> URL {
        SimulatorCardStandin.directory(for: .virtDisk)
    }

    static func ensureDirectory() {
        SimulatorCardStandin.ensureDirectories()
    }

    /// Unsigned `.psbt` files on the virtual disk (firmware `force_vdisk=True` picker).
    static func psbtURLs() -> [URL] {
        SimulatorCardStandin.psbtFiles(on: .virtDisk).map(\.url)
    }
}

/// Documents `MicroSD/` folder — SD-card stand-in for List Files and Format SD Card.
enum MicroSDFolder {
    static func directory() -> URL {
        SimulatorCardStandin.directory(for: .microSD)
    }

    static func ensureDirectory() {
        SimulatorCardStandin.ensureDirectories()
    }
}

