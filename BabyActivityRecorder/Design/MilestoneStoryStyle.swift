import SwiftUI

/// Opaque reading surfaces; glass remains on the navigation and action controls.
enum MilestonePaperTone { case ivory, sage, memory }

struct MilestonePaper: View {
    var tone: MilestonePaperTone = .ivory
    var folded = false
    var unfolded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    private var colors: [Color] {
        switch (tone, scheme) {
        case (.sage, .light): [Color(red: 0.96, green: 0.97, blue: 0.91), Color(red: 0.86, green: 0.91, blue: 0.80)]
        case (.memory, .light): [Color(red: 1, green: 0.97, blue: 0.91), Color(red: 0.98, green: 0.94, blue: 0.87)]
        case (.ivory, .light): [Color(red: 1, green: 0.99, blue: 0.95), Color(red: 0.97, green: 0.95, blue: 0.90)]
        case (.sage, _): [Color(red: 0.19, green: 0.30, blue: 0.24), Color(red: 0.11, green: 0.20, blue: 0.17)]
        case (.memory, _): [Color(red: 0.22, green: 0.23, blue: 0.18), Color(red: 0.14, green: 0.18, blue: 0.15)]
        case (.ivory, _): [Color(red: 0.13, green: 0.20, blue: 0.17), Color(red: 0.08, green: 0.14, blue: 0.12)]
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topTrailing) {
                if folded {
                    MilestoneCorner()
                        .fill(LinearGradient(colors: scheme == .light
                            ? [.white.opacity(0.95), Color(red: 0.78, green: 0.84, blue: 0.71), .white.opacity(0.9)]
                            : [Color(red: 0.34, green: 0.44, blue: 0.35), Color(red: 0.14, green: 0.23, blue: 0.18), Color(red: 0.27, green: 0.38, blue: 0.29)],
                            startPoint: .topTrailing, endPoint: .bottomLeading))
                        .frame(width: 57, height: 63)
                        .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1)
                        .shadow(color: .black.opacity(scheme == .light ? 0.12 : 0.25), radius: 5, x: -3, y: 4)
                        .rotation3DEffect(.degrees(unfolded && !reduceMotion ? -14 : 0), axis: (x: 1, y: -1, z: 0), anchor: .topTrailing)
                }
            }
            .clipShape(.rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26).strokeBorder(
                    contrast == .increased ? LogStyle.forest.opacity(0.7) : (scheme == .light ? .white.opacity(0.86) : .white.opacity(0.13)), lineWidth: 1)
            }
            .shadow(color: LogStyle.ink.opacity(scheme == .light ? 0.055 : 0), radius: 12, x: 0, y: 6)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MilestoneCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: rect.width, y: rect.height),
                   control1: CGPoint(x: rect.width * 0.1, y: rect.height * 0.65),
                   control2: CGPoint(x: rect.width * 0.63, y: rect.height * 0.37))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.closeSubpath()
        return p
    }
}

