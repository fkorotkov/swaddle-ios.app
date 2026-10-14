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

struct AppOpenURL: Identifiable {
    let id = UUID()
    let url: URL
}

extension Notification.Name {
    static let familyInvitationOpened = Notification.Name("SwaddleFamilyInvitationOpened")
}

struct FamilyLogRootView: View {
    let store: LogStore
    @State private var demoSession = DemoSession()
    @State private var externalURL: AppOpenURL?

    init(store: LogStore? = nil) { self.store = store ?? .shared }

    var body: some View {
        let displayedStore = demoSession.store ?? store
        VStack(spacing: 0) {
            if displayedStore.isDemo { DemoBanner() }
            ContentView(store: displayedStore, externalURL: $externalURL)
                .id(displayedStore.isDemo)
                .defaultAppStorage(displayedStore.defaults)
        }
            .background(LogStyle.canvas)
            .environment(\.demoSession, demoSession)
            .tint(LogStyle.forest)
            .onOpenURL { url in
                guard url.scheme == "littlelog" else { return }
                // Widgets always address the real family. Exit first, then deliver once
                // to the newly visible ContentView, never to fictional record IDs.
                demoSession.exit()
                externalURL = AppOpenURL(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                demoSession.exit()
                store.openSearchActivity(activity)
            }
            .onReceive(NotificationCenter.default.publisher(for: .familyInvitationOpened)) { _ in
                demoSession.exit()
            }
            .onChange(of: store.siriNavigation?.id) { _, request in
                if request != nil { demoSession.exit() }
            }
            #if DEBUG && targetEnvironment(simulator)
            .task {
                if MotionReview.isRequested && MotionReview.has("--demo") {
                    do { try demoSession.start() } catch { store.report(error) }
                }
            }
            #endif
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
        NotificationCenter.default.post(name: .familyInvitationOpened, object: nil)
        Task { @MainActor in
            do { try await LogStore.shared.acceptShare(metadata) } catch { LogStore.shared.report(error) }
        }
    }
}
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .familyInvitationOpened, object: nil)
        Task { @MainActor in
            do { try await LogStore.shared.acceptShare(cloudKitShareMetadata) } catch { LogStore.shared.report(error) }
        }
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let activity = connectionOptions.userActivities.first(where: { $0.activityType == CSSearchableItemActionType }) {
            LogStore.shared.openSearchActivity(activity)
        }
        if let metadata = connectionOptions.cloudKitShareMetadata {
            NotificationCenter.default.post(name: .familyInvitationOpened, object: nil)
            Task { @MainActor in
                do { try await LogStore.shared.acceptShare(metadata) } catch { LogStore.shared.report(error) }
            }
        }
    }
}
