import SwiftUI

/// One decorative opening per root session. Routing or interruption settles it
/// immediately; no logging or presentation waits for this object.
@MainActor @Observable
final class CocoonOpeningSession {
  let duration: TimeInterval
  private(set) var isSettled = false
  @ObservationIgnored private var hasStarted = false

  init(duration: TimeInterval = 0.85) { self.duration = duration }

  func claim(reduceMotion: Bool) -> Bool {
    guard !hasStarted, !isSettled else { return false }
    hasStarted = true
    if reduceMotion {
      isSettled = true
      return false
    }
    return true
  }

  func settle() { isSettled = true }
}

struct CocoonOpeningMark: View {
  var session: CocoonOpeningSession? = nil
  var size: CGFloat = 80
  @State private var playback = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let still = reduceMotion || session == nil || session?.isSettled == true
    Color.clear.frame(width: size, height: size)
      .keyframeAnimator(initialValue: 0.0, trigger: playback) { [still] _, value in
        CocoonCloth(progress: still ? 1 : value).frame(width: size, height: size)
          .onChange(of: value >= 1) { _, finished in
            if finished { Task { @MainActor in session?.settle() } }
          }
      } keyframes: { _ in
        MoveKeyframe(0)
        LinearKeyframe(1, duration: session?.duration ?? 0.85)
      }
      .allowsHitTesting(false).accessibilityHidden(true)
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        if session?.claim(reduceMotion: reduceMotion) == true { playback += 1 }
      }
      .onChange(of: reduceMotion) { _, reduced in if reduced { session?.settle() } }
      .onChange(of: scenePhase) { previous, phase in
        if previous == .active && phase != .active { session?.settle() }
      }
      .onDisappear {
        // ViewThatFits also discards unchosen layout candidates. Only
        // the instance that actually began playing may end the session.
        if playback > 0 { session?.settle() }
      }
  }
}

/// A continuous fabric surface and its turning edge. The face is revealed only
/// once the cloth has mostly closed, rather than arriving as a separate piece.
struct CocoonCloth: View {
  let progress: Double
  private var fold: Double { smooth(0.15, 0.79) }

  private func smooth(_ begin: Double, _ end: Double) -> Double {
    let t = min(1, max(0, (progress - begin) / (end - begin)))
    return t * t * (3 - 2 * t)
  }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size.width
      let arrival = smooth(0, 0.72)
      let finish = smooth(0.72, 1)
      ZStack {
        ClothBody(fold: fold)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.72, green: 0.80, blue: 0.62),
                Color(red: 0.64, green: 0.74, blue: 0.55),
              ],
              startPoint: .topLeading, endPoint: .bottomTrailing))
        Ellipse()
          .fill(
            LinearGradient(
              colors: [
                Color(red: 1, green: 0.94, blue: 0.77),
                Color(red: 0.96, green: 0.90, blue: 0.72),
              ],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .frame(width: size * 0.25, height: size * 0.27)
          .rotationEffect(.degrees(-24))
          .position(x: size * 0.38, y: size * 0.265)
          .opacity(smooth(0.50, 0.72))
        ClothFold(fold: fold)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 1, green: 0.98, blue: 0.90),
                Color(red: 0.90, green: 0.90, blue: 0.81),
              ],
              startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .shadow(
            color: .black.opacity(0.065 * fold), radius: size * 0.012,
            x: size * 0.008, y: size * 0.006)
      }
      .scaleEffect(0.87 + arrival * 0.13 + sin(finish * .pi) * 0.012)
      .rotationEffect(.degrees((1 - arrival) * -18))
      .rotation3DEffect(.degrees((1 - arrival) * 28), axis: (x: 1, y: 0.2, z: 0), perspective: 0.25)
      .offset(x: (arrival - 1) * size * 0.15, y: sin(arrival * .pi) * -size * 0.055)
      .opacity(smooth(0, 0.12))
    }
  }
}

private struct ClothBody: Shape {
  var fold: Double
  func path(in rect: CGRect) -> Path {
    func p(_ a: (Double, Double), _ b: (Double, Double)) -> CGPoint {
      CGPoint(
        x: (a.0 + (b.0 - a.0) * fold) * rect.width,
        y: (a.1 + (b.1 - a.1) * fold) * rect.height)
    }
    var path = Path()
    path.move(to: p((0.11, 0.30), (0.39, 0.18)))
    path.addCurve(
      to: p((0.87, 0.25), (0.56, 0.27)), control1: p((0.35, 0.16), (0.47, 0.17)),
      control2: p((0.62, 0.36), (0.52, 0.19)))
    path.addCurve(
      to: p((0.69, 0.82), (0.72, 0.66)), control1: p((0.85, 0.45), (0.62, 0.38)),
      control2: p((0.89, 0.65), (0.68, 0.51)))
    path.addCurve(
      to: p((0.21, 0.69), (0.48, 0.79)), control1: p((0.51, 0.7), (0.79, 0.86)),
      control2: p((0.3, 0.82), (0.59, 0.88)))
    path.addCurve(
      to: p((0.11, 0.30), (0.39, 0.18)), control1: p((0.19, 0.58), (0.3, 0.62)),
      control2: p((0.21, 0.42), (0.13, 0.24)))
    path.closeSubpath()
    return path
  }
}

private struct ClothFold: Shape {
  var fold: Double
  func path(in rect: CGRect) -> Path {
    func p(_ a: (Double, Double), _ b: (Double, Double)) -> CGPoint {
      CGPoint(
        x: (a.0 + (b.0 - a.0) * fold) * rect.width,
        y: (a.1 + (b.1 - a.1) * fold) * rect.height)
    }
    var path = Path()
    path.move(to: p((0.11, 0.30), (0.47, 0.18)))
    path.addCurve(
      to: p((0.87, 0.25), (0.62, 0.37)), control1: p((0.32, 0.15), (0.56, 0.22)),
      control2: p((0.68, 0.39), (0.6, 0.3)))
    path.addCurve(
      to: p((0.85, 0.36), (0.46, 0.63)), control1: p((0.83, 0.29), (0.67, 0.48)),
      control2: p((0.86, 0.34), (0.51, 0.54)))
    path.addCurve(
      to: p((0.20, 0.39), (0.47, 0.78)), control1: p((0.61, 0.45), (0.4, 0.7)),
      control2: p((0.36, 0.22), (0.42, 0.74)))
    path.addCurve(
      to: p((0.11, 0.30), (0.32, 0.57)), control1: p((0.17, 0.38), (0.35, 0.72)),
      control2: p((0.15, 0.33), (0.29, 0.64)))
    path.addCurve(
      to: p((0.11, 0.30), (0.5, 0.28)), control1: p((0.12, 0.31), (0.34, 0.48)),
      control2: p((0.1, 0.3), (0.58, 0.34)))
    path.addCurve(
      to: p((0.11, 0.30), (0.47, 0.18)), control1: p((0.1, 0.3), (0.51, 0.23)),
      control2: p((0.1, 0.3), (0.49, 0.2)))
    path.closeSubpath()
    return path
  }
}
