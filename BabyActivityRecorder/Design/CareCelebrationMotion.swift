import SwiftUI

nonisolated enum CareCelebrationKind: Equatable, Sendable { case birthday, pumping }

/// A finite, decorative overlay. It never intercepts a tap or moves the log.
struct CareCelebrationMotion: ViewModifier {
    let trigger: UUID?
    let kind: CareCelebrationKind
    var canPlay = true
    var claimPlayback: ((UUID) -> Bool)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playedID: UUID?
    @State private var visibleID: UUID?

    private struct Request: Equatable {
        let id: UUID?
        let allowed: Bool
    }

    func body(content: Content) -> some View {
        content.overlay {
            if let visibleID, !reduceMotion, scenePhase == .active, canPlay {
                SatinConfetti(kind: kind) { self.visibleID = nil }
                    .id(visibleID).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .task(id: Request(id: trigger, allowed: canPlay && !reduceMotion && scenePhase == .active)) {
            visibleID = nil
            guard let trigger, trigger != playedID, canPlay, !reduceMotion,
                  scenePhase == .active else { return }
            // Let the existing opening or editor dismissal finish first.
            try? await Task.sleep(for: .milliseconds(kind == .birthday ? 850 : 350))
            guard !Task.isCancelled, claimPlayback?(trigger) ?? true else { return }
            playedID = trigger
            visibleID = trigger
        }
        .onDisappear { visibleID = nil }
    }
}

/// Cloth-shaped fragments echo the app's folded mark, with a quiet drifting arc.
private struct SatinConfetti: View {
    let kind: CareCelebrationKind
    let finished: () -> Void
    @State private var playback = 0

    var body: some View {
        let kind = self.kind
        let colors = [LogStyle.forest, LogStyle.amber, LogStyle.blue, LogStyle.ink]
        let cloth = CocoonFold().path(in: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
        return Color.clear
            .keyframeAnimator(initialValue: 0.0, trigger: playback) { _, progress in
                Canvas { context, size in
                    Self.draw(in: context, size: size, progress: progress,
                              kind: kind, colors: colors, cloth: cloth)
                }
                .onChange(of: progress >= 1) { _, ended in
                    if ended { Task { @MainActor in finished() } }
                }
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 3.2)
            }
            .task { playback += 1 }
    }

    nonisolated private static func draw(
        in context: GraphicsContext, size: CGSize, progress: Double,
        kind: CareCelebrationKind, colors: [Color], cloth: Path
    ) {
        let count = kind == .birthday ? 34 : 18
        for index in 0..<count {
            let seed = Double(index)
            let delay = Double(index % 7) * 0.019
            let t = min(1, max(0, (progress - delay) / (1 - delay)))
            guard t > 0, t < 1 else { continue }
            let spread = Double((index * 37) % 101) / 100
            let side = index.isMultiple(of: 2) ? -1.0 : 1.0
            let arc = sin(t * .pi)
            let x: Double
            let y: Double
            if kind == .birthday {
                x = size.width * spread + side * arc * 25 + sin(t * 7 + seed) * 12
                y = -20 + t * (size.height * (0.54 + spread * 0.38))
            } else {
                x = size.width * 0.5 + side * arc * size.width * (0.12 + spread * 0.36)
                y = size.height * 0.83 - arc * size.height * (0.2 + spread * 0.16) + t * 26
            }
            var particle = context
            particle.opacity = min(1, t / 0.08) * min(1, (1 - t) / 0.35) * 0.7
            particle.translateBy(x: x, y: y)
            particle.rotate(by: .radians(seed * 1.71 + t * (side * 4)))
            let width = 4.0 + Double(index % 4)
            let height = 9.0 + Double(index % 5)
            particle.scaleBy(x: width * (0.45 + abs(cos(t * 8 + seed)) * 0.55), y: height)
            particle.fill(cloth, with: .color(colors[index % colors.count]))
        }
    }
}

struct AgeCelebrationHighlight: ViewModifier {
    let trigger: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = self.reduceMotion
        let amber = LogStyle.amber
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, progress in
            let glow = reduceMotion ? 0 : sin(progress * .pi)
            content.background {
                Capsule().fill(amber.opacity(glow * 0.17))
                    .padding(.horizontal, -7).padding(.vertical, -4)
                    .shadow(color: amber.opacity(glow * 0.18), radius: 8)
            }
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 3.2)
        }
    }
}

struct BirthdayNote: View {
    let celebration: AgeCelebration
    let openMilestones: (Int) -> Void
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Birthday").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        dismissButton
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(celebration.title).font(LogStyle.heading(.title3))
                            Text(celebration.message).font(.subheadline).foregroundStyle(LogStyle.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 200)
                    milestoneButton
                }
            } else {
                regularNote
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(LogStyle.card, in: LogStyle.cardShape)
            .overlay { LogStyle.cardShape.strokeBorder(LogStyle.amber.opacity(0.18), lineWidth: 1) }
            .accessibilityAction(.escape, dismiss)
    }

    private var dismissButton: some View {
        Button("Dismiss birthday celebration", systemImage: "xmark", action: dismiss)
            .labelStyle(.iconOnly).font(.system(size: 12, weight: .semibold))
            .frame(width: 44, height: 44).contentShape(.circle)
            .buttonStyle(.plain).foregroundStyle(LogStyle.muted)
            .accessibilityIdentifier("celebration.birthday.dismiss")
    }

    @ViewBuilder private var milestoneButton: some View {
        if let months = celebration.nextCheckpoint {
            Button { openMilestones(months) } label: {
                HStack(spacing: 8) {
                    Text("See what’s ahead").font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right").font(.caption.weight(.semibold))
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(LogPressStyle()).foregroundStyle(LogStyle.forest)
                .accessibilityHint("Opens the \(MilestoneCatalog.title(at: months)) milestone check-in")
                .accessibilityIdentifier("celebration.birthday.milestones")
        }
    }

    private var regularNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkle").font(.title3).foregroundStyle(LogStyle.amber)
                    .padding(.top, 7).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(celebration.title).font(LogStyle.heading(.title3))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(celebration.message).font(.subheadline).foregroundStyle(LogStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                dismissButton
            }
            milestoneButton.padding(.leading, 31)
        }
    }
}

/// Used by pumping history as well as Today, so saves from Settings get feedback too.
struct PumpingRecordPresentation: ViewModifier {
    let store: LogStore
    var canPlay = true
    var showsConfirmation = true

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if showsConfirmation, let celebration = store.pumpingCelebration, store.toast != nil {
                SaveConfirmation(
                    message: String(localized: "A new personal record"), undoID: store.undoID,
                    celebrationDetail: String(localized: "\(store.volumeUnit.quantity(celebration.totalML)) pumped"),
                    undo: { do { try store.undo() } catch { store.report(error) } },
                    dismiss: { store.toast = nil })
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.modifier(CareCelebrationMotion(trigger: store.pumpingCelebration?.id,
                                        kind: .pumping, canPlay: canPlay,
                                        claimPlayback: store.claimPumpingCelebrationMotion))
    }
}
