#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_DIR = ROOT / "ColdcardQSimulator.xcodeproj"
PROJECT_DIR.mkdir(parents=True, exist_ok=True)


def uid(name: str) -> str:
    return hashlib.sha1(name.encode("utf-8")).hexdigest().upper()[:24]


def quote(value: str) -> str:
    if value and all(c.isalnum() or c in "_./$()<>-" for c in value):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

app_files = sorted((ROOT / "App").glob("*.swift"))
app_rel = [str(p.relative_to(ROOT)) for p in app_files]

third_party_files = sorted(p for p in (ROOT / "ThirdParty").rglob("*") if p.is_file())
doc_files = [ROOT / "README.md", ROOT / "LICENSE", ROOT / "NOTICE.md", ROOT / "Info.plist", ROOT / "PrivacyInfo.xcprivacy", ROOT / "ColdcardQSimulator.entitlements", ROOT / "Package.swift"]
doc_files += sorted((ROOT / "Docs").glob("*.md"))
doc_files += sorted((ROOT / "Docs").glob("*.png"))

# Stable identifiers
project_id = uid("PBXProject")
target_id = uid("PBXNativeTarget:ColdcardQSimulator")
product_ref = uid("PBXFileReference:Product")
main_group = uid("PBXGroup:Main")
app_group = uid("PBXGroup:App")
resources_group = uid("PBXGroup:Resources")
docs_group = uid("PBXGroup:Docs")
third_group = uid("PBXGroup:ThirdParty")
products_group = uid("PBXGroup:Products")
frameworks_phase = uid("PBXFrameworksBuildPhase")
resources_phase = uid("PBXResourcesBuildPhase")
sources_phase = uid("PBXSourcesBuildPhase")
project_debug = uid("XCBuildConfiguration:Project:Debug")
project_release = uid("XCBuildConfiguration:Project:Release")
target_debug = uid("XCBuildConfiguration:Target:Debug")
target_release = uid("XCBuildConfiguration:Target:Release")
project_config_list = uid("XCConfigurationList:Project")
target_config_list = uid("XCConfigurationList:Target")
local_package = uid("XCLocalSwiftPackageReference:Root")
core_product = uid("XCSwiftPackageProductDependency:ColdcardCore")
core_build = uid("PBXBuildFile:ColdcardCore")
asset_ref = uid("PBXFileReference:Assets")
asset_build = uid("PBXBuildFile:Assets")
privacy_ref = uid("PBXFileReference:Privacy")
privacy_build = uid("PBXBuildFile:Privacy")
settings_ref = uid("PBXFileReference:Settings.bundle")
settings_build = uid("PBXBuildFile:Settings.bundle")

file_refs: dict[str, str] = {}
build_ids: dict[str, str] = {}
for rel in app_rel:
    file_refs[rel] = uid(f"PBXFileReference:{rel}")
    build_ids[rel] = uid(f"PBXBuildFile:{rel}")
for p in doc_files + third_party_files:
    rel = str(p.relative_to(ROOT))
    file_refs[rel] = uid(f"PBXFileReference:{rel}")

# Nested ThirdParty groups, preserving paths.
group_ids: dict[str, str] = {"ThirdParty": third_group}
for p in sorted({str(x.parent.relative_to(ROOT)) for x in third_party_files}):
    parts = Path(p).parts
    for i in range(1, len(parts) + 1):
        key = str(Path(*parts[:i]))
        group_ids.setdefault(key, uid(f"PBXGroup:{key}"))


def file_type(path: str) -> tuple[str, str]:
    suffix = Path(path).suffix.lower()
    if suffix == ".swift": return ("lastKnownFileType", "sourcecode.swift")
    if suffix == ".md": return ("lastKnownFileType", "net.daringfireball.markdown")
    if suffix == ".py": return ("lastKnownFileType", "text.script.python")
    if suffix == ".json": return ("lastKnownFileType", "text.json")
    if suffix in {".plist", ".xcprivacy"}: return ("lastKnownFileType", "text.plist.xml")
    if suffix == ".png": return ("lastKnownFileType", "image.png")
    return ("lastKnownFileType", "text")

lines: list[str] = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {\n\t};")
lines.append("\tobjectVersion = 60;")
lines.append("\tobjects = {\n")

# PBXBuildFile
lines.append("/* Begin PBXBuildFile section */")
for rel in app_rel:
    lines.append(f"\t\t{build_ids[rel]} /* {Path(rel).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[rel]} /* {Path(rel).name} */; }};")
lines.append(f"\t\t{asset_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_ref} /* Assets.xcassets */; }};")
lines.append(f"\t\t{privacy_build} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {privacy_ref} /* PrivacyInfo.xcprivacy */; }};")
lines.append(f"\t\t{settings_build} /* Settings.bundle in Resources */ = {{isa = PBXBuildFile; fileRef = {settings_ref} /* Settings.bundle */; }};")
lines.append(f"\t\t{core_build} /* ColdcardCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {core_product} /* ColdcardCore */; }};")
lines.append("/* End PBXBuildFile section */\n")

