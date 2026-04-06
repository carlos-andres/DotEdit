import AppKit

/// Enumerates installed monospace fonts for the editor font picker (DEC-048).
enum MonospaceFontProvider {
    /// Returns display names of installed monospace font families, sorted, "System" first.
    static func availableFonts() -> [String] {
        let manager = NSFontManager.shared
        let monoFonts = manager.availableFontNames(with: .fixedPitchFontMask) ?? []

        // Deduplicate variants (e.g. "Menlo-Regular", "Menlo-Bold") into family names
        let families = Set(monoFonts.compactMap { name -> String? in
            NSFont(name: name, size: 12)?.familyName
        })

        return ["System"] + families.sorted()
    }
}
