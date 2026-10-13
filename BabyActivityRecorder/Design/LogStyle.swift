import SwiftUI

// Semantic, adaptive colors retain contrast in both appearances.
enum LogStyle {
    static let ink = adaptive(light: (0.09, 0.227, 0.196), dark: (0.95, 0.95, 0.88))
    static let forest = BabyPalette.sage.accent
    // Share the adaptive color with the static system launch screen.
    static let canvas = Color("LaunchCanvas")
    static let card = adaptive(light: (0.925, 0.906, 0.867), dark: (0.085, 0.13, 0.12))
    static let muted = adaptive(light: (0.35, 0.41, 0.385), dark: (0.65, 0.71, 0.68))
    static let blue = adaptive(light: (0.157, 0.341, 0.439), dark: (0.65, 0.81, 0.9))
    static let amber = adaptive(light: (0.529, 0.314, 0.129), dark: (0.9, 0.7, 0.45))
    static let bottleSurface = adaptive(light: (0.882, 0.929, 0.945), dark: (0.09, 0.18, 0.23))
    static let sage = BabyPalette.sage.surface
    static let apricot = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.3, green: 0.23, blue: 0.17, alpha: 1) : UIColor(red: 0.98, green: 0.89, blue: 0.79, alpha: 1) })
    static let milk = Color(red: 0.42, green: 0.62, blue: 0.44)
    static let formula = Color(red: 0.86, green: 0.58, blue: 0.32)

    static func heading(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

struct LogCard<Content: View>: View {
    var color: Color = LogStyle.card
    var verticalPadding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(.horizontal, 20).padding(.vertical, verticalPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: LogStyle.cardShape)
    }
}

struct PrimaryButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.babyPalette) private var palette
    var title: String
    var disabled = false
    var action: () -> Void
    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                button.buttonStyle(SolidPrimaryActionStyle())
            } else {
                button.buttonStyle(.glassProminent)
            }
        }.controlSize(.large).buttonBorderShape(.capsule).tint(palette.accent).disabled(disabled)
    }
    private var button: some View {
        Button(action: action) {
            Text(title).font(.headline).multilineTextAlignment(.center)
                .logValueTransition(value: title)
                .frame(maxWidth: .infinity, minHeight: 26)
                .foregroundStyle(disabled ? Color.secondary : LogStyle.canvas)
        }
    }
}

/// The native prominent style fades disabled labels too far with transparency
/// reduced. A solid fallback keeps the unavailable action readable in both modes.
private struct SolidPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.babyPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 20).padding(.vertical, 15)
            .background(isEnabled ? palette.accent : Color(uiColor: .systemGray4), in: .capsule)
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

struct KeyboardControls: View {
    var nextTitle: String? = nil
    var next: () -> Void = {}
    var done: () -> Void
    @Environment(\.babyPalette) private var palette
    var body: some View {
        HStack {
            if let nextTitle {
                Button(action: next) { Text(nextTitle).frame(minHeight: 44).contentShape(.rect) }
            }
            Spacer()
            Button(action: done) { Text("Done").frame(minWidth: 44, minHeight: 44).contentShape(.rect) }
        }.font(.subheadline.weight(.semibold)).buttonStyle(.plain).foregroundStyle(palette.accent)
    }
}

struct EditorActionBar<Content: View>: View {
    let editing: Bool
    var nextTitle: String? = nil
    var next: () -> Void = {}
    var done: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compactEditing: Bool { editing && verticalSizeClass == .compact }
    var body: some View {
        VStack(spacing: 8) {
            if editing { KeyboardControls(nextTitle: nextTitle, next: next, done: done) }
            // In landscape, give the focused input room. Done reveals the save action.
            if !compactEditing { content }
        }.padding(.horizontal, 16).padding(.vertical, compactEditing ? 4 : 16).background(.bar)
    }
}

