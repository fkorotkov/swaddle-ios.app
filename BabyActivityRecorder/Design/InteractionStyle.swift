import SwiftUI

/// Glass belongs to controls, while the log itself stays on quiet, solid surfaces.
private struct LogGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let fallback: Color
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased || !isEnabled {
            content.background(fallback, in: shape)
        } else {
            content.glassEffect(.regular.tint(tint).interactive(interactive && isEnabled && !reduceMotion), in: shape)
        }
    }
}

struct LogPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: configuration.isPressed)
    }
}

private struct LogValueTransition<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: value)
    }
}

enum LogPresentationSource: Hashable { case bottle, breastfeeding, pump, importNotes }

private struct LogEditorTransition: ViewModifier {
    let source: LogPresentationSource?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        // The source is captured when opening the sheet. Changing the system's
        // motion setting must not swap this branch and recreate an unsaved editor.
        if let source {
            content.navigationTransition(.zoom(sourceID: source, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    func logGlass<S: Shape>(in shape: S, tint: Color? = nil, fallback: Color = LogStyle.card, interactive: Bool = false) -> some View {
        modifier(LogGlassSurface(shape: shape, tint: tint, fallback: fallback, interactive: interactive))
    }

    func logValueTransition(value: some Equatable) -> some View {
        modifier(LogValueTransition(value: value))
    }

    func logEditorTransition(source: LogPresentationSource?, namespace: Namespace.ID) -> some View {
        modifier(LogEditorTransition(source: source, namespace: namespace))
    }
}

struct SaveConfirmation: View {
    let message: String
    let undoID: UUID?
    var celebrationDetail: String? = nil
    var undo: () -> Void
    var dismiss: () -> Void
    @Environment(\.babyPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var symbolSize = 20

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(celebrationDetail == nil ? .subheadline : LogStyle.heading(.title3))
                        .fixedSize(horizontal: false, vertical: true)
                    if let celebrationDetail {
                        Text(celebrationDetail).font(.caption).foregroundStyle(LogStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } icon: {
                Image(systemName: celebrationDetail != nil ? "sparkle" : undoID == nil ? "checkmark.circle" : "checkmark.circle.fill")
                    .font(.system(size: min(symbolSize, 28), weight: .semibold))
                    .foregroundStyle(celebrationDetail == nil ? palette.accent : LogStyle.amber)
                    .symbolEffect(.bounce, value: undoID)
                    .symbolEffectsRemoved(reduceMotion)
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if undoID != nil {
                Button(action: undo) {
                    Text("Undo").font(.subheadline.bold())
                        .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 8).contentShape(.rect)
                }.buttonStyle(.plain).foregroundStyle(palette.accent)
            }
            Button("Dismiss confirmation", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).font(.caption.weight(.semibold))
                .frame(width: 44, height: 44).contentShape(.circle)
                .buttonStyle(.plain).foregroundStyle(LogStyle.muted)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .logGlass(in: .rect(cornerRadius: 26))
            .accessibilityAction(.escape, dismiss)
    }
}