/// A continuous ribbon that sways and catches the light while scrolling.
/// Geometry updates stay inside this decoration, never invalidating the chapter list.
struct MilestoneRibbon: View {
    @State private var viewport: CGRect = .zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Canvas { context, size in
            let period: CGFloat = 168
            let dark = scheme == .dark
            let count = Int(size.height / period) + 1
            let travel = reduceMotion || viewport.isEmpty ? 0 : viewport.minY
            let path = cloth(width: size.width, period: period, count: count, travel: travel)
            var clothContext = context
            clothContext.addFilter(.shadow(color: .black.opacity(dark ? 0.12 : 0.07), radius: 4, x: 2, y: 3))
            clothContext.fill(path, with: .linearGradient(Gradient(stops: [
                .init(color: Color(red: 0.53, green: 0.65, blue: 0.45), location: 0),
                .init(color: Color(red: 0.76, green: 0.83, blue: 0.65), location: 0.36),
                .init(color: Color(red: 0.88, green: 0.91, blue: 0.78), location: 0.58),
                .init(color: Color(red: 0.57, green: 0.70, blue: 0.48), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            var weave = context
            weave.clip(to: path)
            // An expanded checklist can make the ribbon thousands of points tall.
            // Only draw the weave near the viewport, combining it into one stroke.
            let first = viewport.isEmpty ? 0 : max(0, Int(floor(viewport.minY / period)) - 1)
            let last = viewport.isEmpty ? count : min(count, Int(ceil(viewport.maxY / period)) + 1)
            var threads = Path()
            for index in first..<max(first, last) {
                let rect = CGRect(x: 0, y: CGFloat(index) * period, width: size.width, height: period)
                for thread in 0..<32 {
                    let offset = CGFloat(thread) * 1.4 - 8
                    threads.move(to: point(x: offset, y: rect.minY, travel: travel))
                    threads.addCurve(to: point(x: offset, y: rect.maxY, travel: travel),
                                     control1: point(x: offset + 63, y: rect.minY + period * 0.30, travel: travel),
                                     control2: point(x: offset - 35, y: rect.minY + period * 0.72, travel: travel))
                }
            }
            weave.stroke(threads, with: .color(.white.opacity(0.14)), lineWidth: 0.45)
            context.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
            if !reduceMotion, !viewport.isEmpty {
                // This follows the reading position, not a completion/progress score.
                let focus = viewport.minY + viewport.height * 0.42
                let radius: CGFloat = 85
                let band = CGRect(x: 0, y: focus - radius, width: size.width, height: radius * 2)
                weave.fill(Path(band), with: .linearGradient(Gradient(colors: [
                    .clear, Color(red: 1, green: 0.94, blue: 0.74).opacity(0.72), .clear
                ]), startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
                // A short satin glint makes the changing folds readable at phone size.
                // It marks the reading area, never milestone completion.
                weave.stroke(seam(width: size.width, period: period, first: first, last: last, travel: travel),
                             with: .linearGradient(Gradient(colors: [
                                .clear, Color(red: 1, green: 0.97, blue: 0.82), .clear
                             ]), startPoint: CGPoint(x: 0, y: focus - 55), endPoint: CGPoint(x: 0, y: focus + 55)),
                             style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1)
        .opacity(scheme == .dark ? 0.80 : 0.92)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 12)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onGeometryChange(for: CGRect.self) { [reduceMotion] geometry in
            guard !reduceMotion else { return .zero }
            return geometry.bounds(of: .scrollView(axis: .vertical)) ?? .zero
        } action: { viewport = $0 }
    }

    private func point(x: CGFloat, y: CGFloat, travel: CGFloat) -> CGPoint {
        // Visible cloth movement stays inside the decorative gutter. It follows
        // the finger directly, with no timer, idle loop, or layout displacement.
        let ripple = reduceMotion ? 0 : 8 * sin(y / 130 + travel / 95)
        return CGPoint(x: x + ripple, y: y)
    }

    private func seam(width: CGFloat, period: CGFloat, first: Int, last: Int, travel: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(x: width * 0.5, y: CGFloat(first) * period, travel: travel))
        for index in first..<max(first, last) {
            let y = CGFloat(index) * period
            path.addCurve(to: point(x: width * 0.5, y: y + period * 0.5, travel: travel),
                          control1: point(x: width * 0.28, y: y + period * 0.19, travel: travel),
                          control2: point(x: width * 1.06, y: y + period * 0.26, travel: travel))
            path.addCurve(to: point(x: width * 0.5, y: y + period, travel: travel),
                          control1: point(x: width * -0.06, y: y + period * 0.74, travel: travel),
                          control2: point(x: width * 0.72, y: y + period * 0.81, travel: travel))
        }
        return path
    }

    private func cloth(width: CGFloat, period: CGFloat, count: Int, travel: CGFloat) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat, _ turn: Int) -> CGPoint {
            self.point(x: x * width, y: (CGFloat(turn) + y) * period, travel: travel)
        }
        var p = Path()
        p.move(to: point(0.23, 0, 0))
        for i in 0..<count {
            p.addCurve(to: point(0.30, 0.50, i), control1: point(0.01, 0.19, i), control2: point(0.95, 0.27, i))
            p.addCurve(to: point(0.23, 1, i), control1: point(-0.17, 0.75, i), control2: point(0.45, 0.81, i))
        }
        p.addLine(to: point(0.77, 1, count - 1))
        for i in (0..<count).reversed() {
            p.addCurve(to: point(0.70, 0.50, i), control1: point(0.99, 0.81, i), control2: point(0.05, 0.73, i))
            p.addCurve(to: point(0.77, 0, i), control1: point(1.17, 0.25, i), control2: point(0.55, 0.19, i))
        }
        p.closeSubpath()
        return p
    }
}

struct MilestoneMedallion: View {
    let symbol: String
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: prominent ? 24 : 19, weight: .medium))
            .foregroundStyle(LogStyle.forest)
            .frame(width: prominent ? 54 : 44, height: prominent ? 54 : 44)
            .background(LinearGradient(colors: scheme == .light
                ? [Color(red: 1, green: 0.98, blue: 0.90), Color(red: 0.98, green: 0.89, blue: 0.74)]
                : [Color(red: 0.27, green: 0.34, blue: 0.25), Color(red: 0.17, green: 0.25, blue: 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
            .overlay { Circle().strokeBorder(.white.opacity(scheme == .light ? 0.9 : 0.2), lineWidth: 1) }
            .shadow(color: .black.opacity(scheme == .light ? 0.09 : 0.2), radius: 5, x: 0, y: 3)
            .visualEffect { [reduceMotion] content, geometry in
                // Edge-only scroll transitions were almost invisible. Let each
                // medallion turn through the reading area without moving its card.
                let height = geometry.bounds(of: .scrollView(axis: .vertical))?.height ?? 0
                let distance = geometry.frame(in: .scrollView(axis: .vertical)).midY - height * 0.42
                let phase = reduceMotion || height == 0 ? 0 : max(-1, min(1, distance / (height * 0.55)))
                return content
                    .rotationEffect(.degrees(phase * 14))
                    .scaleEffect(1 - abs(phase) * 0.12)
            }
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}
