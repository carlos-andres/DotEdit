import Foundation

/// The 6 naming conventions supported for .env key classification (DEC-008).
enum NamingConvention: String, CaseIterable, Equatable {
    case screamingSnake  // DB_HOST
    case snakeCase       // db_host
    case dotNotation     // app.url
    case kebabCase       // db-host
    case camelCase       // dbHost
    case pascalCase      // DbHost

    var displayName: String {
        switch self {
        case .screamingSnake: return "SCREAMING_SNAKE"
        case .snakeCase: return "snake_case"
        case .dotNotation: return "dot.notation"
        case .kebabCase: return "kebab-case"
        case .camelCase: return "camelCase"
        case .pascalCase: return "PascalCase"
        }
    }
}

// MARK: - Classification

extension NamingConvention {

    /// Classify a single key into its naming convention.
    static func classify(key: String) -> NamingConvention {
        let hasDot = key.contains(".")
        let hasDash = key.contains("-")
        let hasUnderscore = key.contains("_")
        let hasUppercase = key.contains(where: \.isUppercase)
        let hasLowercase = key.contains(where: \.isLowercase)

        // dot.notation — has dots
        if hasDot && !hasUnderscore && !hasDash {
            return .dotNotation
        }

        // kebab-case — has dashes
        if hasDash && !hasUnderscore && !hasDot {
            return .kebabCase
        }

        // Has underscores — distinguish SCREAMING_SNAKE vs snake_case
        if hasUnderscore {
            if hasUppercase && !hasLowercase {
                return .screamingSnake
            }
            if hasLowercase && !hasUppercase {
                return .snakeCase
            }
            // Mixed case with underscores — treat as SCREAMING_SNAKE if mostly upper
            let upperCount = key.filter(\.isUppercase).count
            let lowerCount = key.filter(\.isLowercase).count
            return upperCount >= lowerCount ? .screamingSnake : .snakeCase
        }

        // No delimiter — camelCase vs PascalCase
        if hasUppercase && hasLowercase {
            if key.first?.isUppercase == true {
                return .pascalCase
            }
            return .camelCase
        }

        // All uppercase, no delimiter — treat as SCREAMING_SNAKE
        if hasUppercase && !hasLowercase {
            return .screamingSnake
        }

        // All lowercase, no delimiter — treat as snake_case (single word)
        return .snakeCase
    }
}

// MARK: - Dominant Detection

extension NamingConvention {

    /// Result of scanning keys for dominant convention.
    struct DetectionResult: Equatable {
        let dominant: NamingConvention
        let confidence: Double
        let breakdown: [(convention: NamingConvention, count: Int)]
        let totalKeys: Int

        /// Whether the result is low confidence (< 5 keys).
        var isLowConfidence: Bool { totalKeys < 5 }

        /// Whether conventions are mixed (dominant < 100%).
        var isMixed: Bool { confidence < 1.0 && breakdown.count > 1 }

        static func == (lhs: DetectionResult, rhs: DetectionResult) -> Bool {
            lhs.dominant == rhs.dominant
                && lhs.confidence == rhs.confidence
                && lhs.totalKeys == rhs.totalKeys
        }
    }

    /// Detect the dominant naming convention from a set of keys.
    static func detectDominant(keys: [String]) -> DetectionResult {
        guard !keys.isEmpty else {
            return DetectionResult(
                dominant: .screamingSnake,
                confidence: 0,
                breakdown: [],
                totalKeys: 0
            )
        }

        var counts: [NamingConvention: Int] = [:]
        for key in keys {
            let convention = classify(key: key)
            counts[convention, default: 0] += 1
        }

        let sorted = counts.sorted { $0.value > $1.value }
        let dominant = sorted.first!.key
        let confidence = Double(sorted.first!.value) / Double(keys.count)

        let breakdown = sorted.map { (convention: $0.key, count: $0.value) }

        return DetectionResult(
            dominant: dominant,
            confidence: confidence,
            breakdown: breakdown,
            totalKeys: keys.count
        )
    }
}

// MARK: - Prefix Extraction

extension NamingConvention {

    /// Extract the prefix from a key using the convention's delimiter.
    static func extractPrefix(key: String, convention: NamingConvention) -> String {
        switch convention {
        case .screamingSnake, .snakeCase:
            // Split on first underscore
            if let idx = key.firstIndex(of: "_") {
                return String(key[key.startIndex..<idx])
            }
            return key

        case .dotNotation:
            // Split on first dot
            if let idx = key.firstIndex(of: ".") {
                return String(key[key.startIndex..<idx])
            }
            return key

        case .kebabCase:
            // Split on first dash
            if let idx = key.firstIndex(of: "-") {
                return String(key[key.startIndex..<idx])
            }
            return key

        case .camelCase:
            // Split at first uppercase boundary
            return extractCamelPrefix(key, startsUpper: false)

        case .pascalCase:
            // Split at second uppercase boundary (first word)
            return extractCamelPrefix(key, startsUpper: true)
        }
    }

    /// Extract prefix from camelCase/PascalCase at the first word boundary.
    private static func extractCamelPrefix(_ key: String, startsUpper: Bool) -> String {
        guard key.count > 1 else { return key }

        let chars = Array(key)
        var splitIndex = key.count

        if startsUpper {
            // PascalCase: find second uppercase letter (start of second word)
            for i in 1..<chars.count {
                if chars[i].isUppercase {
                    splitIndex = i
                    break
                }
            }
        } else {
            // camelCase: find first uppercase letter
            for i in 0..<chars.count {
                if chars[i].isUppercase {
                    splitIndex = i
                    break
                }
            }
        }

        if splitIndex == 0 || splitIndex == key.count {
            return key
        }

        return String(chars[0..<splitIndex])
    }
}
