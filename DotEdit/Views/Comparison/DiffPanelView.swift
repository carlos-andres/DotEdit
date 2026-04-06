import SwiftUI

/// Renders one side (left or right) of the comparison as a column of rows
/// with independent horizontal scrolling.
struct DiffPanelView: View {
    let rows: [ComparisonRow]
    let side: Side

    enum Side {
        case left, right
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    DiffRowView(
                        entry: entry(for: row),
                        diffCategory: row.diffCategory,
                        contextCategory: row.contextCategory,
                        rowType: row.rowType,
                        lineIndex: nil,
                        rowIndex: index,
                        onLineChanged: nil
                    )
                }
            }
            .frame(minWidth: 300)
        }
    }

    private func entry(for row: ComparisonRow) -> EnvEntry? {
        switch side {
        case .left: return row.leftEntry
        case .right: return row.rightEntry
        }
    }
}
