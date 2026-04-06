import SwiftUI

/// Persisted app settings backed by UserDefaults.
/// All changes apply immediately — no Apply button needed.
@Observable
final class AppSettings {

    // MARK: - Keys

    private enum Key {
        static let theme = "settings.theme"
        static let fontSize = "settings.fontSize"
        static let createBackupOnSave = "settings.createBackupOnSave"
        static let exportPrefixMode = "settings.exportPrefixMode"
        static let caseInsensitiveKeys = "settings.caseInsensitiveKeys"
        static let wordWrap = "settings.wordWrap"
        static let showLineNumbers = "settings.showLineNumbers"
        static let transferMode = "settings.transferMode"
        static let sequentialDiff = "settings.sequentialDiff"
        static let reorgCommentHandling = "settings.reorgCommentHandling"
        static let fontFamily = "settings.fontFamily"
    }

    // MARK: - Defaults

    static let defaultFontSize: CGFloat = 12
    static let fontSizeRange: ClosedRange<CGFloat> = 12...20
    static let defaultFontFamily = "System"

    // MARK: - Storage

    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted values (or use defaults)
        let themeRaw = defaults.string(forKey: Key.theme) ?? AppearanceMode.system.rawValue
        _theme = AppearanceMode(rawValue: themeRaw) ?? .system

        let storedSize = defaults.double(forKey: Key.fontSize)
        _fontSize = storedSize > 0 ? CGFloat(storedSize) : Self.defaultFontSize

        // Bool defaults: UserDefaults returns false for unset keys, so use object check
        if defaults.object(forKey: Key.createBackupOnSave) != nil {
            _createBackupOnSave = defaults.bool(forKey: Key.createBackupOnSave)
        } else {
            _createBackupOnSave = true
        }

        _caseInsensitiveKeys = defaults.bool(forKey: Key.caseInsensitiveKeys)

        _wordWrap = defaults.bool(forKey: Key.wordWrap)

        if defaults.object(forKey: Key.showLineNumbers) != nil {
            _showLineNumbers = defaults.bool(forKey: Key.showLineNumbers)
        } else {
            _showLineNumbers = true
        }

        let exportRaw = defaults.string(forKey: Key.exportPrefixMode) ?? ExportPrefixMode.preserve.rawValue
        _exportPrefixMode = ExportPrefixMode(rawValue: exportRaw) ?? .preserve

        let transferRaw = defaults.string(forKey: Key.transferMode) ?? TransferMode.fullLine.rawValue
        _transferMode = TransferMode(rawValue: transferRaw) ?? .fullLine

        _sequentialDiff = defaults.bool(forKey: Key.sequentialDiff)

        let reorgRaw = defaults.string(forKey: Key.reorgCommentHandling) ?? SemanticReorg.CommentHandling.moveWithKey.rawValue
        _reorgCommentHandling = SemanticReorg.CommentHandling(rawValue: reorgRaw) ?? .moveWithKey

