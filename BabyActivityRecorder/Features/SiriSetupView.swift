import SwiftUI

struct SiriSetupView: View {
    let store: LogStore
    var childName = String(localized: "my baby")
    @Environment(\.babyPalette) private var palette
    var body: some View {
        List {
            if store.isDemo {
                Section { Text("Widgets and Siri use your own family log, not the demo.") }
            }
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(palette.accent)
                    Text("Hands full.\nJust ask Siri.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Record the moment. Hear the answer. Keep your attention on your baby.")
                        .font(.body).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            if #available(iOS 27.0, *) {
                Section {
                    Toggle("Care history in Siri & Search", isOn: Binding(get: { store.siriDiscoveryEnabled }, set: { enabled in
                        do { try store.setSiriDiscoveryEnabled(enabled) } catch { store.report(error) }
                    })).disabled(store.isDemo).accessibilityIdentifier("siri.careHistory")
                    if store.siriDiscoveryEnabled {
                        Label(store.siriDiscoveryStatus, systemImage: "checkmark.shield").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Go further with Apple Intelligence") } footer: {
                    Text("On by default on this device. Siri and system search can discover your family’s saved records and understand the record you’re viewing. Turn this off to remove Swaddle’s search index and stop sharing onscreen context. Voice logging and feeding totals still work.")
                }
                Section("More ways to ask") {
                    Label("Find and read care records", systemImage: "text.magnifyingglass")
                    Label("Create a care note for your child", systemImage: "note.text.badge.plus")
                    Label("Ask about the record you’re viewing", systemImage: "viewfinder")
                    Text("These capabilities require care history access and compatible Apple Intelligence settings. Siri’s choice of action and wording depend on system support. A care note saves text; it doesn’t create a feeding or diaper entry.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.siriDiscoveryEnabled {
                        NavigationLink("Browse available care records") { CareSearchView(store: store) }
                    }
                }
            }
            Section("Record with your voice") {
                phrase("Log a pee and poo diaper in Swaddle", detail: "Or say “wet and dirty” instead of “pee and poo”.")
                phrase("Record a bottle in Swaddle", detail: "Siri asks for the details it needs.")
                phrase("Record the usual bottle in Swaddle", detail: "Confirms the last amounts before saving.")
                phrase("Log expressed milk in Swaddle", detail: "Saved to the pumping caregiver, separate from feeding.")
                Text("If Siri is unsure, say “Record a diaper in Swaddle”, then answer “Both”.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Ask and listen") {
                phrase("How much did \(childName) eat in Swaddle?", detail: "Breast milk, formula, and breastfeeding time for the last 24 hours.")
                phrase("When was the last feed in Swaddle?", detail: "Reads the latest completed feed.")
                Text("You can also choose Today, Yesterday, and mL or oz. With one child, no name is needed; with several, Siri asks who you mean.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Say “in Swaddle” when asking. Your device may ask you to allow Swaddle actions the first time. No custom shortcut needs to be built.")
                Text("Your device must authenticate before reading or changing your family’s log.")
            } header: { Text("Ready when you are") }
        }.navigationTitle("Siri").navigationBarTitleDisplayMode(.inline)
    }
    private func phrase(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(Text(title))”").font(.body.weight(.medium))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}

#if DEBUG
#Preview("Siri") {
    @Previewable @State var store = PreviewData.makeStore()
    NavigationStack { SiriSetupView(store: store) }.tint(LogStyle.forest)
}
#Preview("Siri · Large text") {
    @Previewable @State var store = PreviewData.makeStore()
    NavigationStack { SiriSetupView(store: store) }.tint(LogStyle.forest).environment(\.dynamicTypeSize, .accessibility3)
}
#endif
