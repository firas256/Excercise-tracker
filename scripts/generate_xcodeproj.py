#!/usr/bin/env python3
"""Generates ExerciseTracker.xcodeproj from the folder layout.

You normally never need this: the generated project is committed and you can add files in Xcode
as usual. It exists so the project can be regenerated on machines without Xcode (e.g. CI or
Linux), and documents exactly how the two targets are wired together.

Usage:  python3 scripts/generate_xcodeproj.py
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = "ExerciseTracker"
IOS_TARGET = "ExerciseTracker"
WATCH_TARGET = "ExerciseTracker Watch App"
IOS_DEPLOYMENT = "17.0"
WATCH_DEPLOYMENT = "10.0"

objects = {}


def uid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(value):
    if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_./]+", value):
        return value
    s = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def render(value, indent):
    pad = "\t" * indent
    if isinstance(value, dict):
        inner = "".join(f"{pad}\t{q(k)} = {render(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + inner + pad + "}"
    if isinstance(value, list):
        inner = "".join(f"{pad}\t{render(v, indent + 1)},\n" for v in value)
        return "(\n" + inner + pad + ")"
    return q(value)


def add(oid, obj):
    if oid in objects and objects[oid] != obj:
        raise SystemExit(f"Object id collision for {oid}: {obj.get('isa')}")
    objects[oid] = obj
    return oid


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".xcassets": "folder.assetcatalog",
    ".xcconfig": "text.xcconfig",
    ".entitlements": "text.plist.entitlements",
    ".plist": "text.plist.xml",
    ".md": "net.daringfireball.markdown",
}


def file_ref(path):
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1]
    return add(uid("fileref", path), {
        "isa": "PBXFileReference",
        "lastKnownFileType": FILE_TYPES.get(ext, "text"),
        "path": name,
        "sourceTree": "<group>",
    })


def group_for_dir(rel_dir, collect, name=None):
    """Creates a group mirroring a directory. `collect(path, ref)` records source/resource files."""
    children = []
    abs_dir = os.path.join(ROOT, rel_dir)
    entries = sorted(os.listdir(abs_dir), key=lambda e: (not os.path.isdir(os.path.join(abs_dir, e)) or e.endswith(".xcassets"), e.lower()))
    for e in entries:
        if e.startswith("."):
            continue
        rel = os.path.join(rel_dir, e)
        full = os.path.join(ROOT, rel)
        if os.path.isdir(full) and not e.endswith(".xcassets"):
            children.append(group_for_dir(rel, collect))
        elif e.endswith((".swift", ".xcassets")):
            ref = file_ref(rel)
            collect(rel, ref)
            children.append(ref)
    obj = {"isa": "PBXGroup", "children": children, "path": os.path.basename(rel_dir), "sourceTree": "<group>"}
    if name:
        obj["name"] = name
    return add(uid("group", rel_dir), obj)


shared_sources, ios_sources, watch_sources = [], [], []
ios_resources, watch_resources = [], []


def collector(sources, resources):
    def collect(path, ref):
        (resources if path.endswith(".xcassets") else sources).append((path, ref))
    return collect


shared_group = group_for_dir("Shared", collector(shared_sources, []))
ios_group = group_for_dir("iOSApp", collector(ios_sources, ios_resources))
watch_group = group_for_dir("WatchApp", collector(watch_sources, watch_resources))
ios_uitest_sources, watch_uitest_sources = [], []
ios_uitest_group = group_for_dir("UITests/iOS", collector(ios_uitest_sources, []), name="iOS UI Tests")
watch_uitest_group = group_for_dir("UITests/Watch", collector(watch_uitest_sources, []), name="Watch UI Tests")
uitests_group = add(uid("group", "UITests"), {
    "isa": "PBXGroup", "children": [ios_uitest_group, watch_uitest_group], "path": "UITests", "sourceTree": "<group>",
})

config_files = ["Base.xcconfig", "ExerciseTracker.entitlements", "WatchApp.entitlements", "iOS-Info.plist", "Watch-Info.plist"]
config_refs = {f: file_ref(os.path.join("Config", f)) for f in config_files}
config_group = add(uid("group", "Config"), {
    "isa": "PBXGroup", "children": [config_refs[f] for f in config_files], "path": "Config", "sourceTree": "<group>",
})

ios_product = add(uid("product", IOS_TARGET), {
    "isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
    "path": f"{IOS_TARGET}.app", "sourceTree": "BUILT_PRODUCTS_DIR",
})
watch_product = add(uid("product", WATCH_TARGET), {
    "isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
    "path": f"{WATCH_TARGET}.app", "sourceTree": "BUILT_PRODUCTS_DIR",
})
IOS_UITESTS = "ExerciseTrackerUITests"
WATCH_UITESTS = "ExerciseTrackerWatchUITests"
ios_uitest_product = add(uid("product", IOS_UITESTS), {
    "isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "includeInIndex": "0",
    "path": f"{IOS_UITESTS}.xctest", "sourceTree": "BUILT_PRODUCTS_DIR",
})
watch_uitest_product = add(uid("product", WATCH_UITESTS), {
    "isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "includeInIndex": "0",
    "path": f"{WATCH_UITESTS}.xctest", "sourceTree": "BUILT_PRODUCTS_DIR",
})
products_group = add(uid("group", "Products"), {
    "isa": "PBXGroup", "children": [ios_product, watch_product, ios_uitest_product, watch_uitest_product],
    "name": "Products", "sourceTree": "<group>",
})
readme_ref = add(uid("fileref", "README.md"), {
    "isa": "PBXFileReference", "lastKnownFileType": "net.daringfireball.markdown", "path": "README.md", "sourceTree": "<group>",
})
main_group = add(uid("group", "main"), {
    "isa": "PBXGroup",
    "children": [readme_ref, shared_group, watch_group, ios_group, uitests_group, config_group, products_group],
    "sourceTree": "<group>",
})


def build_phase(kind, target, files, extra=None):
    file_ids = []
    for path, ref in files:
        file_ids.append(add(uid("buildfile", target, kind, path), {"isa": "PBXBuildFile", "fileRef": ref}))
    obj = {"isa": kind, "buildActionMask": "2147483647", "files": file_ids, "runOnlyForDeploymentPostprocessing": "0"}
    if extra:
        obj.update(extra)
    return add(uid("phase", target, kind), obj)


def config_list(owner, debug_settings, release_settings, base_ref=None):
    ids = []
    for name, settings in (("Debug", debug_settings), ("Release", release_settings)):
        obj = {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": name}
        if base_ref:
            obj["baseConfigurationReference"] = base_ref
        ids.append(add(uid("config", owner, name), obj))
    return add(uid("configlist", owner), {
        "isa": "XCConfigurationList", "buildConfigurations": ids,
        "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release",
    })


common_target = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Rep Coach",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
}

ios_settings = dict(common_target, **{
    "CODE_SIGN_ENTITLEMENTS": "Config/ExerciseTracker.entitlements",
    "INFOPLIST_FILE": "Config/iOS-Info.plist",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "IPHONEOS_DEPLOYMENT_TARGET": IOS_DEPLOYMENT,
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).ExerciseTracker",
    "SDKROOT": "iphoneos",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
})

watch_settings = dict(common_target, **{
    "CODE_SIGN_ENTITLEMENTS": "Config/WatchApp.entitlements",
    "INFOPLIST_FILE": "Config/Watch-Info.plist",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(BUNDLE_ID_PREFIX).ExerciseTracker",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).ExerciseTracker.watchkitapp",
    "SDKROOT": "watchos",
    "SKIP_INSTALL": "YES",
    "TARGETED_DEVICE_FAMILY": "4",
    "WATCHOS_DEPLOYMENT_TARGET": WATCH_DEPLOYMENT,
})

# Watch target
watch_phases = [
    build_phase("PBXSourcesBuildPhase", WATCH_TARGET, shared_sources + watch_sources),
    build_phase("PBXFrameworksBuildPhase", WATCH_TARGET, []),
    build_phase("PBXResourcesBuildPhase", WATCH_TARGET, watch_resources),
]
watch_target = add(uid("target", WATCH_TARGET), {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": config_list("target:" + WATCH_TARGET, watch_settings, watch_settings),
    "buildPhases": watch_phases,
    "buildRules": [],
    "dependencies": [],
    "name": WATCH_TARGET,
    "productName": WATCH_TARGET,
    "productReference": watch_product,
    "productType": "com.apple.product-type.application",
})

# iOS target embeds the watch app
project_id = uid("project", PROJECT)
proxy = add(uid("proxy", WATCH_TARGET), {
    "isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": "1",
    "remoteGlobalIDString": watch_target, "remoteInfo": WATCH_TARGET,
})
dependency = add(uid("dependency", WATCH_TARGET), {
    "isa": "PBXTargetDependency", "target": watch_target, "targetProxy": proxy,
})
embed_file = add(uid("buildfile", IOS_TARGET, "embed-watch"), {
    "isa": "PBXBuildFile", "fileRef": watch_product, "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]},
})
embed_phase = add(uid("phase", IOS_TARGET, "embed-watch"), {
    "isa": "PBXCopyFilesBuildPhase", "buildActionMask": "2147483647", "dstPath": "$(CONTENTS_FOLDER_PATH)/Watch",
    "dstSubfolderSpec": "16", "files": [embed_file], "name": "Embed Watch Content",
    "runOnlyForDeploymentPostprocessing": "0",
})
ios_phases = [
    build_phase("PBXSourcesBuildPhase", IOS_TARGET, shared_sources + ios_sources),
    build_phase("PBXFrameworksBuildPhase", IOS_TARGET, []),
    build_phase("PBXResourcesBuildPhase", IOS_TARGET, ios_resources),
    embed_phase,
]
ios_target = add(uid("target", IOS_TARGET), {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": config_list("target:" + IOS_TARGET, ios_settings, ios_settings),
    "buildPhases": ios_phases,
    "buildRules": [],
    "dependencies": [dependency],
    "name": IOS_TARGET,
    "productName": IOS_TARGET,
    "productReference": ios_product,
    "productType": "com.apple.product-type.application",
})



def target_dependency(owner, target_id, target_name):
    proxy_id = add(uid("proxy", owner, target_name), {
        "isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": "1",
        "remoteGlobalIDString": target_id, "remoteInfo": target_name,
    })
    return add(uid("dependency", owner, target_name), {
        "isa": "PBXTargetDependency", "target": target_id, "targetProxy": proxy_id,
    })


uitest_common = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
}
ios_uitest_settings = dict(uitest_common, **{
    "IPHONEOS_DEPLOYMENT_TARGET": IOS_DEPLOYMENT,
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).ExerciseTrackerUITests",
    "SDKROOT": "iphoneos",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_TARGET_NAME": IOS_TARGET,
})
watch_uitest_settings = dict(uitest_common, **{
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).ExerciseTrackerWatchUITests",
    "SDKROOT": "watchos",
    "TARGETED_DEVICE_FAMILY": "4",
    "TEST_TARGET_NAME": WATCH_TARGET,
    "WATCHOS_DEPLOYMENT_TARGET": WATCH_DEPLOYMENT,
})


def uitest_target(name, settings, sources, product, app_target, app_name):
    phases = [
        build_phase("PBXSourcesBuildPhase", name, sources),
        build_phase("PBXFrameworksBuildPhase", name, []),
        build_phase("PBXResourcesBuildPhase", name, []),
    ]
    return add(uid("target", name), {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": config_list("target:" + name, settings, settings),
        "buildPhases": phases,
        "buildRules": [],
        "dependencies": [target_dependency(name, app_target, app_name)],
        "name": name,
        "productName": name,
        "productReference": product,
        "productType": "com.apple.product-type.bundle.ui-testing",
    })


ios_uitest_target = uitest_target(IOS_UITESTS, ios_uitest_settings, ios_uitest_sources, ios_uitest_product, ios_target, IOS_TARGET)
watch_uitest_target = uitest_target(WATCH_UITESTS, watch_uitest_settings, watch_uitest_sources, watch_uitest_product, watch_target, WATCH_TARGET)

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SWIFT_VERSION": "5.0",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

add(project_id, {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "1500",
        "LastUpgradeCheck": "1500",
        "TargetAttributes": {
            ios_target: {"CreatedOnToolsVersion": "15.0"},
            watch_target: {"CreatedOnToolsVersion": "15.0"},
            ios_uitest_target: {"CreatedOnToolsVersion": "15.0", "TestTargetID": ios_target},
            watch_uitest_target: {"CreatedOnToolsVersion": "15.0", "TestTargetID": watch_target},
        },
    },
    "buildConfigurationList": config_list("project:" + PROJECT, project_debug, project_release, base_ref=config_refs["Base.xcconfig"]),
    "compatibilityVersion": "Xcode 14.0",
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base"],
    "mainGroup": main_group,
    "productRefGroup": products_group,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [ios_target, watch_target, ios_uitest_target, watch_uitest_target],
})

# ---- Write project.pbxproj (objects grouped by isa, like Xcode does) ----
by_isa = {}
for oid, obj in objects.items():
    by_isa.setdefault(obj["isa"], []).append((oid, obj))

lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for isa in sorted(by_isa):
    lines.append("")
    lines.append(f"/* Begin {isa} section */")
    for oid, obj in sorted(by_isa[isa]):
        body = {"isa": obj["isa"], **{k: v for k, v in obj.items() if k != "isa"}}
        lines.append(f"\t\t{oid} = {render(body, 2)};")
    lines.append(f"/* End {isa} section */")
lines += ["\t};", f"\trootObject = {project_id};", "}", ""]

proj_dir = os.path.join(ROOT, f"{PROJECT}.xcodeproj")
os.makedirs(os.path.join(proj_dir, "project.xcworkspace"), exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines))
with open(os.path.join(proj_dir, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')


# ---- Shared schemes ----
def scheme(target_id, target_name, test_id=None, test_name=None):
    ref = (f'            <BuildableReference\n'
           f'               BuildableIdentifier = "primary"\n'
           f'               BlueprintIdentifier = "{target_id}"\n'
           f'               BuildableName = "{target_name}.app"\n'
           f'               BlueprintName = "{target_name}"\n'
           f'               ReferencedContainer = "container:{PROJECT}.xcodeproj">\n'
           f'            </BuildableReference>\n')
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{ref}         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_id}"
               BuildableName = "{test_name}.xctest"
               BlueprintName = "{test_name}"
               ReferencedContainer = "container:{PROJECT}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{ref.replace("            ", "         ", 1)}      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{ref.replace("            ", "         ", 1)}      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''


scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
with open(os.path.join(scheme_dir, f"{IOS_TARGET}.xcscheme"), "w") as f:
    f.write(scheme(ios_target, IOS_TARGET, ios_uitest_target, IOS_UITESTS))
with open(os.path.join(scheme_dir, f"{WATCH_TARGET}.xcscheme"), "w") as f:
    f.write(scheme(watch_target, WATCH_TARGET, watch_uitest_target, WATCH_UITESTS))

print(f"Wrote {proj_dir}: {len(shared_sources)} shared, {len(ios_sources)} iOS, {len(watch_sources)} watch sources")
