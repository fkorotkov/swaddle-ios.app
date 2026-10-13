import SwiftUI

enum BabyPalette: Equatable {
    case sage, blue, rose

    init(gender: ChildGender?) {
        switch gender {
        case .boy: self = .blue
        case .girl: self = .rose
        case nil: self = .sage
        }
    }

    var accent: Color {
        switch self {
        case .sage: Self.sageAccent
        case .blue: Self.blueAccent
        case .rose: Self.roseAccent
        }
    }

    var surface: Color {
        switch self {
        case .sage: Self.sageSurface
        case .blue: Self.blueSurface
        case .rose: Self.roseSurface
        }
    }

    private static let sageAccent = adaptive(light: (0.227, 0.396, 0.314), dark: (0.69, 0.8, 0.64))
    private static let blueAccent = adaptive(light: (0.18, 0.34, 0.43), dark: (0.63, 0.78, 0.87))
    private static let roseAccent = adaptive(light: (0.43, 0.22, 0.29), dark: (0.90, 0.68, 0.75))
    private static let sageSurface = adaptive(light: (0.89, 0.93, 0.86), dark: (0.14, 0.24, 0.19))
    private static let blueSurface = adaptive(light: (0.885, 0.93, 0.955), dark: (0.12, 0.21, 0.27))
    private static let roseSurface = adaptive(light: (0.96, 0.897, 0.91), dark: (0.29, 0.16, 0.21))
    static let pumpingAccent = adaptive(light: (0.50, 0.28, 0.10), dark: (0.91, 0.70, 0.46))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

extension EnvironmentValues {
    @Entry var babyPalette: BabyPalette = .sage
}

extension View {
    func babyPalette(for gender: ChildGender?) -> some View {
        let palette = BabyPalette(gender: gender)
        return environment(\.babyPalette, palette).tint(palette.accent)
    }
}
