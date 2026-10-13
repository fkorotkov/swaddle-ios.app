import SwiftUI

/// The same folded corner as the Cocoon mark, without obscuring care data.
extension LogStyle {
    static var cardShape: UnevenRoundedRectangle {
        .init(topLeadingRadius: 30, bottomLeadingRadius: 30,
              bottomTrailingRadius: 9, topTrailingRadius: 30)
    }
}

struct CocoonSummarySurface: ViewModifier {
    let saveID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.padding(22)
            .background(LogStyle.bottleSurface)
            .overlay(alignment: .bottomTrailing) {
                CocoonFold().fill(LogStyle.blue.opacity(0.09))
                    .frame(width: 128, height: 115)
                    .keyframeAnimator(initialValue: 0.0, trigger: saveID) { [reduceMotion] content, progress in
                        content.offset(x: reduceMotion ? 0 : progress * 9,
                                       y: reduceMotion ? 0 : -progress * 10)
                    } keyframes: { _ in
                        CubicKeyframe(1, duration: 0.15)
                        SpringKeyframe(0, duration: 0.36, spring: .smooth)
                    }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipShape(LogStyle.cardShape)
            .overlay { LogStyle.cardShape.strokeBorder(LogStyle.blue.opacity(0.1), lineWidth: 1) }
    }
}

struct CocoonFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX * 0.8, y: rect.maxY * 0.46),
                      control2: CGPoint(x: rect.maxX * 0.24, y: rect.maxY * 0.55))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