# File references
lines.append("/* Begin PBXFileReference section */")
for rel in app_rel:
    lines.append(f"\t\t{file_refs[rel]} /* {Path(rel).name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(Path(rel).name)}; sourceTree = \"<group>\"; }};")
lines.append(f"\t\t{asset_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
lines.append(f"\t\t{product_ref} /* ColdcardQSimulator.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ColdcardQSimulator.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for p in doc_files:
    rel = str(p.relative_to(ROOT))
    if rel == "PrivacyInfo.xcprivacy":
        continue
    k, v = file_type(rel)
    lines.append(f"\t\t{file_refs[rel]} /* {Path(rel).name} */ = {{isa = PBXFileReference; {k} = {v}; path = {quote(rel)}; sourceTree = SOURCE_ROOT; }};")
lines.append(f"\t\t{privacy_ref} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT; }};")
lines.append(f"\t\t{settings_ref} /* Settings.bundle */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.plug-in; path = Settings.bundle; sourceTree = \"<group>\"; }};")
for p in third_party_files:
    rel = str(p.relative_to(ROOT))
    k, v = file_type(rel)
    lines.append(f"\t\t{file_refs[rel]} /* {Path(rel).name} */ = {{isa = PBXFileReference; {k} = {v}; path = {quote(Path(rel).name)}; sourceTree = \"<group>\"; }};")
lines.append("/* End PBXFileReference section */\n")

# Framework phase
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{core_build} /* ColdcardCore in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
lines.append("/* End PBXFrameworksBuildPhase section */\n")

# Groups
lines.append("/* Begin PBXGroup section */")
lines.append(f"\t\t{main_group} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{app_group} /* App */,\n\t\t\t\t{resources_group} /* Resources */,\n\t\t\t\t{docs_group} /* Documentation */,\n\t\t\t\t{third_group} /* ThirdParty */,\n\t\t\t\t{products_group} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
lines.append(f"\t\t{app_group} /* App */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
for rel in app_rel:
    lines.append(f"\t\t\t\t{file_refs[rel]} /* {Path(rel).name} */,")
lines.append("\t\t\t);\n\t\t\tpath = App;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")
lines.append(f"\t\t{resources_group} /* Resources */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{asset_ref} /* Assets.xcassets */,\n\t\t\t\t{privacy_ref} /* PrivacyInfo.xcprivacy */,\n\t\t\t\t{settings_ref} /* Settings.bundle */,\n\t\t\t);\n\t\t\tpath = Resources;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
lines.append(f"\t\t{docs_group} /* Documentation */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
for p in doc_files:
    rel = str(p.relative_to(ROOT))
    if rel == "PrivacyInfo.xcprivacy":
        continue
    lines.append(f"\t\t\t\t{file_refs[rel]} /* {Path(rel).name} */,")
lines.append("\t\t\t);\n\t\t\tname = Documentation;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")

# Third-party nested groups. The top group path is ThirdParty. Children are immediate subgroups/files.
all_group_paths = sorted(group_ids.keys(), key=lambda x: (len(Path(x).parts), x), reverse=True)
for group_path in all_group_paths:
    gid = group_ids[group_path]
    children: list[tuple[str, str]] = []
    gp = Path(group_path)
    for child_group, cid in group_ids.items():
        cp = Path(child_group)
        if cp.parent == gp and child_group != group_path:
            children.append((cid, cp.name))
    for p in third_party_files:
        rel = p.relative_to(ROOT)
        if rel.parent == gp:
            children.append((file_refs[str(rel)], rel.name))
    children.sort(key=lambda item: item[1].lower())
    comment = gp.name if group_path != "ThirdParty" else "ThirdParty"
    path_line = f"\n\t\t\tpath = {quote(gp.name)};" if group_path == "ThirdParty" else f"\n\t\t\tpath = {quote(gp.name)};"
    lines.append(f"\t\t{gid} /* {comment} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (")
    for cid, name in children:
        lines.append(f"\t\t\t\t{cid} /* {name} */,")
    lines.append(f"\t\t\t);{path_line}\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")

lines.append(f"\t\t{products_group} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{product_ref} /* ColdcardQSimulator.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
lines.append("/* End PBXGroup section */\n")

# Native target
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_id} /* ColdcardQSimulator */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"ColdcardQSimulator\" */;\n\t\t\tbuildPhases = (\n\t\t\t\t{sources_phase} /* Sources */,\n\t\t\t\t{frameworks_phase} /* Frameworks */,\n\t\t\t\t{resources_phase} /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = ColdcardQSimulator;\n\t\t\tpackageProductDependencies = (\n\t\t\t\t{core_product} /* ColdcardCore */,\n\t\t\t);\n\t\t\tproductName = ColdcardQSimulator;\n\t\t\tproductReference = {product_ref} /* ColdcardQSimulator.app */;\n\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};")
lines.append("/* End PBXNativeTarget section */\n")

# Project
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{project_id} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{target_id} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"ColdcardQSimulator\" */;\n\t\t\tcompatibilityVersion = \"Xcode 15.0\";\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {main_group};\n\t\t\tpackageReferences = (\n\t\t\t\t{local_package} /* XCLocalSwiftPackageReference \".\" */,\n\t\t\t);\n\t\t\tproductRefGroup = {products_group} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t{target_id} /* ColdcardQSimulator */,\n\t\t\t);\n\t\t}};")
lines.append("/* End PBXProject section */\n")

# Resources phase
lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{resources_phase} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{asset_build} /* Assets.xcassets in Resources */,\n\t\t\t\t{privacy_build} /* PrivacyInfo.xcprivacy in Resources */,\n\t\t\t\t{settings_build} /* Settings.bundle in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
lines.append("/* End PBXResourcesBuildPhase section */\n")

# Sources phase
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{sources_phase} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (")
for rel in app_rel:
    lines.append(f"\t\t\t\t{build_ids[rel]} /* {Path(rel).name} in Sources */,")
lines.append("\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */\n")

# Build configurations
lines.append("/* Begin XCBuildConfiguration section */")
project_common = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS", "YES"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "YES_AGGRESSIVE"),
    ("CLANG_CXX_LANGUAGE_STANDARD", '"gnu++20"'),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_ENABLE_OBJC_WEAK", "YES"),
    ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_COMMA", "YES"),
    ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
    ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
    ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
    ("CLANG_WARN_DOCUMENTATION_COMMENTS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_INFINITE_RECURSION", "YES"),
    ("CLANG_WARN_INT_CONVERSION", "YES"),
    ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
    ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
    ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
    ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
    ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
    ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
    ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("SDKROOT", "iphoneos"),
]

def config_block(config_id: str, name: str, settings: list[tuple[str, str]]) -> None:
    lines.append(f"\t\t{config_id} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for key, value in settings:
        lines.append(f"\t\t\t\t{key} = {value};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

config_block(project_debug, "Debug", project_common + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("GCC_PREPROCESSOR_DEFINITIONS", '("DEBUG=1", "$(inherited)")'),
    ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
    ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
])
config_block(project_release, "Release", project_common + [
    ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("MTL_ENABLE_DEBUG_INFO", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
])

target_common = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("GENERATE_INFOPLIST_FILE", "NO"),
    ("INFOPLIST_FILE", "Info.plist"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("LD_RUNPATH_SEARCH_PATHS", '("$(inherited)", "@executable_path/Frameworks")'),
    ("MARKETING_VERSION", "1.0.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "dev.thales.ColdcardQSimulator"),
    ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
    ("CODE_SIGN_ENTITLEMENTS", "ColdcardQSimulator.entitlements"),
    ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
    ("SUPPORTS_MACCATALYST", "NO"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("SWIFT_VERSION", "5.0"),
    ("TARGETED_DEVICE_FAMILY", '"1,2"'),
]
config_block(target_debug, "Debug", target_common + [("ENABLE_PREVIEWS", "YES")])
config_block(target_release, "Release", target_common)
lines.append("/* End XCBuildConfiguration section */\n")

# Configuration lists
lines.append("/* Begin XCConfigurationList section */")
lines.append(f"\t\t{project_config_list} /* Build configuration list for PBXProject \"ColdcardQSimulator\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{project_debug} /* Debug */,\n\t\t\t\t{project_release} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
lines.append(f"\t\t{target_config_list} /* Build configuration list for PBXNativeTarget \"ColdcardQSimulator\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{target_debug} /* Debug */,\n\t\t\t\t{target_release} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
lines.append("/* End XCConfigurationList section */\n")

# Swift packages
lines.append("/* Begin XCLocalSwiftPackageReference section */")
lines.append(f"\t\t{local_package} /* XCLocalSwiftPackageReference \".\" */ = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = .;\n\t\t}};")
lines.append("/* End XCLocalSwiftPackageReference section */\n")
lines.append("/* Begin XCSwiftPackageProductDependency section */")
lines.append(f"\t\t{core_product} /* ColdcardCore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {local_package} /* XCLocalSwiftPackageReference \".\" */;\n\t\t\tproductName = ColdcardCore;\n\t\t}};")
lines.append("/* End XCSwiftPackageProductDependency section */\n")

lines.append("\t};")
lines.append(f"\trootObject = {project_id} /* Project object */;")
lines.append("}")

(PROJECT_DIR / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

workspace = PROJECT_DIR / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text('''<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0">\n   <FileRef location="self:"></FileRef>\n</Workspace>\n''')

scheme_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES" buildArchitectures="Automatic">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="ColdcardQSimulator.app" BlueprintName="ColdcardQSimulator" ReferencedContainer="container:ColdcardQSimulator.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES"/>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="ColdcardQSimulator.app" BlueprintName="ColdcardQSimulator" ReferencedContainer="container:ColdcardQSimulator.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="ColdcardQSimulator.app" BlueprintName="ColdcardQSimulator" ReferencedContainer="container:ColdcardQSimulator.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir / "ColdcardQSimulator.xcscheme").write_text(scheme)
print(PROJECT_DIR / "project.pbxproj")
