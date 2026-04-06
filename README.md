# DotEdit

A native macOS app for visually comparing and syncing `.env` files side-by-side. Purpose-built for `.env` files — not a general diff tool.

When managing multiple environments (dev, staging, production, homelab servers), `.env` files drift apart. New keys get added to one environment but forgotten in others. DotEdit makes comparison and syncing a 30-second visual task.

## Links

- **Download:** [Latest Release](https://github.com/carlos-andres/DotEdit/releases/latest)
- **Website:** [dotedit.app](https://dotedit.app)
- **Documentation:** [dotedit.app/docs](https://dotedit.app/docs)

## Tech Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Language | Swift | 6.2.3 |
| Framework | SwiftUI + AppKit (bridged) | — |
| Platform | macOS | 15.0+ (Sequoia) |
| IDE | Xcode | 26.2 |
| Concurrency | async/await + @Observable | Swift 6 |
| Persistence | UserDefaults | — |
| Sandbox | App Sandbox | Entitlements |
| Dependencies | None | Zero third-party packages |

## Install

1. Download `DotEdit-0.3.0.dmg` from [GitHub Releases](https://github.com/carlos-andres/DotEdit/releases/latest)
2. Mount the DMG and drag DotEdit to Applications
3. Launch from Applications — no Gatekeeper warnings (signed + notarized)

Requires macOS 15.0+ (Sequoia).

## Testing

250 tests across 22 suites using the Swift Testing framework (`@Suite` / `@Test`).

```bash
# Run all tests
xcodebuild test -scheme DotEdit -destination 'platform=macOS'

# Run a specific test suite
xcodebuild test -scheme DotEdit -only-testing:DotEditTests/EnvParserTests
```

| Suite | Coverage |
|-------|----------|
| EnvParserTests | Parsing, quotes, multiline, BOM, warnings |
| DiffEngineTests | Key-based diff, ordering, duplicates, case sensitivity |
| SequentialDiffTests | Position-based diff mode |
| FileIOTests | Load/save, binary rejection, read-only, symlinks |
| SearchAndWarningsTests | Search matching, warning aggregation |
| SemanticReorgTests | Prefix grouping, reorganization |
| AlignedReorgEngineTests | Visual reorg alignment |
| ConsolidateEngineTests | Consolidation engine |
| CollapseAndDedupTests | Collapse and deduplication |
| VisualReorgTests | Visual reorg mode |
| ContextDiffTests | Context-aware diff |
| ExternalChangeDiffTests | External file change detection |
| NamingConventionTests | Naming convention detection |
| VolumeMonitorTests | Volume monitoring |
| IntegrationTests | Real-world .env files (Laravel, Node, .NET, Python) |

## Architecture

MVVM pattern — `@Observable` ViewModels with `@MainActor` concurrency, stateless service enums, and SwiftUI views. ~7,700 lines of source code across 54 files.

Two-screen flow:
1. **File Selection** — Dropzones, file picker, recent files, validation
2. **Comparison View** — Side-by-side diff with gutter actions, toolbar, per-panel controls, status bar

### Layers

| Layer | Count | Key Types |
|-------|-------|-----------|
| Models | 6 | `EnvEntry`, `EnvFile`, `DiffResult`, `ComparisonRow`, `AlignedRow`, `PanelSide` |
| ViewModels | 7 | `ComparisonViewModel`, `AppState`, `AppSettings`, `ThemeManager`, `ToastManager`, `SearchState`, `ConfirmationService` |
| Views | 13 | `FileSelectionView`, `ComparisonView`, `SettingsView`, `HelpView` + 9 subviews + 8 reusable components |
| Services | 12 | `EnvParser`, `DiffEngine`, `FileLoader`, `FileSaver`, `FileValidator`, `FileWatcher`, `SemanticReorg`, `AlignedReorgEngine`, `ConsolidateEngine`, `RecentFilesManager`, `VolumeMonitor`, `Log` |
| Utils | 4 | `NamingConvention`, `PathClamper`, `MonospaceFontProvider`, `Theme` |

### Project Structure

```
DotEdit/
├── DotEditApp.swift              # App entry point
├── ContentView.swift             # Navigation router
├── Models/
│   ├── AlignedRow.swift
│   ├── ComparisonRow.swift
│   ├── DiffResult.swift
│   ├── EnvEntry.swift            # Key-value entry model
│   ├── EnvFile.swift             # Parsed file model
│   └── PanelSide.swift
├── Services/
│   ├── AlignedReorgEngine.swift
│   ├── ConsolidateEngine.swift
│   ├── DiffEngine.swift          # Key-based & sequential diff
│   ├── EnvFilePanel.swift
│   ├── EnvParser.swift           # .env file parser
│   ├── FileLoader.swift          # Load with 2MB guard
│   ├── FileSaver.swift           # Atomic writes (temp → rename)
│   ├── FileValidator.swift
│   ├── FileWatcher.swift         # FSEvents monitoring
│   ├── Log.swift
│   ├── RecentFilesManager.swift
│   ├── SemanticReorg.swift       # Convention-aware reorganization
│   └── VolumeMonitor.swift
├── Utils/
│   ├── MonospaceFontProvider.swift
│   ├── NamingConvention.swift
│   ├── PathClamper.swift
│   └── Theme.swift
├── ViewModels/
│   ├── AppSettings.swift         # UserDefaults-backed (10 options)
│   ├── AppState.swift
│   ├── ComparisonViewModel.swift # Central hub (~955 lines)
│   ├── ConfirmationService.swift
│   ├── SearchState.swift
│   ├── ThemeManager.swift
│   └── ToastManager.swift
├── Views/
│   ├── ComparisonView.swift      # Main screen (~1040 lines)
│   ├── FileSelectionView.swift
│   ├── HelpView.swift
│   ├── SettingsView.swift
│   ├── Comparison/
│   │   ├── ComparisonKeyboardShortcuts.swift
│   │   ├── DiffPanelView.swift
│   │   ├── DiffRowView.swift
│   │   ├── FileHeaderView.swift
│   │   ├── GutterView.swift
│   │   ├── PanelActionBarView.swift
│   │   ├── StatusBarView.swift
│   │   ├── ToolbarView.swift
│   │   └── WarningsPanelView.swift
│   └── Components/
│       ├── DecisionToastView.swift
│       ├── DropZoneView.swift
│       ├── ExternalChangeDiffSheet.swift
│       ├── FileInaccessibleBanner.swift
│       ├── FilePanelView.swift
│       ├── PillButton.swift
│       ├── ToastView.swift
│       ├── ToolbarItems.swift
│       └── WarningModal.swift
├── Assets.xcassets/
└── DotEdit.entitlements

DotEditTests/                     # 22 suites, 250 tests
├── AlignedReorgEngineTests.swift
├── CollapseAndDedupTests.swift
├── ConsolidateEngineTests.swift
├── ContextDiffTests.swift
├── DiffEngineTests.swift
├── EnvParserTests.swift
├── ExternalChangeDiffTests.swift
├── FileIOTests.swift
├── IntegrationTests.swift
├── NamingConventionTests.swift
├── SearchAndWarningsTests.swift
├── SemanticReorgTests.swift
├── SequentialDiffTests.swift
├── VisualReorgTests.swift
└── VolumeMonitorTests.swift
```

## Key Features

### File Selection Screen
- Drag-and-drop zones filtered to `.env` / `.env.*` files
- File picker with `.env` pattern filter
- Recent files list per side with clear option
- Same-file validation guard

### Comparison View
- **Dual panels** — Fully editable, like an IDE code editor
- **Center gutter** — `»` (copy left→right), `«` (copy right→left), `=` (equal)
- **Key-based diff** — Matches by key name regardless of line position
- **Sequential diff** — Fallback mode for line-by-line comparison
- **Live re-diff** — Background colors update instantly on every edit (~100ms debounce)
- **Color coding** — Green (added/missing), Blue (modified), None (equal)
- **Synchronized scrolling** — Toggle on/off
- **Draggable split divider** — 50/50 default

### Toolbar (Global Controls)
```
[← Back] │ [🔀 Reorg ▾] [⇅ Collapse] [↕ Sync] [♊ Dedup ▾] │ [🔄 Reload] [⚙] [?] [✕ Exit]
```

### Per-Panel Action Bar
```
[💾 Save] [↩ Undo] [↪ Redo] [🔍 Search]
```

### Semantic Reorganization
- Groups keys by prefix (e.g., `DB_HOST`, `DB_PORT` → `# === DB ===`)
- Detects naming convention: SCREAMING_SNAKE, snake_case, dot.notation, kebab-case, camelCase, PascalCase
- Warns on mixed conventions
- Preserves comments (moves with associated key)

### .env Parser
Handles: key-value pairs, comments, blank lines, quoted values (single, double, backtick), multiline values, `export` prefix, BOM detection, inline comments, empty values, duplicate keys, malformed lines.

### Warnings System
IDE-style warnings dropdown: unclosed quotes, BOM, malformed lines, non-standard keys, duplicates, read-only files.

### File Watching
FSEvents-based monitoring for external changes. Self-suppresses during saves to avoid false triggers. Diff preview before reload.

### Settings (10 options)
Diff mode, blank lines, sync scrolling, naming convention detection, theme, font size, backup before save, `export` handling, case-insensitive keys, reorg comment behavior.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘Z` | Undo (active panel) |
| `⌘⇧Z` | Redo (active panel) |
| `⌘S` | Save active panel |
| `⌘⌥S` | Save all panels |
| `⌘R` | Reload files from disk |
| `⌘F` | Search in active panel |
| `Escape` | Back to file selection |
| `⌘Q` | Quit app |

### Security & Sandbox

| Protection | Implementation |
|------------|----------------|
| App Sandbox | Entitlements-based |
| Code signing | Developer ID Application (Apple notarized) |
| Hardened Runtime | Enabled |
| File size guard | 2MB max |
| Binary detection | Null byte scan on first 8KB |
| Atomic writes | Temp file → rename |
| Permission preservation | On save |
| Backup before overwrite | `.env` → `.env.backup` (7-day TTL) |
| Symlink resolution | Before loading |
| Security-scoped access | Bookmark refresh on stale detection |

## Distribution

DotEdit v0.3.0 is code-signed with a Developer ID certificate and notarized by Apple. Gatekeeper will allow it to run without warnings.

- **DMG** — Signed, notarized, and stapled. Mount and drag to Applications.
- **ZIP** — Notarized. Extract and run directly.

Download from [GitHub Releases](https://github.com/carlos-andres/DotEdit/releases/latest).

## Target Users

- Developers managing multiple environments (dev/staging/prod)
- Homelab administrators syncing configurations across servers
- Small teams working with environment-specific configs

## Design Constraints

| Rule | Description |
|------|-------------|
| RULE-001 | Only `.env` and `.env.*` files supported — this is a feature, not a limitation |
| RULE-002 | macOS only (Sequoia 15.0+) |

## Building from Source

```bash
git clone https://github.com/carlos-andres/DotEdit.git
cd DotEdit
xcodebuild -project DotEdit.xcodeproj -scheme DotEdit -destination 'platform=macOS' build
```

Requires Xcode (developed with 26.2). Zero third-party dependencies.

## Related

- **Website & Docs:** [dotedit.app](https://dotedit.app) — [github.com/carlos-andres/DotEditWebsite](https://github.com/carlos-andres/DotEditWebsite)
