// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "LittleLogCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LittleLogCore", targets: ["LittleLogCore"])],
    targets: [
        .target(name: "LittleLogCore", path: "BabyActivityRecorder", exclude: [
            "Features", "Design", "Intents", "Assets.xcassets", "Cocoon.icon", "Info.plist",
            "BabyActivityRecorder.entitlements", "ContentView.swift", "MyApp.swift",
            "Persistence/LogStore.swift", "Persistence/WidgetCache.swift"
        ], sources: [
            "Domain", "Persistence/PersistenceController.swift", "Persistence/CloudRecordCodec.swift",
            "Persistence/CareSyncJournal.swift", "Persistence/CareCloudSync.swift",
            "Persistence/CloudSyncMigration.swift", "Persistence/CloudInvitationIdentity.swift",
            "Persistence/CloudSharePreparation.swift"
        ]),
        .testTarget(name: "LittleLogCoreTests", dependencies: ["LittleLogCore"], path: "Tests")
    ]
)
