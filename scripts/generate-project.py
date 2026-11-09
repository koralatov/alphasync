#!/usr/bin/env python3
"""Generate the two app targets and their matching Swift login helpers."""
from hashlib import sha256
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'AlphaSync/AlphaSync.xcodeproj'
objects = {}


def identifier(name):
    return sha256(('AlphaSync 1.6 ' + name).encode()).hexdigest()[:24].upper()


def add(object_key, kind, **values):
    key = identifier(object_key)
    objects[key] = dict(isa=kind, **values)
    return key


def reference(name, path, file_type, source_tree='<group>'):
    return add(name, 'PBXFileReference', path=path, lastKnownFileType=file_type, sourceTree=source_tree)


def phase(object_key, kind, files=(), **values):
    return add(object_key, kind, buildActionMask=2147483647, files=list(files), runOnlyForDeploymentPostprocessing=0, **values)


def configuration_list(name, profile=None, settings=None):
    configurations = []
    for mode in ['Debug', 'Release']:
        build_settings = dict(settings or {})
        if name == 'project':
            build_settings.update(SWIFT_VERSION='6.0', MACOSX_DEPLOYMENT_TARGET='13.0', SDKROOT='macosx',
                ONLY_ACTIVE_ARCH='NO', CLANG_ENABLE_MODULES='YES', ENABLE_USER_SCRIPT_SANDBOXING='NO',
                SWIFT_STRICT_CONCURRENCY='complete', CODE_SIGN_STYLE='Manual', CODE_SIGN_IDENTITY='-',
                CODE_SIGN_INJECT_BASE_ENTITLEMENTS='NO', ENABLE_HARDENED_RUNTIME='YES',
                DEBUG_INFORMATION_FORMAT='dwarf-with-dsym', SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O',
                SWIFT_COMPILATION_MODE='singlefile' if mode == 'Debug' else 'wholemodule')
            if mode == 'Debug':
                build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG'
        values = dict(name=mode, buildSettings=build_settings)
        if profile:
            values['baseConfigurationReference'] = profile
        configurations.append(add(name + mode, 'XCBuildConfiguration', **values))
    return add(name + 'configurations', 'XCConfigurationList', buildConfigurations=configurations,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')


package = add('shared-package', 'XCLocalSwiftPackageReference', relativePath='..')
entry = reference('app-entry', '../Sources/AlphaSyncApp/AlphaSyncApp.swift', 'sourcecode.swift')
launcher = reference('launcher-entry', '../Sources/AlphaSyncLauncher/AlphaSyncLauncher.swift', 'sourcecode.swift')
silicon = reference('silicon-guard', '../Sources/AlphaSyncSilicon/EditionGuard.swift', 'sourcecode.swift')
help_book = reference('help-book', 'AlphaSync Help', 'folder')
icon = reference('selected-icon', '$(AS_APP_ICON_NAME).icns', 'image.icns', 'DERIVED_FILE_DIR')
launcher_icon = reference('launcher-icon', 'Graphics/launcher.icns', 'image.icns')
version = reference('version', 'Build/Version.xcconfig', 'text.xcconfig')
sources = reference('shared-sources', '../Sources', 'folder')
products = []
targets = []
configurations = [version]
schemes = []
for edition, scheme, config_file in [('universal', 'AlphaSyncUniversal', 'Universal.xcconfig'),
                                      ('apple-silicon', 'AlphaSyncAppleSilicon', 'AppleSilicon.xcconfig')]:
    config = reference(edition + '-profile', 'Build/' + config_file, 'text.xcconfig')
    configurations.append(config)
    app_product = add(edition + '-app-product', 'PBXFileReference', explicitFileType='wrapper.application',
                      path='AlphaSync.app', sourceTree='BUILT_PRODUCTS_DIR')
    helper_product = add(edition + '-helper-product', 'PBXFileReference', explicitFileType='wrapper.application',
                         path='AlphaSyncLauncher.app', sourceTree='BUILT_PRODUCTS_DIR')
    products += [app_product, helper_product]
    app_target = identifier(edition + '-app-target')
    helper_target = identifier(edition + '-helper-target')
    for helper in [True, False]:
        key = edition + ('-helper' if helper else '-app')
        product_name = 'AlphaSyncLauncher' if helper else 'AlphaSync'
        settings = dict(PRODUCT_NAME=product_name, PRODUCT_BUNDLE_IDENTIFIER='com.tsoniq.' + product_name,
                        GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='AlphaSyncLauncher-Info.plist' if helper else 'Info.plist',
                        CONFIGURATION_BUILD_DIR='$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/$(AS_BUILD_PROFILE)',
                        SKIP_INSTALL='YES' if helper else 'NO', COMBINE_HIDPI_IMAGES='YES')
        if not helper:
            settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/../Frameworks'
        product = add(key + '-package', 'XCSwiftPackageProductDependency', package=package,
                      productName='AlphaSyncHardware' if helper else 'AlphaSyncUI')
        compiled = [add(key + '-entry-build', 'PBXBuildFile', fileRef=launcher if helper else entry)]
        if not helper and edition == 'apple-silicon':
            compiled.append(add(key + '-guard-build', 'PBXBuildFile', fileRef=silicon))
        phases = [phase(key + '-sources', 'PBXSourcesBuildPhase', compiled),
                  phase(key + '-frameworks', 'PBXFrameworksBuildPhase', [add(key + '-link', 'PBXBuildFile', productRef=product)])]
        dependencies = []
        if helper:
            resources = [add(key + '-icon-build', 'PBXBuildFile', fileRef=launcher_icon)]
        else:
            phases.append(phase(key + '-build-icon', 'PBXShellScriptBuildPhase', name='Build app icon', shellPath='/bin/bash',
                shellScript='bash "$SRCROOT/../scripts/build-app-icon.sh"\n',
                inputPaths=['$(SRCROOT)/../scripts/build-app-icon.sh', '$(SRCROOT)/application.iconset', '$(SRCROOT)/Graphics/application-modern.png'],
                outputPaths=['$(DERIVED_FILE_DIR)/AppIconBuild', '$(DERIVED_FILE_DIR)/$(AS_APP_ICON_NAME).icns']))
            resources = [add(key + '-help-build', 'PBXBuildFile', fileRef=help_book),
                         add(key + '-icon-build', 'PBXBuildFile', fileRef=icon)]
        phases.append(phase(key + '-resources', 'PBXResourcesBuildPhase', resources))
        if not helper:
            phases.append(phase(key + '-build-help', 'PBXShellScriptBuildPhase', name='Build offline Help', alwaysOutOfDate=1,
                shellPath='/bin/bash', shellScript='bash "$SRCROOT/../scripts/build-help.sh"\n',
                inputPaths=['$(SRCROOT)/../scripts/build-help.sh', '$(SRCROOT)/../LICENSE',
                    '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/AlphaSync Help/alphasync-help.html'],
                outputPaths=['$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/AlphaSync Help/licence.html',
                    '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/AlphaSync Help/AlphaSync Help.helpindex']))
            copy = add(key + '-helper-copy', 'PBXBuildFile', fileRef=helper_product, settings={'ATTRIBUTES': ['CodeSignOnCopy']})
            phases.append(phase(key + '-login-items', 'PBXCopyFilesBuildPhase', [copy], name='Embed login helper',
                                dstPath='Contents/Library/LoginItems', dstSubfolderSpec=1))
            proxy = add(key + '-helper-proxy', 'PBXContainerItemProxy', containerPortal=identifier('project'), proxyType=1,
                        remoteGlobalIDString=helper_target, remoteInfo=scheme + 'Launcher')
            dependencies = [add(key + '-helper-dependency', 'PBXTargetDependency', target=helper_target, targetProxy=proxy)]
        target = add(key + '-target', 'PBXNativeTarget', name=scheme + ('Launcher' if helper else ''), productName=product_name,
                     productReference=helper_product if helper else app_product, productType='com.apple.product-type.application',
                     buildConfigurationList=configuration_list(key, config, settings), buildPhases=phases, buildRules=[],
                     dependencies=dependencies, packageProductDependencies=[product])
        targets.append(target)
    schemes.append((scheme, app_target))

product_group = add('products', 'PBXGroup', name='Products', children=products, sourceTree='<group>')
main_group = add('main-group', 'PBXGroup', children=[entry, launcher, silicon, sources, help_book, icon, launcher_icon] + configurations + [product_group], sourceTree='<group>')
project = add('project', 'PBXProject', attributes={'LastUpgradeCheck': '1660', 'BuildIndependentTargetsInParallel': 'YES'},
              buildConfigurationList=configuration_list('project'), compatibilityVersion='Xcode 14.0', developmentRegion='en',
              hasScannedForEncodings=0, knownRegions=['en', 'Base'], mainGroup=main_group, productRefGroup=product_group,
              projectDirPath='', projectRoot='', targets=targets, packageReferences=[package])


def serialise(value, indent=0):
    prefix = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join(prefix + '\t' + json.dumps(str(k)) + ' = ' + serialise(v, indent + 1) + ';\n' for k, v in value.items()) + prefix + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(prefix + '\t' + serialise(v, indent + 1) + ',\n' for v in value) + prefix + ')'
    return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=False)


PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialise(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + '\n')
scheme_folder = PROJECT / 'xcshareddata/xcschemes'
scheme_folder.mkdir(parents=True, exist_ok=True)
for old in scheme_folder.glob('*.xcscheme'):
    old.unlink()
for name, target in schemes:
    root = ET.Element('Scheme', LastUpgradeVersion='1660', version='1.3')
    build = ET.SubElement(root, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
    entries = ET.SubElement(build, 'BuildActionEntries')
    entry_node = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='YES', buildForArchiving='YES', buildForAnalyzing='YES')
    attributes = dict(BuildableIdentifier='primary', BlueprintIdentifier=target, BuildableName='AlphaSync.app', BlueprintName=name, ReferencedContainer='container:AlphaSync.xcodeproj')
    ET.SubElement(entry_node, 'BuildableReference', **attributes)
    for action, config in [('LaunchAction', 'Debug'), ('ProfileAction', 'Release')]:
        node = ET.SubElement(root, action, buildConfiguration=config, useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugServiceExtension='internal', allowLocationSimulation='YES')
        if action == 'LaunchAction':
            node.set('selectedDebuggerIdentifier', 'Xcode.DebuggerFoundation.Debugger.LLDB')
            node.set('selectedLauncherIdentifier', 'Xcode.IDEFoundation.Launcher.LLDB')
        runnable = ET.SubElement(node, 'BuildableProductRunnable', runnableDebuggingMode='0')
        ET.SubElement(runnable, 'BuildableReference', **attributes)
    ET.SubElement(root, 'AnalyzeAction', buildConfiguration='Debug')
    ET.SubElement(root, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
    ET.indent(root, space='  ')
    ET.ElementTree(root).write(scheme_folder / (name + '.xcscheme'), encoding='UTF-8', xml_declaration=True)
print('Generated two app targets and their matching launch helpers.')
