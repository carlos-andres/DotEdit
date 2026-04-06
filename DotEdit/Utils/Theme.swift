import SwiftUI

enum Theme {
    // MARK: - Typography

    /// SF Mono — primary font for all env content display
    static let monoFont: Font = .system(.body, design: .monospaced)

    static func monoFont(size: CGFloat, family: String = "System") -> Font {
        if family != "System" {
            return Font.custom(family, size: size)
        }
        return .system(size: size, design: .monospaced)
    }

    // MARK: - Window

    static let defaultWindowWidth: CGFloat = 1024
    static let defaultWindowHeight: CGFloat = 768

    // MARK: - Comparison Layout

    static let gutterWidth: CGFloat = 96
    static let gutterLineNumberWidth: CGFloat = 24
    static let gutterSymbolWidth: CGFloat = 16
    static let gutterActionWidth: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 1
    static let rowHorizontalPadding: CGFloat = 8
    static let headerHeight: CGFloat = 32
    static let statusBarHeight: CGFloat = 28
    static let toolbarHeight: CGFloat = 44
    static let actionBarHeight: CGFloat = 36
    static let scrollBarReservedWidth: CGFloat = 16
    // MARK: - Editor & Gutter Backgrounds

    static let editorBackground = Color(NSColor.textBackgroundColor)
    static let gutterBackground = Color(NSColor.controlBackgroundColor)
    static let stripeBackground = Color.primary.opacity(0.03)

    // MARK: - Diff Colors

    static let diffModifiedBackground = Color.blue.opacity(0.12)
    static let diffAddedBackground = Color.green.opacity(0.12)
    static let diffRemovedBackground = Color.green.opacity(0.12)
    static let diffEqualBackground = Color.clear

    // MARK: - Context Diff Colors

    static let contextModifiedBackground = Color.blue.opacity(0.06)
    static let contextOnlyBackground = Color.orange.opacity(0.06)

    // MARK: - Gutter Diff Backgrounds

    static let gutterModifiedBackground = Color.blue.opacity(0.15)
    static let gutterAddedBackground = Color.green.opacity(0.15)
    static let gutterRemovedBackground = Color.orange.opacity(0.15)

    // MARK: - Warning Colors

    static let warningBackground = Color.orange.opacity(0.12)
    static let warningText = Color.orange

    // MARK: - Search Colors

    static let searchMatchBackground = Color.yellow.opacity(0.15)
    static let searchCurrentMatchBackground = Color(red: 1.0, green: 0.92, blue: 0.4)

    // MARK: - Syntax Colors

    static let syntaxKey = Color.primary
    static let syntaxValue = Color.primary.opacity(0.85)
    static let syntaxComment = Color.mint.opacity(0.8)
    static let syntaxLineNumber = Color.secondary.opacity(0.6)
    static let syntaxEquals = Color.secondary.opacity(0.5)
}
