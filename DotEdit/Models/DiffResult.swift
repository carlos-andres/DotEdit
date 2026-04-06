import Foundation

/// Represents the result of comparing two env entries across files.
struct DiffResult: Equatable, Identifiable {
    let id = UUID()
    let category: Category
    let leftEntry: EnvEntry?
    let rightEntry: EnvEntry?

    enum Category: Equatable {
        case equal
        case modified
        case leftOnly
        case rightOnly
    }

    // MARK: - Equatable (exclude id)

    static func == (lhs: DiffResult, rhs: DiffResult) -> Bool {
        lhs.category == rhs.category
            && lhs.leftEntry == rhs.leftEntry
            && lhs.rightEntry == rhs.rightEntry
    }
}
