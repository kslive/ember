import ProjectDescription

// MARK: - Shared settings (ad-hoc signing only — no Apple certificates, like Sage)

let baseSettings: SettingsDictionary = [
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "SWIFT_VERSION": "5.0",
    "MARKETING_VERSION": "1.5.0",
    "CURRENT_PROJECT_VERSION": "10",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
]

let deploymentTargets: DeploymentTargets = .macOS("14.4")

// MARK: - Module helper

func mod(
    _ name: String,
    path: String,
    deps: [TargetDependency] = [],
    hasResources: Bool = false
) -> Target {
    var resources: ResourceFileElements? = nil
    if hasResources { resources = ["\(path)/Resources/**"] }
    return .target(
        name: name,
        destinations: .macOS,
        product: .staticFramework,
        bundleId: "com.kslff.ember.\(name.lowercased())",
        deploymentTargets: deploymentTargets,
        sources: ["\(path)/Sources/**"],
        resources: resources,
        dependencies: deps,
        settings: .settings(base: baseSettings)
    )
}

// MARK: - Targets

let core = mod("Core", path: "Modules/Core/Core")
let designSystem = mod("DesignSystem", path: "Modules/Core/DesignSystem", deps: [.target(name: "Core")], hasResources: true)

let audioService = mod("AudioService", path: "Modules/Services/Audio", deps: [.target(name: "Core")])
let callDetectService = mod("CallDetectService", path: "Modules/Services/CallDetect", deps: [.target(name: "Core")])
let transcriptionService = mod("TranscriptionService", path: "Modules/Services/Transcription", deps: [
    .target(name: "Core"), .external(name: "WhisperKit"),
])
let summaryService = mod("SummaryService", path: "Modules/Services/Summary", deps: [
    .target(name: "Core"), .external(name: "MLXLLM"), .external(name: "MLXLMCommon"),
])
let persistenceService = mod("PersistenceService", path: "Modules/Services/Persistence", deps: [
    .target(name: "Core"), .external(name: "GRDB"),
])
let updaterService = mod("UpdaterService", path: "Modules/Services/Updater", deps: [
    .target(name: "Core"),
])
let diarizationService = mod("DiarizationService", path: "Modules/Services/Diarization", deps: [
    .target(name: "Core"), .external(name: "FluidAudio"),
])

let onboardingFeature = mod("OnboardingFeature", path: "Modules/Features/Onboarding", deps: [
    .target(name: "Core"), .target(name: "DesignSystem"),
    .target(name: "TranscriptionService"), .target(name: "SummaryService"),
])
let recordingFeature = mod("RecordingFeature", path: "Modules/Features/Recording", deps: [
    .target(name: "Core"), .target(name: "DesignSystem"),
    .target(name: "AudioService"), .target(name: "TranscriptionService"), .target(name: "SummaryService"),
])
let meetingsFeature = mod("MeetingsFeature", path: "Modules/Features/Meetings", deps: [
    .target(name: "Core"), .target(name: "DesignSystem"),
    .target(name: "PersistenceService"), .target(name: "SummaryService"),
])
let settingsFeature = mod("SettingsFeature", path: "Modules/Features/Settings", deps: [
    .target(name: "Core"), .target(name: "DesignSystem"),
    .target(name: "TranscriptionService"), .target(name: "SummaryService"), .target(name: "UpdaterService"),
])

// mlx-swift looks for its Metal shader library colocated with the Cmlx binary as
// `mlx.metallib` (device.cpp `load_colocated_library`), but Tuist ships it inside
// the framework as `Resources/default.metallib`. Without this, MLX aborts with
// "Failed to load the default metallib" the moment it touches the GPU (summary
// generation). Copy default.metallib → Resources/mlx.metallib (satisfies the
// always-compiled colocated "Resources/mlx" lookup) and re-sign the framework.
let fixMetallibScript = TargetScript.post(
    script: #"""
    set -e
    FW="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Cmlx.framework"
    RES="${FW}/Versions/A/Resources"; [ -d "${RES}" ] || RES="${FW}/Resources"
    if [ -f "${RES}/default.metallib" ]; then
        cp -f "${RES}/default.metallib" "${RES}/mlx.metallib"
        codesign --force --sign - --timestamp=none "${FW}" 2>/dev/null || true
        echo "metallib fix: created ${RES}/mlx.metallib + re-signed Cmlx.framework"
    else
        echo "metallib fix: default.metallib not found under ${FW} (skipped)"
    fi
    """#,
    name: "Fix MLX metallib lookup",
    basedOnDependencyAnalysis: false
)

let lintScript = TargetScript.pre(
    script: #"""
    export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
    if which swiftlint >/dev/null; then
        swiftlint lint --config "${SRCROOT}/.swiftlint.yml" --quiet \
            "${SRCROOT}/App" "${SRCROOT}/Modules" "${SRCROOT}/Tests"
    else
        echo "warning: SwiftLint not installed — run 'brew install swiftlint'"
    fi
    """#,
    name: "SwiftLint",
    basedOnDependencyAnalysis: false
)

let app = Target.target(
    name: "Ember",
    destinations: .macOS,
    product: .app,
    bundleId: "com.kslff.ember",
    deploymentTargets: deploymentTargets,
    infoPlist: .file(path: "App/Resources/Info.plist"),
    sources: ["App/Sources/**"],
    resources: ["App/Resources/Assets.xcassets"],
    entitlements: .file(path: "App/Resources/Ember.entitlements"),
    scripts: [lintScript, fixMetallibScript],
    dependencies: [
        .target(name: "Core"),
        .target(name: "DesignSystem"),
        .target(name: "AudioService"),
        .target(name: "CallDetectService"),
        .target(name: "TranscriptionService"),
        .target(name: "SummaryService"),
        .target(name: "PersistenceService"),
        .target(name: "UpdaterService"),
        .target(name: "DiarizationService"),
        .target(name: "OnboardingFeature"),
        .target(name: "RecordingFeature"),
        .target(name: "MeetingsFeature"),
        .target(name: "SettingsFeature"),
    ],
    settings: .settings(base: baseSettings.merging(["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"]) { _, new in new })
)

let tests = Target.target(
    name: "EmberTests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "com.kslff.ember.tests",
    deploymentTargets: deploymentTargets,
    sources: ["Tests/**"],
    dependencies: [
        .target(name: "Core"),
        .target(name: "DesignSystem"),
        .target(name: "PersistenceService"),
        .target(name: "SummaryService"),
        .target(name: "TranscriptionService"),
        .target(name: "CallDetectService"),
        .target(name: "AudioService"),
        .external(name: "WhisperKit"),
    ],
    settings: .settings(base: baseSettings)
)

let project = Project(
    name: "Ember",
    options: .options(automaticSchemesOptions: .enabled()),
    settings: .settings(base: baseSettings),
    targets: [
        core, designSystem,
        audioService, callDetectService, transcriptionService, summaryService, persistenceService, updaterService,
        diarizationService,
        onboardingFeature, recordingFeature, meetingsFeature, settingsFeature,
        app, tests,
    ],
    schemes: [
        .scheme(
            name: "EmberTests",
            shared: true,
            buildAction: .buildAction(targets: ["EmberTests"]),
            testAction: .targets(["EmberTests"])
        ),
    ]
)
