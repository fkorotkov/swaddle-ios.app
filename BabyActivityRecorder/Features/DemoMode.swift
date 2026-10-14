import SwiftUI

/// A process-only session. Only disposable display preferences use a separate defaults
/// domain; care records live in memory. Nothing resumes a demo on the next launch.
@MainActor @Observable
final class DemoSession {
    private(set) var store: LogStore?
    private let defaultsName: String

    init(defaultsName: String = "com.github.fkorotkov.LittleLog.demo") {
        self.defaultsName = defaultsName
    }

    func start(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) throws {
        guard store == nil, let defaults = UserDefaults(suiteName: defaultsName) else { return }
        defaults.removePersistentDomain(forName: defaultsName)
        let example = try DemoFamily.make(now: now, calendar: calendar)
        let demo = LogStore(defaults: defaults, publishesWidgets: false, isDemo: true)
        try demo.loadDemoFamily(example, now: now)
        store = demo
    }

    func exit() {
        store = nil
        UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
    }
}

extension EnvironmentValues {
    @Entry var demoSession: DemoSession? = nil
}

struct DemoBanner: View {
    @Environment(\.demoSession) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingInfo = false
    var body: some View {
        HStack(spacing: 12) {
            Button { showingInfo = true } label: {
                if typeSize.isAccessibilitySize {
                    Image(systemName: "sparkles").font(.title3)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(minWidth: 44)
                } else {
                    Label("Demo · sample data only", systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).multilineTextAlignment(.leading)
                }
            }.buttonStyle(.plain).frame(minHeight: 44)
                .accessibilityLabel("Demo · sample data only")
                .accessibilityIdentifier("demo.info")
            Spacer(minLength: 4)
            Button("Exit demo") { session?.exit() }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("demo.exit")
        }
        .foregroundStyle(LogStyle.forest)
        .padding(.horizontal, 22).frame(maxWidth: 1240)
        .frame(maxWidth: .infinity).background(LogStyle.sage)
        .sheet(isPresented: $showingInfo) { DemoIntroductionView(isActive: true) }
    }
}

struct DemoIntroductionView: View {
    var isActive = false
    @Environment(\.demoSession) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(LogStyle.forest)
                        .accessibilityHidden(true)
                    Text("Meet Robin & family.").font(LogStyle.heading(.largeTitle))
                    Text("Three months of growing, with Sam and Alex. Try logging a bottle, explore pumping and growth charts, or check in on a milestone.")
                        .font(.title3).foregroundStyle(.secondary)
                    LogCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Make yourself at home", systemImage: "hand.tap")
                                .font(.headline)
                            Text("All records are fictional. You can change them freely; they never sync to iCloud or appear in your widgets or Siri.")
                            Divider()
                            Text("Tap Exit demo anytime. Fully closing the app also ends the demo. Your own family log stays untouched.")
                        }
                    }
                    Text("Robin was born six days before the due date, at 39 weeks and 1 day. This is full term, so growth charts use age since birth.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Example records show how Swaddle works, not care recommendations or targets.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { ErrorNotice(message: error) }
                    if isActive {
                        PrimaryButton(title: String(localized: "Keep exploring")) { dismiss() }
                    } else {
                        PrimaryButton(title: String(localized: "Start demo")) {
                            do { try session?.start(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("demo.start")
                    }
                }.padding(24).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.background(LogStyle.canvas).navigationTitle("Explore Swaddle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.tint(LogStyle.forest)
    }
}
