import SwiftUI

/// Center gutter column with 5-column JetBrains-style layout:
/// [Col1: » transfer-right] [Col2: L#] [Col3: status] [Col4: R#] [Col5: « transfer-left]
/// Arrow direction = transfer direction. Physically separated to prevent misclicks.
struct GutterView: View {
    let row: ComparisonRow
    var showLineNumbers: Bool = true
    var fontFamily: String = "System"
    var onTransferToRight: (() -> Void)?
    var onTransferToLeft: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Col1: » transfer-to-right action (left edge)
            transferToRightButton
                .frame(width: Theme.gutterActionWidth)

            if showLineNumbers {
                // Col2: left line number — right-aligned
                Text(leftLineText)
                    .font(Theme.monoFont(size: 11, family: fontFamily))
                    .foregroundStyle(Theme.syntaxLineNumber)
                    .frame(width: Theme.gutterLineNumberWidth, alignment: .trailing)
            }

            // Col3: status symbol (= or ~), not clickable
            statusSymbol
                .frame(width: Theme.gutterSymbolWidth)

            if showLineNumbers {
                // Col4: right line number — left-aligned
                Text(rightLineText)
                    .font(Theme.monoFont(size: 11, family: fontFamily))
                    .foregroundStyle(Theme.syntaxLineNumber)
                    .frame(width: Theme.gutterLineNumberWidth, alignment: .leading)
            }

            // Col5: « transfer-to-left action (right edge)
            transferToLeftButton
                .frame(width: Theme.gutterActionWidth)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Line Numbers

    private var leftLineText: String {
        guard let entry = row.leftEntry else { return "" }
        guard entry.isMultiline else { return "\(entry.lineNumber)" }
        return "\(entry.lineNumber)\u{2012}\(entry.lineNumber + entry.lineCount - 1)"
    }

    private var rightLineText: String {
        guard let entry = row.rightEntry else { return "" }
        guard entry.isMultiline else { return "\(entry.lineNumber)" }
        return "\(entry.lineNumber)\u{2012}\(entry.lineNumber + entry.lineCount - 1)"
    }

    // MARK: - Col1: » Transfer to Right

    @ViewBuilder
    private var transferToRightButton: some View {
        if let cat = row.diffCategory, cat == .modified || cat == .leftOnly {
            Button(action: { onTransferToRight?() }) {
                Text("\u{00BB}") // »
                    .font(symbolFont)
                    .foregroundStyle(symbolActiveColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Col3: Status Symbol

    @ViewBuilder
    private var statusSymbol: some View {
        if let cat = row.diffCategory {
            switch cat {
            case .equal:
                Text("=")
                    .font(symbolFont)
                    .foregroundStyle(.primary.opacity(0.5))
            case .modified:
                Text("~")
                    .font(symbolFont)
                    .foregroundStyle(.primary.opacity(0.5))
            case .leftOnly, .rightOnly:
                Color.clear
            }
        } else if let cat = row.contextCategory {
            switch cat {
            case .equal:
                Text("=")
                    .font(symbolFont)
                    .foregroundStyle(.primary.opacity(0.3))
            case .modified:
                Text("~")
                    .font(symbolFont)
                    .foregroundStyle(.primary.opacity(0.3))
            case .leftOnly, .rightOnly:
                Color.clear
            }
        } else {
            Text(" ")
                .font(symbolFont)
        }
    }

    // MARK: - Col5: « Transfer to Left

    @ViewBuilder
    private var transferToLeftButton: some View {
        if let cat = row.diffCategory, cat == .modified || cat == .rightOnly {
            Button(action: { onTransferToLeft?() }) {
                Text("\u{00AB}") // «
                    .font(symbolFont)
                    .foregroundStyle(symbolActiveColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Styling

    private var symbolFont: Font {
        Theme.monoFont(size: 14, family: fontFamily).bold()
    }

    private var symbolActiveColor: Color {
        .primary.opacity(0.85)
    }
}
