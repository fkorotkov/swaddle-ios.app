import SwiftUI
import CoreSpotlight

struct ContentView: View {
    let store: LogStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Int
    @State private var todayOpenRequest = UUID()
    @State private var widgetBottleRoute: LogRoute?
    @State private var showingSettings = false
    @State private var openingMotion: CocoonOpeningSession
    @State private var milestoneRequest: MilestoneCheckpointRequest?

    init(store: LogStore, openingDuration: TimeInterval = 0.85) {
        self.store = store
        #if DEBUG && targetEnvironment(simulator)
        tab = MotionReview.has("--milestones") ? 2 : MotionReview.has("--trends") ? 1 : 0
        #else
        tab = 0
        #endif
        _openingMotion = State(initialValue: CocoonOpeningSession(duration: openingDuration))
    }
    var body: some View {
        Group {
            if !store.isReady {
                ContentUnavailableView {
                    Label("Your log is unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? String(localized: "Loading your family…"))
                } actions: {
                    Button("Try again") { Task { await store.checkAccount(); await store.syncCloud(); store.reload() } }
                }
            } else if store.snapshot.family == nil {
                WelcomeView(store: store, openingMotion: openingMotion)
            } else if store.canEdit && !store.snapshot.caregivers.contains(where: { $0.id == store.caregiverID }) {
                JoinProfileView(store: store)
            } else {
                TabView(selection: $tab) {
                    Tab("Today", systemImage: "sun.max", value: 0) {
                        TodayView(
                            store: store, openRequest: todayOpenRequest,
                            openingMotion: openingMotion, settingsPresentation: $showingSettings,
                            isCurrentTab: tab == 0, openMilestones: { months in
                                guard let child = store.selectedChild else { return }
                                milestoneRequest = MilestoneCheckpointRequest(childID: child.id, months: months)
                                tab = 2
                            })
                    }
                    Tab("Trends", systemImage: "chart.xyaxis.line", value: 1) {
                        TrendsView(store: store, settingsPresentation: $showingSettings)
                    }
                    Tab("Milestones", systemImage: "leaf.fill", value: 2) {
                        MilestoneJourneyView(store: store, settingsPresentation: $showingSettings,
                                             checkpointRequest: milestoneRequest)
                            .environment(\.calendar, familyCalendar)
                            .environment(\.timeZone, familyCalendar.timeZone)
                    }
                }
            }
        }
        .background(LogStyle.canvas)
        .foregroundStyle(LogStyle.ink)
        .babyPalette(for: store.selectedChild?.paletteGender)
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
        .sheet(item: Binding(get: { store.siriNavigation }, set: { store.siriNavigation = $0 })) { request in
            SiriDestinationView(store: store, request: request)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            openingMotion.settle()
            showingSettings = false
            store.openSearchActivity(activity)
        }
        .sheet(item: $widgetBottleRoute) { route in
            ActivityEditor(store: store, route: route)
        }
        .onOpenURL { url in
            guard url.scheme == "littlelog" else { return }
            openingMotion.settle()
            showingSettings = false
            store.reload()
            do {
                if url.host == "widget-diaper" {
                    try store.openWidgetDiaper(url)
                    widgetBottleRoute = nil
                    store.siriNavigation = nil
                    todayOpenRequest = UUID()
                    tab = 0
                    return
                }
                switch try LogDestination.resolve(url, in: store.snapshot, ready: store.isReady) {
                case .today(let childID):
                    store.selectedChildID = childID
                    todayOpenRequest = UUID()
                    tab = 0
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    if let action = items.first(where: { $0.name == "widgetError" })?.value,
                       let familyID = store.snapshot.family?.id,
                       let message = WidgetCache.quickLogFailure(target: "\(familyID)/\(childID)", action: action) {
                        store.report(LogError.message(message))
                        WidgetCache.setQuickLogFailure(nil, target: "\(familyID)/\(childID)", action: action)
                    }
                case .bottle(let childID):
                    guard store.canEdit else { throw LogError.message(String(localized: "This family is shared with view-only access.")) }
                    store.selectedChildID = childID
                    todayOpenRequest = UUID()
                    tab = 0
                    widgetBottleRoute = LogRoute(kind: .bottle, childID: childID)
                case .family: showingSettings = true
                }
            } catch { store.report(error) }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                store.reload()
                Task { await store.checkAccount(); await store.syncCloud() }
            }
        }
        .onChange(of: store.siriNavigation?.id) { _, request in
            if request != nil { openingMotion.settle() }
        }
        .onChange(of: showingSettings) { _, presented in
            if presented { openingMotion.settle() }
        }
        .onChange(of: tab) { _, selected in
            if selected != 0 { openingMotion.settle() }
        }
        .alert(
            "Couldn’t complete that",
            isPresented: Binding(
                get: { store.errorMessage != nil && store.isReady },
                set: { if !$0 { store.clearError() } })
        ) {
            Button("OK") { store.clearError() }
        } message: { Text(store.errorMessage ?? "") }
    }
    private var familyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current
        return calendar
    }
}

