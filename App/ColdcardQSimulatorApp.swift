import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
@MainActor
struct ColdcardQSimulatorApp: App {
    @State private var store = SimulatorStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var privacyCover = false

    var body: some Scene {
        WindowGroup {
            @Bindable var store = store
            Group {
                if store.interfaceMode == .phone {
                    PhoneInterfaceView(store: store)
                } else {
                    ColdcardDeviceView(store: store)
                }
            }
                .overlay {
                    if privacyCover {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            VStack(spacing: 12) {
                                Image("coldcard-splash").resizable().interpolation(.none).scaledToFit().frame(width: 120)
                                Text("COLDCARD Q SIMULATOR").font(.headline.monospaced())
                                Text("Content hidden while the app is inactive").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $store.showFileImporter,
                    allowedContentTypes: store.fileImporterContentTypes,
                    allowsMultipleSelection: store.importAllowsMultiple
                ) { result in
                    switch result {
                    case .success(let urls): store.handleImportedFiles(urls)
                    case .failure(let error): store.handleFileImporterFailure(error)
                    }
                }
                .onChange(of: store.showFileImporter) { _, presented in
                    if !presented { store.noteFileImporterDismissed() }
                }
                .fileExporter(
                    isPresented: $store.showFileExporter,
                    document: store.exportDocument,
                    contentType: store.exportContentType,
                    defaultFilename: store.exportFilename
                ) { result in
                    switch result {
                    case .success:
                        store.noteExportCompleted(success: true)
                    case .failure(let error):
                        store.noteExportCompleted(success: false)
                        store.errorMessage = error.localizedDescription
                    }
                }
                .sheet(isPresented: $store.showScanner, onDismiss: {
                    store.cancelPendingNoteQuickCreate()
                }) {
                    QRScannerSheet(store: store) { value in store.handleScannedText(value) }
                }
                .sheet(isPresented: $store.showNFCStandIn) {
                    NFCStandInSheet(store: store)
                }
                .sheet(item: $store.qrPresentation) { item in
                    QRPresentationSheet(item: item)
                }
                .onChange(of: scenePhase) { _, phase in
                    privacyCover = phase != .active
                    if phase == .active { store.handleSceneBecameActive() }
                }
        }
    }
}

private struct QRPresentationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: QRPresentation
    @State private var frameIndex = 0
    @State private var isPaused = false

    private var currentPayload: String {
        item.payloads[min(frameIndex, item.payloads.count - 1)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if item.sensitive {
                        Label("Sensitive secret — do not photograph or share", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.bold()).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    QRCodeView(payload: currentPayload, correctionLevel: item.payloads.count > 1 ? "L" : "M")
                        .frame(maxWidth: 420, minHeight: 260, maxHeight: 420)
                        .padding()
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))

                    if item.pagesLabeledQR {
                        HStack {
                            Button { frameIndex = (frameIndex - 1 + item.payloads.count) % item.payloads.count } label: {
                                Image(systemName: "chevron.left")
                            }
                            Text(item.captions.indices.contains(frameIndex) ? item.captions[frameIndex] : item.title)
                                .font(.headline.monospacedDigit())
                            Button { frameIndex = (frameIndex + 1) % item.payloads.count } label: {
                                Image(systemName: "chevron.right")
                            }
                        }
                        Text(String(currentPayload.prefix(80)) + (currentPayload.count > 80 ? "…" : ""))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    } else if item.payloads.count > 1 {
                        HStack {
                            Button { frameIndex = (frameIndex - 1 + item.payloads.count) % item.payloads.count } label: {
                                Image(systemName: "chevron.left")
                            }
                            Text("BBQr frame \(frameIndex + 1) / \(item.payloads.count)")
                                .font(.headline.monospacedDigit())
                            Button { frameIndex = (frameIndex + 1) % item.payloads.count } label: {
                                Image(systemName: "chevron.right")
                            }
                        }
                        Button(isPaused ? "Resume animation" : "Pause animation") { isPaused.toggle() }
                            .buttonStyle(.borderedProminent)
                        Text(String(currentPayload.prefix(80)) + (currentPayload.count > 80 ? "…" : ""))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy all BBQr frames") {
                            UIPasteboard.general.string = item.payloads.joined(separator: "\n")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text(currentPayload)
                            .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        Button("Copy") { UIPasteboard.general.string = currentPayload }
                            .buttonStyle(.bordered)
                    }
                }.padding()
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: item.id) {
                guard item.payloads.count > 1, !item.pagesLabeledQR else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !isPaused { frameIndex = (frameIndex + 1) % item.payloads.count }
                }
            }
        }
    }
}

