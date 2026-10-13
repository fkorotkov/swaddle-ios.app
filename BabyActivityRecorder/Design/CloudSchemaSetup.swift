#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftUI

/// Explicit developer launch mode. Never compiled into a Release or TestFlight build.
enum CloudSchemaSetup {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--initialize-cloudkit-schema")
    }

    nonisolated static func initialize() throws {
        #if targetEnvironment(simulator)
        throw NSError(domain: "SwaddleSchemaSetup", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Run schema setup on a signed development iPhone with iCloud enabled."
        ])
        #else
        // A separate store prevents this utility from opening the family's local databases.
        // Only the private database needs initialization; the shared database uses its schema.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SwaddleSchema-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let container = NSPersistentCloudKitContainer(name: "SwaddleSchemaSetup", managedObjectModel: PersistenceController.model())
        let description = NSPersistentStoreDescription(url: directory.appending(path: "Schema.sqlite"))
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        let cloudOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: PersistenceController.cloudContainer)
        cloudOptions.databaseScope = .private
        description.cloudKitContainerOptions = cloudOptions
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
        if let loadError { throw loadError }
        // Core Data generates representative records and removes them after creating all fields.
        try container.initializeCloudKitSchema(options: [])
        #endif
    }
}

struct CloudSchemaSetupView: View {
    @State private var started = false
    @State private var finished = false
    @State private var message = "Preparing the development CloudKit schema…"

    var body: some View {
        VStack(spacing: 16) {
            if !finished { ProgressView() }
            Text("Development schema setup").font(.title2)
            Text(message).multilineTextAlignment(.center)
            Text("Quit and relaunch normally to return to your family log.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .task {
            guard !started else { return }
            started = true
            do {
                try await Task.detached(priority: .userInitiated) {
                    try CloudSchemaSetup.initialize()
                }.value
                message = "Preparing the development sharing schema…"
                try await CloudShareSchemaSetup.initialize(containerIdentifier: PersistenceController.cloudContainer)
                message = "Development data and sharing schemas initialized. Review them in CloudKit Console before deploying to production."
                print("SWADDLE_SCHEMA_SETUP_SUCCEEDED")
            } catch {
                message = error.localizedDescription
                print("SWADDLE_SCHEMA_SETUP_FAILED: \(error)")
            }
            finished = true
        }
    }
}
#endif
