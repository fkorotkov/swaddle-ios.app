import Lottie
import SwiftUI

/// One small, offline scene per skill. Playback stays local to this view so an
/// illustration never invalidates an observation draft or the milestone list.
struct MilestoneIllustrationView: View {
    let skill: MilestoneSkill
    var caregiverSex: CaregiverSex?
    var showsStillImage = false
    var maximumArtworkWidth: CGFloat = 420
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var userPaused = false
    @State private var playback: LottiePlaybackMode

    init(skill: MilestoneSkill, caregiverSex: CaregiverSex? = nil, showsStillImage: Bool = false, maximumArtworkWidth: CGFloat = 420) {
        self.skill = skill
        self.caregiverSex = caregiverSex
        self.showsStillImage = showsStillImage
        self.maximumArtworkWidth = maximumArtworkWidth
        _playback = State(initialValue: .paused(at: .progress(0)))
    }

    private var poster: CGFloat { CGFloat(MilestoneIllustrationCatalog.posterFrame(for: skill)) }

    private var canAnimate: Bool { visible && scenePhase == .active && !reduceMotion && !showsStillImage }
    private var isPlaying: Bool {
        if case .playing = playback { return true }
        return false
    }
    private var animation: LottieAnimation? {
        guard MilestoneIllustrationCatalog.descriptions[skill.id] != nil else { return nil }
        return MilestoneAnimationCache.animation(for: skill, caregiverSex: caregiverSex)
    }

    var body: some View {
        if let animation {
            VStack(spacing: 0) {
                LottieView(animation: animation)
                    .configuration(LottieConfiguration(renderingEngine: .coreAnimation))
                    .playbackMode(reduceMotion || showsStillImage ? .paused(at: .frame(poster)) : playback)
                    .backgroundBehavior(.pause)
                    .aspectRatio(1.5, contentMode: .fit)
                    .frame(maxWidth: maximumArtworkWidth)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(MilestoneIllustrationCatalog.descriptions[skill.id] ?? skill.title)
                    .accessibilityIdentifier("milestone-illustration-\(skill.id)")
                    .onScrollVisibilityChange(threshold: 0.25) { isVisible in
                        visible = isVisible
                        updatePlayback()
                    }
                HStack {
                    Text("Illustration")
                        .font(.caption).foregroundStyle(LogStyle.muted)
                    Spacer(minLength: 12)
                    if !reduceMotion && !showsStillImage {
                        Button(action: togglePlayback) {
                            Label(isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                                  systemImage: isPlaying ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.semibold))
                                .frame(minWidth: 70, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(LogPressStyle())
                        .foregroundStyle(LogStyle.forest)
                        .accessibilityHint(isPlaying ? String(localized: "Pauses the looping illustration") : String(localized: "Resumes the looping illustration"))
                        .accessibilityIdentifier("milestone-illustration-playback")
                    }
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
                .background(LogStyle.card)
            }
            // A quiet paper ground keeps the original ink and skin tones legible
            // in both app appearances without recoloring the illustration.
            .background(Color(red: 0.965, green: 0.949, blue: 0.906))
            .clipShape(.rect(cornerRadius: 24))
            .onChange(of: scenePhase) { _, _ in updatePlayback() }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    playback = .paused(at: .frame(poster))
                } else { updatePlayback() }
            }
            .onDisappear {
                visible = false
                playback = .paused(at: .currentFrame)
            }
        }
    }

    private func updatePlayback() {
        if canAnimate && !userPaused {
            // Keep the full range when resuming: a nil start would repeat only
            // the remainder of the scene. Core Animation resumes the current
            // frame for the first loop, then plays the complete six-second loop.
            playback = .playing(.fromProgress(0, toProgress: 1, loopMode: .loop))
        } else {
            playback = .paused(at: .currentFrame)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            userPaused = true
            playback = .paused(at: .currentFrame)
        } else {
            userPaused = false
            updatePlayback()
        }
    }
}

#Preview("Milestone illustration · light", traits: .fixedLayout(width: 375, height: 310)) {
    MilestoneIllustrationView(skill: MilestoneCatalog.skill("cdc-12-bye_bye")!, showsStillImage: true)
        .padding(16).background(LogStyle.canvas).preferredColorScheme(.light)
}

#Preview("Milestone illustration · dark", traits: .fixedLayout(width: 375, height: 310)) {
    MilestoneIllustrationView(skill: MilestoneCatalog.skill("who-crawling")!, showsStillImage: true)
        .padding(16).background(LogStyle.canvas).preferredColorScheme(.dark)
}
