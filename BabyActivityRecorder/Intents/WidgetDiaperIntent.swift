import AppIntents
import Foundation

/// Shared declaration, with writes owned exclusively by the app's existing persistence stack.
struct WidgetDiaperIntent: AppIntent {
    static var title: LocalizedStringResource { "Log a diaper from the Lock Screen" }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    // Dynamic foreground support replaces ForegroundContinuableIntent on iOS 26.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Family and child") var target: String
    @Parameter(title: "Contents") var action: String
    @Parameter(title: "Entry") var command: String
    @Parameter(title: "Undo") var undo: Bool

    init() {}
    init(target: String, action: WidgetQuickAction, commandID: UUID, undo: Bool = false) {
        self.target = target
        self.action = action.rawValue
        self.command = commandID.uuidString
        self.undo = undo
    }

    @MainActor func perform() async throws -> some IntentResult {
        do {
            guard let kind = WidgetQuickAction(rawValue: action), kind.diaper != nil,
                  let commandID = UUID(uuidString: command) else {
                throw LogError.message("Choose your child again in Edit Widget.")
            }
            #if WIDGET_EXTENSION
            // Never write a cache as if it were the family log if the OS chooses the wrong process.
            try requireMainApp()
            #else
            let store = LogStore.shared
            // Use the same locally known membership as in-app logging, including offline.
            // Account refresh and cloud permission checks continue on the existing sync path.
            if undo {
                try store.undoWidgetDiaper(target: target, action: kind, recordID: commandID)
            } else {
                try store.recordWidgetDiaper(target: target, action: kind, commandID: commandID)
            }
            // Core Data has committed; the existing CKSyncEngine outbox owns upload/retry.
            WidgetCache.setQuickLogFailure(nil, target: target, action: action)
            #endif
        } catch {
            WidgetCache.setQuickLogFailure(error.localizedDescription, target: target, action: action)
            throw error
        }
        return .result()
    }

    #if WIDGET_EXTENSION
    private func requireMainApp() throws {
        throw LogError.message("Open Swaddle to complete this entry.")
    }
    #endif
}
