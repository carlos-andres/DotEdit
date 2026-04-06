import SwiftUI

@Observable
final class ThemeManager {
    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearanceMode: AppearanceMode = .system
}
