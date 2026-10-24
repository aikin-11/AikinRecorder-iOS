#!/usr/bin/env python3
"""Generate a dependency-free, reviewable Xcode project on macOS or Windows."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'AikinRecorder.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(name, content):
    key = uid(name)
    objects[key] = content
    return key

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def settings(values):
    return '{ ' + ' '.join(f'{k} = {quote(v)};' for k, v in values.items()) + ' }'

def refs(ids):
    return '(' + ', '.join(ids) + ',)'

app_sources, test_sources, resources, source_refs, test_refs, resource_refs = [], [], [], [], [], []
widget_sources, widget_refs = [], []
shared_for_widget = {'AikinRecorder/Sources/Recording.swift', 'AikinRecorder/Sources/RecordingActivityAttributes.swift'}
for path in sorted((ROOT / 'AikinRecorder/Sources').glob('*.swift')) + sorted((ROOT / 'Tests').glob('*.swift')):
    relative = path.relative_to(ROOT).as_posix()
    ref = add(relative, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ' + quote(relative) + '; sourceTree = SOURCE_ROOT;}')
    build = add(relative + ':build', '{isa = PBXBuildFile; fileRef = ' + ref + ';}')
    if relative.startswith('Tests/'):
        test_sources.append(build); test_refs.append(ref)
    else:
        app_sources.append(build); source_refs.append(ref)
        if relative in shared_for_widget:
            widget_sources.append(add(relative + ':widget', '{isa = PBXBuildFile; fileRef = ' + ref + ';}'))
for path in sorted((ROOT / 'AikinRecorderLiveActivity').glob('*.swift')):
    relative = path.relative_to(ROOT).as_posix()
    ref = add(relative, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ' + quote(relative) + '; sourceTree = SOURCE_ROOT;}')
    widget_sources.append(add(relative + ':build', '{isa = PBXBuildFile; fileRef = ' + ref + ';}'))
    widget_refs.append(ref)
for relative, kind in [('AikinRecorder/Resources/Assets.xcassets', 'folder.assetcatalog'), ('AikinRecorder/Resources/SpecialElite-Regular.ttf', 'file'), ('AikinRecorder/Resources/SpecialElite-LICENSE.txt', 'text'), ('AikinRecorder/Resources/PrivacyInfo.xcprivacy', 'text.xml')]:
    ref = add(relative, '{isa = PBXFileReference; lastKnownFileType = ' + kind + '; path = ' + quote(relative) + '; sourceTree = SOURCE_ROOT;}')
    resources.append(add(relative + ':build', '{isa = PBXBuildFile; fileRef = ' + ref + ';}')); resource_refs.append(ref)

app_product = add('appProduct', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = AikinRecorder.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product = add('testProduct', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AikinRecorderTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
widget_product = add('widgetProduct', '{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = AikinRecorderLiveActivity.appex; sourceTree = BUILT_PRODUCTS_DIR;}')
widget_embed = add('widgetEmbed', '{isa = PBXBuildFile; fileRef = ' + widget_product + '; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);};}')
watch_sources, watch_refs = [], []
for path in sorted((ROOT / 'AikinRecorderWatch').glob('*.swift')):
    relative = path.relative_to(ROOT).as_posix()
    ref = add(relative, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ' + quote(relative) + '; sourceTree = SOURCE_ROOT;}')
    watch_sources.append(add(relative + ':build', '{isa = PBXBuildFile; fileRef = ' + ref + ';}'))
    watch_refs.append(ref)
watch_resources = []
assets = 'AikinRecorderWatch/Assets.xcassets'
assets_ref = add(assets, '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = ' + quote(assets) + '; sourceTree = SOURCE_ROOT;}')
watch_resources.append(add(assets + ':build', '{isa = PBXBuildFile; fileRef = ' + assets_ref + ';}'))
watch_refs.append(assets_ref)
for icon in sorted((ROOT / 'AikinRecorderWatch/BundledIcons').glob('*.png')):
    relative = icon.relative_to(ROOT).as_posix()
    ref = add(relative, '{isa = PBXFileReference; lastKnownFileType = image.png; path = ' + quote(relative) + '; sourceTree = SOURCE_ROOT;}')
    watch_resources.append(add(relative + ':build', '{isa = PBXBuildFile; fileRef = ' + ref + ';}'))
    watch_refs.append(ref)
watch_product = add('watchProduct', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = AikinRecorderWatch.app; sourceTree = BUILT_PRODUCTS_DIR;}')
watch_embed = add('watchEmbed', '{isa = PBXBuildFile; fileRef = ' + watch_product + '; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);};}')
src_group = add('sourcesGroup', '{isa = PBXGroup; children = ' + refs(source_refs) + '; name = Sources; sourceTree = "<group>";}')
res_group = add('resourcesGroup', '{isa = PBXGroup; children = ' + refs(resource_refs) + '; name = Resources; sourceTree = "<group>";}')
test_group = add('testsGroup', '{isa = PBXGroup; children = ' + refs(test_refs) + '; name = Tests; sourceTree = "<group>";}')
widget_group = add('widgetGroup', '{isa = PBXGroup; children = ' + refs(widget_refs) + '; name = LiveActivity; sourceTree = "<group>";}')
watch_group = add('watchGroup', '{isa = PBXGroup; children = ' + refs(watch_refs) + '; name = Watch; sourceTree = "<group>";}')
products = add('products', '{isa = PBXGroup; children = ' + refs([app_product, test_product, widget_product, watch_product]) + '; name = Products; sourceTree = "<group>";}')
main_group = add('mainGroup', '{isa = PBXGroup; children = ' + refs([src_group, res_group, test_group, widget_group, watch_group, products]) + '; sourceTree = "<group>";}')
for name, isa, files in [('appSources', 'PBXSourcesBuildPhase', app_sources), ('testSources', 'PBXSourcesBuildPhase', test_sources), ('widgetSources', 'PBXSourcesBuildPhase', widget_sources), ('watchSources', 'PBXSourcesBuildPhase', watch_sources), ('watchResources', 'PBXResourcesBuildPhase', watch_resources), ('appResources', 'PBXResourcesBuildPhase', resources), ('appFrameworks', 'PBXFrameworksBuildPhase', []), ('testFrameworks', 'PBXFrameworksBuildPhase', []), ('widgetFrameworks', 'PBXFrameworksBuildPhase', []), ('watchFrameworks', 'PBXFrameworksBuildPhase', [])]:
    add(name, '{isa = ' + isa + '; buildActionMask = 2147483647; files = ' + (refs(files) if files else '()') + '; runOnlyForDeploymentPostprocessing = 0;}')
add('embedWidgets', '{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ' + refs([widget_embed]) + '; name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0;}')
add('embedWatch', '{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = ' + refs([watch_embed]) + '; name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0;}')

config_lists = {}
for owner in ['project', 'app', 'test', 'widget', 'watch']:
    configs = []
    for mode in ['Debug', 'Release']:
        cfg = {'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'CODE_SIGNING_ALLOWED': 'NO'}
        if mode == 'Debug':
            cfg.update(SWIFT_OPTIMIZATION_LEVEL='-Onone', ENABLE_TESTABILITY='YES', DEBUG_INFORMATION_FORMAT='dwarf', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG')
        else:
            cfg.update(SWIFT_OPTIMIZATION_LEVEL='-O', DEBUG_INFORMATION_FORMAT='dwarf-with-dsym', SWIFT_COMPILATION_MODE='wholemodule')
        if owner == 'app':
            cfg.update(PRODUCT_NAME='AikinRecorder', PRODUCT_BUNDLE_IDENTIFIER='app.aikin.recorder', TARGETED_DEVICE_FAMILY='1,2', INFOPLIST_FILE='AikinRecorder/Resources/Info.plist', GENERATE_INFOPLIST_FILE='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO', CURRENT_PROJECT_VERSION='37', MARKETING_VERSION='1.36.0')
        if owner == 'test':
            cfg.update(PRODUCT_NAME='AikinRecorderTests', PRODUCT_BUNDLE_IDENTIFIER='app.aikin.recorder.tests', GENERATE_INFOPLIST_FILE='YES', TEST_HOST='$(BUILT_PRODUCTS_DIR)/AikinRecorder.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/AikinRecorder', BUNDLE_LOADER='$(TEST_HOST)', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @loader_path/Frameworks', TARGETED_DEVICE_FAMILY='1,2')
        if owner == 'widget':
            cfg.update(PRODUCT_NAME='AikinRecorderLiveActivity', PRODUCT_BUNDLE_IDENTIFIER='app.aikin.recorder.liveactivity', TARGETED_DEVICE_FAMILY='1,2', INFOPLIST_FILE='AikinRecorderLiveActivity/Info.plist', GENERATE_INFOPLIST_FILE='NO', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks', SKIP_INSTALL='YES', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', CURRENT_PROJECT_VERSION='37', MARKETING_VERSION='1.36.0', APPLICATION_EXTENSION_API_ONLY='YES', CODE_SIGNING_REQUIRED='NO')
        if owner == 'watch':
            cfg.update(PRODUCT_NAME='AikinRecorderWatch', PRODUCT_BUNDLE_IDENTIFIER='app.aikin.recorder.watch', SDKROOT='watchos', TARGETED_DEVICE_FAMILY='4', INFOPLIST_FILE='AikinRecorderWatch/Info.plist', GENERATE_INFOPLIST_FILE='NO', WATCHOS_DEPLOYMENT_TARGET='11.0', SKIP_INSTALL='YES', SUPPORTED_PLATFORMS='watchos watchsimulator', CURRENT_PROJECT_VERSION='37', MARKETING_VERSION='1.36.0', CODE_SIGNING_REQUIRED='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS='YES')
        configs.append(add(owner + mode, '{isa = XCBuildConfiguration; buildSettings = ' + settings(cfg) + '; name = ' + mode + ';}'))
    config_lists[owner] = add(owner + 'Configs', '{isa = XCConfigurationList; buildConfigurations = ' + refs(configs) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')

project_id = uid('project')
app_target = uid('appTarget')
test_target = uid('testTarget')
widget_target = uid('widgetTarget')
watch_target = uid('watchTarget')
proxy = add('proxy', '{isa = PBXContainerItemProxy; containerPortal = ' + project_id + '; proxyType = 1; remoteGlobalIDString = ' + app_target + '; remoteInfo = AikinRecorder;}')
widget_proxy = add('widgetProxy', '{isa = PBXContainerItemProxy; containerPortal = ' + project_id + '; proxyType = 1; remoteGlobalIDString = ' + widget_target + '; remoteInfo = AikinRecorderLiveActivity;}')
watch_proxy = add('watchProxy', '{isa = PBXContainerItemProxy; containerPortal = ' + project_id + '; proxyType = 1; remoteGlobalIDString = ' + watch_target + '; remoteInfo = AikinRecorderWatch;}')
dependency = add('testDependency', '{isa = PBXTargetDependency; target = ' + app_target + '; targetProxy = ' + proxy + ';}')
widget_dependency = add('widgetDependency', '{isa = PBXTargetDependency; target = ' + widget_target + '; targetProxy = ' + widget_proxy + ';}')
watch_dependency = add('watchDependency', '{isa = PBXTargetDependency; target = ' + watch_target + '; targetProxy = ' + watch_proxy + ';}')
add('widgetTarget', '{isa = PBXNativeTarget; buildConfigurationList = ' + config_lists['widget'] + '; buildPhases = ' + refs([uid('widgetSources'), uid('widgetFrameworks')]) + '; buildRules = (); dependencies = (); name = AikinRecorderLiveActivity; productName = AikinRecorderLiveActivity; productReference = ' + widget_product + '; productType = "com.apple.product-type.app-extension";}')
add('watchTarget', '{isa = PBXNativeTarget; buildConfigurationList = ' + config_lists['watch'] + '; buildPhases = ' + refs([uid('watchSources'), uid('watchResources'), uid('watchFrameworks')]) + '; buildRules = (); dependencies = (); name = AikinRecorderWatch; productName = AikinRecorderWatch; productReference = ' + watch_product + '; productType = "com.apple.product-type.application";}')
add('appTarget', '{isa = PBXNativeTarget; buildConfigurationList = ' + config_lists['app'] + '; buildPhases = ' + refs([uid('appSources'), uid('appFrameworks'), uid('appResources'), uid('embedWidgets'), uid('embedWatch')]) + '; buildRules = (); dependencies = ' + refs([widget_dependency, watch_dependency]) + '; name = AikinRecorder; productName = AikinRecorder; productReference = ' + app_product + '; productType = "com.apple.product-type.application";}')
add('testTarget', '{isa = PBXNativeTarget; buildConfigurationList = ' + config_lists['test'] + '; buildPhases = ' + refs([uid('testSources'), uid('testFrameworks')]) + '; buildRules = (); dependencies = ' + refs([dependency]) + '; name = AikinRecorderTests; productName = AikinRecorderTests; productReference = ' + test_product + '; productType = "com.apple.product-type.bundle.unit-test";}')
add('project', '{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600;}; buildConfigurationList = ' + config_lists['project'] + '; compatibilityVersion = "Xcode 15.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = ' + main_group + '; productRefGroup = ' + products + '; projectDirPath = ""; projectRoot = ""; targets = ' + refs([app_target, widget_target, watch_target, test_target]) + ';}')
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n' + '\n'.join(f'{key} = {value};' for key, value in objects.items()) + '\n}; rootObject = ' + project_id + ';}\n', encoding='utf-8')
scheme_dir = PROJECT / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:AikinRecorder.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable(app_target, 'AikinRecorder.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable(test_target, 'AikinRecorderTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(app_target, 'AikinRecorder.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(app_target, 'AikinRecorder.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(scheme_dir / 'AikinRecorder.xcscheme').write_text(scheme, encoding='utf-8')

info = {'CFBundleDisplayName': 'AikinRec', 'CFBundleName': 'AikinRecorder', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)', 'LSRequiresIPhoneOS': True, 'ITSAppUsesNonExemptEncryption': False, 'NSMicrophoneUsageDescription': '录制会议音频，并在你开启实时转写时将语音转换为文字。', 'NSSpeechRecognitionUsageDescription': '使用 Apple 语音识别将你选择的录音转换为文字。', 'NSSupportsLiveActivities': True, 'UIBackgroundModes': ['audio'], 'UIUserInterfaceStyle': 'Dark', 'UILaunchScreen': {'UIColorName': 'LaunchBackground'}, 'UIAppFonts': ['SpecialElite-Regular.ttf'], 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']}
(ROOT / 'AikinRecorder/Resources/Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
privacy = {'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': [], 'NSPrivacyCollectedDataTypes': [], 'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp', 'NSPrivacyAccessedAPITypeReasons': ['C617.1']}]}
(ROOT / 'AikinRecorder/Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps(privacy))
assets = ROOT / 'AikinRecorder/Resources/Assets.xcassets'
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(assets / 'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))
color = assets / 'LaunchBackground.colorset'; color.mkdir(exist_ok=True)
(color / 'Contents.json').write_text(json.dumps({'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': {'red': '0.000', 'green': '0.000', 'blue': '0.000', 'alpha': '1.000'}}}], 'info': {'author': 'xcode', 'version': 1}}))
print(f'Generated {PROJECT} with {len(app_sources)} source files and {len(test_sources)} test files')
