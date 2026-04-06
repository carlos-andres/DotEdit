import SwiftUI

/// Renders a single row for one side of the comparison: editable content with zebra stripes.
/// Line numbers are now rendered in GutterView.
struct DiffRowView: View {
    let entry: EnvEntry?
    let diffCategory: DiffResult.Category?
    let contextCategory: ComparisonRow.ContextCategory?
    let rowType: ComparisonRow.RowType
    let lineIndex: Int?
    let rowIndex: Int
    let onLineChanged: ((Int, String) -> Void)?
    var searchText: String = ""
    var isCurrentMatch: Bool = false
    var contentFontSize: CGFloat = 12
    var wordWrap: Bool = false
    var fontFamily: String = "System"
    var isGapRow: Bool = false

    @State private var editText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Content
            if let entry {
                if isEditing {
                    editableField
                } else {
                    syntaxColoredContent(entry)
                        .onTapGesture {
                            guard onLineChanged != nil else { return }
                            editText = entry.rawLine
                            isEditing = true
                            isFocused = true
                        }
                }
            } else if isGapRow {
                // Gap placeholder for visual reorg alignment
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(.secondary.opacity(0.15))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Spacer()
            }
        }
        .padding(.vertical, Theme.rowVerticalPadding)
        .padding(.horizontal, Theme.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(searchHighlightBackground)
        .background(warningBackground)
        .background(backgroundColor)
    }

    /// Search match background — yellow for match, stronger for current match.
    private var searchHighlightBackground: Color {
        guard !searchText.isEmpty, let entry, entry.rawLine.lowercased().contains(searchText.lowercased()) else {
            return .clear
        }
        return isCurrentMatch ? Theme.searchCurrentMatchBackground : Theme.searchMatchBackground
    }

    /// Warning background — subtle orange for entries with warnings.
    private var warningBackground: Color {
        guard let entry, !entry.warnings.isEmpty else { return .clear }
        return Theme.warningBackground
    }

    // MARK: - Editable Field

    private var editableField: some View {
        TextField("", text: $editText, onCommit: {
            commitEdit()
        })
        .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitEdit()
            }
        }
        .onExitCommand {
            // Esc cancels editing
            isEditing = false
        }
        .onChange(of: entry?.rawLine) { _, _ in
            // Cancel edit if the entry changed externally (e.g. file watcher reDiff)
            if isEditing {
                isEditing = false
            }
        }
    }

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        guard let index = lineIndex, let callback = onLineChanged else { return }
        callback(index, editText)
    }

    // MARK: - Syntax Coloring

    @ViewBuilder
    private func syntaxColoredContent(_ entry: EnvEntry) -> some View {
        switch entry.type {
        case .keyValue:
            HStack(spacing: 0) {
                if entry.hasExportPrefix {
                    Text("export ")
                        .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                        .foregroundStyle(Theme.syntaxComment)
                }
                Text(entry.key ?? "")
                    .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                    .foregroundStyle(Theme.syntaxKey)
                    .lineLimit(1)
                Text("=")
                    .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                    .foregroundStyle(Theme.syntaxEquals)
                    .lineLimit(1)
                Text(formattedValue(entry))
                    .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                    .foregroundStyle(Theme.syntaxValue)
                    .lineLimit(wordWrap || entry.isMultiline ? nil : 1)
            }

        case .comment:
            Text(entry.rawLine)
                .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                .foregroundStyle(Theme.syntaxComment)
                .lineLimit(wordWrap || entry.isMultiline ? nil : 1)

        case .blank:
            Text(" ")
                .font(Theme.monoFont(size: contentFontSize, family: fontFamily))

        case .malformed:
            Text(entry.rawLine)
                .font(Theme.monoFont(size: contentFontSize, family: fontFamily))
                .foregroundStyle(.red.opacity(0.7))
                .lineLimit(wordWrap || entry.isMultiline ? nil : 1)
        }
    }

    private func formattedValue(_ entry: EnvEntry) -> String {
        let val = entry.value ?? ""
        switch entry.quoteStyle {
        case .none: return val
        case .single: return "'\(val)'"
        case .double: return "\"\(val)\""
        case .backtick: return "`\(val)`"
        }
    }

    // MARK: - Background

    private var backgroundColor: Color {
        // When current search match, suppress diff bg so opaque highlight dominates
        if isCurrentMatch && !searchText.isEmpty { return .clear }

        if isGapRow {
            return Color(NSColor.separatorColor).opacity(0.08)
        }
        let base = stripeColor
        if let cat = diffCategory, rowType == .diff {
            switch cat {
            case .equal: return base
            case .modified: return Theme.diffModifiedBackground
            case .leftOnly: return Theme.diffRemovedBackground
            case .rightOnly: return Theme.diffAddedBackground
            }
        }
        if let cat = contextCategory, rowType == .context {
            switch cat {
            case .equal: return base
            case .modified: return Theme.contextModifiedBackground
            case .leftOnly, .rightOnly: return Theme.contextOnlyBackground
            }
        }
        return base
    }

    /// Zebra stripe for even rows
    private var stripeColor: Color {
        rowIndex.isMultiple(of: 2) ? Theme.stripeBackground : Color.clear
    }
}