        _fontFamily = defaults.string(forKey: Key.fontFamily) ?? Self.defaultFontFamily
    }

    // MARK: - Appearance

    enum AppearanceMode: String, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"

        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private var _theme: AppearanceMode
    var theme: AppearanceMode {
        get { _theme }
        set {
            _theme = newValue
            defaults.set(newValue.rawValue, forKey: Key.theme)
        }
    }

    // MARK: - Font Size

    private var _fontSize: CGFloat
    var fontSize: CGFloat {
        get { _fontSize }
        set {
            let clamped = min(max(newValue, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            _fontSize = clamped
            defaults.set(Double(clamped), forKey: Key.fontSize)
        }
    }

    // MARK: - Font Family (DEC-048)

    private var _fontFamily: String
    var fontFamily: String {
        get { _fontFamily }
        set {
            _fontFamily = newValue
            defaults.set(newValue, forKey: Key.fontFamily)
        }
    }

    // MARK: - Backup

    private var _createBackupOnSave: Bool
    var createBackupOnSave: Bool {
        get { _createBackupOnSave }
        set {
            _createBackupOnSave = newValue
            defaults.set(newValue, forKey: Key.createBackupOnSave)
        }
    }

    // MARK: - Export Prefix

    enum ExportPrefixMode: String, CaseIterable {
        case preserve = "preserve"
        case remove = "remove"
        case skip = "skip"

        var label: String {
            switch self {
            case .preserve: "Preserve"
            case .remove: "Remove"
            case .skip: "Skip"
            }
        }

        /// Convert to DiffEngine.ExportMode.
        var diffEngineMode: DiffEngine.ExportMode {
            switch self {
            case .preserve: .preserve
            case .remove: .remove
            case .skip: .skip
            }
        }
    }

    private var _exportPrefixMode: ExportPrefixMode
    var exportPrefixMode: ExportPrefixMode {
        get { _exportPrefixMode }
        set {
            _exportPrefixMode = newValue
            defaults.set(newValue.rawValue, forKey: Key.exportPrefixMode)
        }
    }

    // MARK: - Case Sensitivity

    private var _caseInsensitiveKeys: Bool
    var caseInsensitiveKeys: Bool {
        get { _caseInsensitiveKeys }
        set {
            _caseInsensitiveKeys = newValue
            defaults.set(newValue, forKey: Key.caseInsensitiveKeys)
        }
    }

    // MARK: - Word Wrap

    private var _wordWrap: Bool
    var wordWrap: Bool {
        get { _wordWrap }
        set {
            _wordWrap = newValue
            defaults.set(newValue, forKey: Key.wordWrap)
        }
    }

    // MARK: - Line Numbers

    private var _showLineNumbers: Bool
    var showLineNumbers: Bool {
        get { _showLineNumbers }
        set {
            _showLineNumbers = newValue
            defaults.set(newValue, forKey: Key.showLineNumbers)
        }
    }

    // MARK: - Transfer Mode

    enum TransferMode: String, CaseIterable {
        case fullLine = "fullLine"
        case valueOnly = "valueOnly"

        var label: String {
            switch self {
            case .fullLine: "Full Line"
            case .valueOnly: "Value Only"
            }
        }
    }

    private var _transferMode: TransferMode
    var transferMode: TransferMode {
        get { _transferMode }
        set {
            _transferMode = newValue
            defaults.set(newValue.rawValue, forKey: Key.transferMode)
        }
    }

    // MARK: - Sequential Diff

    private var _sequentialDiff: Bool
    var sequentialDiff: Bool {
        get { _sequentialDiff }
        set {
            _sequentialDiff = newValue
            defaults.set(newValue, forKey: Key.sequentialDiff)
        }
    }

    // MARK: - Reorg Comment Handling (OI-006)

    private var _reorgCommentHandling: SemanticReorg.CommentHandling
    var reorgCommentHandling: SemanticReorg.CommentHandling {
        get { _reorgCommentHandling }
        set {
            _reorgCommentHandling = newValue
            defaults.set(newValue.rawValue, forKey: Key.reorgCommentHandling)
        }
    }

    // MARK: - Comparison State Reset (DEC-042)

    /// Reset Tier 2 (session-only) settings to defaults.
    /// Called before each new file comparison to ensure clean state.
    /// Tier 1 (user preferences) remain unchanged.
    func resetComparisonState() {
        _sequentialDiff = false
        defaults.set(false, forKey: Key.sequentialDiff)
        _caseInsensitiveKeys = false
        defaults.set(false, forKey: Key.caseInsensitiveKeys)
    }

    // MARK: - Convenience

    /// Build DiffEngine.Options from current settings.
    var diffOptions: DiffEngine.Options {
        DiffEngine.Options(
            caseInsensitiveKeys: caseInsensitiveKeys,
            exportMode: exportPrefixMode.diffEngineMode,
            diffMode: sequentialDiff ? .sequential : .keyBased
        )
    }
}
