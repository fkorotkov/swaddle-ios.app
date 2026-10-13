import SwiftUI
import CloudKit
import CoreSpotlight
import AppIntents

@main
struct LittleLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG && targetEnvironment(simulator)
            if MotionReview.isRequested { return }
        #endif
        // Register on every launch, including after an update with unchanged family data.
        LittleLogShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
                if MotionReview.isRequested {
                    MotionReviewRoot()
                } else {
                    appContent
                }
            #else
                appContent
            #endif
        }
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG
            if CloudSchemaSetup.isRequested {
                CloudSchemaSetupView()
            } else {
                FamilyLogRootView()
            }
        #else
            FamilyLogRootView()
        #endif
    }
}

private struct FamilyLogRootView: View {
    @State private var store = LogStore.shared

    var body: some View {
        ContentView(store: store)
            .tint(LogStyle.forest)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
            if MotionReview.isRequested { return true }
        #endif
        application.registerForRemoteNotifications()
        #if DEBUG
        if !CloudSchemaSetup.isRequested { _ = LogStore.shared }
        #else
        _ = LogStore.shared
        #endif
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }
    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            do { try await LogStore.shared.acceptShare(metadata) } catch { LogStore.shared.report(error) }
        }
    }
}
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            do { try await LogStore.shared.acceptShare(cloudKitShareMetadata) } catch { LogStore.shared.report(error) }
        }
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == CSSearchableItemActionType }) {
            LogStore.shared.openSearchActivity(activity)
        }
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in
                do { try await LogStore.shared.acceptShare(metadata) } catch { LogStore.shared.report(error) }
            }
        }
    }
}