struct WelcomeView: View {
    let store: LogStore
    var openingMotion: CocoonOpeningSession? = nil
    @State private var childName = ""
    @State private var gender: ChildGender?
    @State private var name = ""
    @State private var mother = true
    @State private var unit: VolumeUnit = .ml
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    CocoonOpeningMark(session: openingMotion, size: 144)
                        .frame(width: 100, height: 116).padding(.top, 4)
                    Text("Little moments.\nA little clearer.")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("A shared record of feeding, changes, and growing. One less thing to remember.")
                        .font(.title3).foregroundStyle(.secondary)
                    LogCard {
                        VStack(alignment: .leading, spacing: 18) {
                            TextField("Your child’s name", text: $childName).textContentType(.givenName).accessibilityIdentifier("onboarding.child")
                            GenderPicker(gender: $gender)
                            Divider()
                            TextField("Your name", text: $name).textContentType(.givenName).accessibilityIdentifier("onboarding.caregiver")
                            Divider()
                            Toggle("I’ll track my pumping", isOn: $mother)
                            VolumePicker(unit: $unit)
                        }
                    }
                    if let error { ErrorNotice(message: error) }
                    PrimaryButton(title: String(localized: "Start our family log"), disabled: childName.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty) {
                        do { try store.createFamily(childName: childName, caregiverName: name, mother: mother, unit: unit, gender: gender) }
                        catch { self.error = error.localizedDescription }
                    }
                    Text("Already invited? Open your family’s iCloud invitation to join. You can add more children and invite caregivers in Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(LogStyle.canvas).navigationTitle("Swaddle").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
        }.babyPalette(for: gender)
    }
}

struct JoinProfileView: View {
    let store: LogStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var mother = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    JoinInvitationStatusView(ready: store.caregiverIdentityReady,
                                             checking: store.isCheckingCaregiverIdentity,
                                             message: store.caregiverIdentityMessage,
                                             invitationURL: store.caregiverInvitationURL,
                                             diagnostics: store.caregiverIdentityDiagnostic) {
                        Task { await store.refreshCaregiverIdentity(force: true) }
                    }
                }
                Section {
                    TextField("Your name", text: $name).textContentType(.givenName)
                    Toggle("I’ll track my pumping", isOn: $mother)
                } header: {
                    Text("Your name in the family log")
                } footer: {
                    Text("If your invitation is linked to an existing caregiver, we’ll use that profile and keep its history.")
                }
                Button("Continue") {
                    do { try store.createJoinedCaregiver(name: name, pumping: mother) }
                    catch { store.report(error) }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit || !store.caregiverIdentityReady)
            }.navigationTitle("Join your family")
                .navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .task(id: scenePhase) {
                    if scenePhase == .active { await store.refreshCaregiverIdentity() }
                }
        }
    }
}

private struct JoinInvitationStatusView: View {
    let ready: Bool
    let checking: Bool
    let message: String?
    let invitationURL: URL?
    var diagnostics: String? = nil
    var retry: () -> Void
    @State private var copiedDiagnostics = false

    var body: some View {
        if ready {
            Label("Invitation accepted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(LogStyle.forest)
        } else {
            if checking {
                ProgressView("Checking your iCloud invitation…")
            } else {
                Label("Finish joining your family", systemImage: "person.crop.circle.badge.clock")
                    .font(.headline)
            }
            Text(message ?? String(localized: "We’re checking your invitation and looking for your caregiver profile."))
                .foregroundStyle(.secondary)
            if !checking {
                Button("Check again", systemImage: "arrow.clockwise", action: retry)
                if let invitationURL {
                    Link(destination: invitationURL) {
                        Label("Open iCloud invitation", systemImage: "envelope.open")
                    }
                }
                if let diagnostics, message != nil {
                    Button(copiedDiagnostics ? String(localized: "Details copied") : String(localized: "Copy troubleshooting details"),
                           systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = diagnostics
                        copiedDiagnostics = true
                    }
                    .onChange(of: diagnostics) { copiedDiagnostics = false }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Join family · Waiting") {
    NavigationStack {
        Form {
            Section {
                JoinInvitationStatusView(ready: false, checking: false,
                                         message: CloudInvitationError.pending.localizedDescription,
                                         invitationURL: URL(string: "https://www.icloud.com/share/example"), retry: {})
            }
            Section("Your name in the family log") {
                TextField("Your name", text: .constant("Alex"))
                Toggle("I’ll track my pumping", isOn: .constant(true))
            }
            Button("Continue", action: {}).disabled(true)
        }.navigationTitle("Join your family").navigationBarTitleDisplayMode(.inline)
    }.tint(LogStyle.forest)
}
#endif