struct ChildPicker: View {
    let children: [ChildProfile]
    let selectedID: UUID?
    var select: (UUID) -> Void
    var body: some View {
        if let child = children.first(where: { $0.id == selectedID }) ?? children.first {
            let palette = BabyPalette(gender: child.paletteGender)
            if children.count > 1 {
                Menu {
                    ForEach(children) { item in
                        Button(item.name, systemImage: item.id == child.id ? "checkmark.circle.fill" : "circle") { select(item.id) }
                    }
                } label: {
                    Label(child.name, systemImage: "chevron.up.chevron.down").font(.headline)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                        .logGlass(in: .capsule, tint: palette.surface, fallback: palette.surface, interactive: true)
                }.accessibilityLabel("Selected child, \(child.name)").accessibilityHint("Choose a different child")
            } else {
                Text(child.name).font(.title3.weight(.semibold)).foregroundStyle(palette.accent)
            }
        }
    }
}

struct GenderPicker: View {
    @Binding var gender: ChildGender?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gender (optional)").font(.subheadline)
            if typeSize.isAccessibilitySize { picker.pickerStyle(.menu) }
            else { picker.pickerStyle(.segmented) }
        }
    }
    private var picker: some View {
        Picker("Gender", selection: $gender) {
            Text("Not set").tag(ChildGender?.none)
            ForEach(ChildGender.allCases) { Text($0.title).tag(Optional($0)) }
        }
    }
}

struct VolumePicker: View {
    @Binding var unit: VolumeUnit
    var body: some View {
        Picker("Volume unit", selection: $unit) {
            ForEach(VolumeUnit.allCases) { unit in Text(unit.label).tag(unit) }
        }.logPickerStyle()
    }
}

struct LogDatePicker: View {
    let title: String
    @Binding var selection: Date
    var range: ClosedRange<Date> = .distantPast...Date.now
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                if displayedComponents.contains(.date) {
                    DatePicker(title, selection: $selection, in: range, displayedComponents: .date)
                        .labelsHidden().accessibilityLabel("\(title), date")
                }
                if displayedComponents.contains(.hourAndMinute) {
                    DatePicker(title, selection: $selection, in: range, displayedComponents: .hourAndMinute)
                        .labelsHidden().accessibilityLabel("\(title), time")
                }
            }.datePickerStyle(.compact)
        } else {
            DatePicker(title, selection: $selection, in: range, displayedComponents: displayedComponents).datePickerStyle(.compact)
        }
    }
}

/// Segmented controls use compact text; a native menu keeps large text readable.
private struct LogPickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.menu).controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else { content.pickerStyle(.segmented) }
    }
}

extension View {
    func logPickerStyle() -> some View { modifier(LogPickerStyle()) }
}

struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle").font(.callout)
            .foregroundStyle(.red).accessibilityAddTraits(.isStaticText)
    }
}

extension Activity {
    func detail(unit: VolumeUnit, at date: Date = .now) -> String {
        switch payload {
        case .bottle(let b): return b.unknownML > 0 ? String(localized: "\(unit.quantity(b.totalML)) · Split not recorded") : String(localized: "\(unit.quantity(b.milkML)) milk · \(unit.quantity(b.formulaML)) formula")
        case .diaper(let d): return d.title
        case .nursing(let n): return String(localized: "\(LogAnalytics.duration(n.duration(at: date))) · \(n.finished ? String(localized: "Finished") : n.activeSide.map { String(localized: "\($0.title) running") } ?? String(localized: "Paused"))")
        case .weight(let grams, _): return String(localized: "\((grams / 1000).formatted(.number.precision(.fractionLength(0...3)))) kg")
        case .length(let cm, let originalUnit, let position): return String(localized: "\(originalUnit.quantity(cm)) · \(position.title)")
        case .headCircumference(let cm, let originalUnit): return originalUnit.quantity(cm)
        case .temperature(let celsius, let originalUnit, let method):
            let amount = originalUnit == String(localized: "°F") ? celsius * 9 / 5 + 32 : celsius
            return String(localized: "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(originalUnit)\(method.isEmpty ? "" : String(localized: " · \(method)"))")
        case .careNote: return note
        }
    }
}
