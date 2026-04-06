import SwiftUI
import Combine

struct ComparisonView: View {
    var onBack: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ToastManager.self) private var toastManager
    @Environment(AppSettings.self) private var settings
    @Environment(ConfirmationService.self) private var confirmationService
    @State private var viewModel: ComparisonViewModel?
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var focusedSide: PanelSide = .left
    @State private var showUnsavedBackModal = false
    @State private var showUnsavedReloadModal = false
    @State private var showExternalChangeDiffSheet = false
    @State private var externalChangeSide: PanelSide?
    @State private var externalChangeStats: ComparisonViewModel.DiffStats?
    @State private var externalChangeResults: [DiffResult] = []
    @State private var externalChangeSideLabel: String = ""
    @State private var fileWatcher = FileWatcher()
    @State private var volumeMonitor: VolumeMonitor?
    @State private var showWarningsPanel = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        Group {
            if let vm = viewModel {
                comparisonContent(vm)
            } else {
                ProgressView("Loading comparison...")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard let left = appState.leftEnvFile, let right = appState.rightEnvFile else { return }
            let vm = ComparisonViewModel(leftFile: left, rightFile: right, settings: settings)
            vm.leftSourceURL = appState.leftFileURL
            vm.rightSourceURL = appState.rightFileURL
            viewModel = vm
        }
    }

    // MARK: - Main Layout

    @ViewBuilder
    private func comparisonContent(_ vm: ComparisonViewModel) -> some View {
        VStack(spacing: 0) {
            // Top bar with back button
            topBar(vm)

            Divider()

            // File headers
            fileHeaders(vm)

            Divider()

            // Identical files banner
            if vm.filesAreIdentical {
                identicalBanner
            }

            // File inaccessible banners (BL-010)
            if !vm.isLeftAccessible {
                FileInaccessibleBanner(side: "Left", filePath: vm.leftFile.filePath)
            }
            if !vm.isRightAccessible {
                FileInaccessibleBanner(side: "Right", filePath: vm.rightFile.filePath)
            }

            // Main diff area
            GeometryReader { geo in
                let layout = vm.panelLayout(for: geo.size)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            if vm.isVisualReorgActive {
                                // Visual reorg mode: aligned rows with prefix group headers
                                alignedRowsList(vm, leftWidth: layout.leftWidth, rightWidth: layout.rightWidth)
                            } else {
                                // Normal mode: original file order
                                normalRowsList(vm, leftWidth: layout.leftWidth, rightWidth: layout.rightWidth)
                            }
                        }
                    }
                    .onChange(of: vm.scrollTarget) { _, id in
                        if let id {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .background(Theme.editorBackground)
            }

            // Search bar (above action bars)
            if vm.search.isSearchActive {
                searchBar(vm)
                Divider()
            }

            Divider()

            // Action bars
            actionBars(vm)

            Divider()

            // Warnings panel
            if showWarningsPanel && vm.warningCount > 0 {
                WarningsPanelView(vm: vm, showWarningsPanel: $showWarningsPanel)
                Divider()
            }

            // Status bar
            StatusBarView(
                leftFile: vm.leftFile,
                rightFile: vm.rightFile,
                stats: vm.diffStats,
                collapsedCount: vm.collapsedCount,
                warningCount: vm.warningCount,
                onToggleWarnings: { showWarningsPanel.toggle() }
            )
        }
        .modifier(ComparisonKeyboardShortcuts(
            onSaveFocused: { savePanel(focusedSide, vm: vm) },
            onSaveAll: {
                savePanel(.left, vm: vm)
                savePanel(.right, vm: vm)
            },
            onReload: { handleReloadRequest(vm) },
            onSearch: {
                vm.search.searchSide = focusedSide
                vm.search.isSearchActive = true
                isSearchFieldFocused = true
            },
            onEscape: {
                if vm.search.isSearchActive {
                    vm.clearSearch()
                    isSearchFieldFocused = false
                }
            },
            onSetFontSize: { delta in
                switch delta {
                case 1: settings.fontSize += 1
                case -1: settings.fontSize -= 1
                case 0: settings.fontSize = AppSettings.defaultFontSize
                default: settings.fontSize = delta
                }
            },
            onShowHelp: { showHelp = true }
        ))
        // Drop rejection — files belong on the file selection screen
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in
            toastManager.show("Drop files on the file selection screen", severity: .info)
            return true
        }
        // Back guard alert
        .alert("Unsaved Changes", isPresented: $showUnsavedBackModal) {
            Button("Save All & Go Back") {
                do {
                    let warning = try vm.saveAll()
                    toastManager.show(warning ?? "Files saved", severity: warning != nil ? .warning : .success)
                    onBack()
                } catch {
                    toastManager.show("Save failed: \(error.localizedDescription)", severity: .error)
                }
            }
            Button("Discard & Go Back", role: .destructive) {
                onBack()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. What would you like to do?")
        }
        // Reload guard alert
        .alert("Unsaved Changes", isPresented: $showUnsavedReloadModal) {
            Button("Reload", role: .destructive) {
                performReload(vm)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reloading will discard your unsaved changes.")
        }
        // External change diff sheet (BL-004)
        .sheet(isPresented: $showExternalChangeDiffSheet) {
            ExternalChangeDiffSheet(
                sideLabel: externalChangeSideLabel,
                stats: externalChangeStats ?? .empty,
                changes: externalChangeResults,
                onReload: {
                    showExternalChangeDiffSheet = false
                    performReload(vm)
                },
                onKeep: {
                    showExternalChangeDiffSheet = false
                }
            )
        }
        // Reorg confirmations now use DecisionToast via ConfirmationService
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(settings)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        // Re-diff when settings change
        .onChange(of: settings.caseInsensitiveKeys) { _, _ in vm.computeRows() }
        .onChange(of: settings.exportPrefixMode) { _, _ in vm.computeRows() }
        // FileWatcher setup
        .onAppear {
            setupFileWatcher(vm)
        }
        .onDisappear {
            fileWatcher.stopAll()
            volumeMonitor?.stop()
        }
        // Sync hasUnsavedChanges to AppState for quit guard
        .onChange(of: vm.hasUnsavedChanges) { _, newValue in
            appState.hasUnsavedChanges = newValue
        }
        // Handle save-all-and-quit from ContentView's quit modal
        .onReceive(NotificationCenter.default.publisher(for: .dotEditSaveAllAndQuit)) { _ in
            fileWatcher.suppress()
            do {
                _ = try vm.saveAll()
                AppDelegate.shared?.isQuitting = true
                NSApplication.shared.terminate(nil)
            } catch {
                fileWatcher.unsuppress()
                toastManager.show("Save failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    // MARK: - Top Bar

    @ViewBuilder
    private func topBar(_ vm: ComparisonViewModel) -> some View {
        ToolbarView(
            isCollapsed: vm.isCollapsed,
            isVisualReorgActive: vm.isVisualReorgActive,
            isReorgPreviewActive: vm.isReorgPreviewActive,
            caseInsensitive: settings.caseInsensitiveKeys,
            sequentialDiff: settings.sequentialDiff,
            wordWrap: settings.wordWrap,
            showLineNumbers: settings.showLineNumbers,
            fontSize: settings.fontSize,
            areCommentsHidden: vm.areCommentsHidden,
            onBack: {
                if vm.hasUnsavedChanges {
                    showUnsavedBackModal = true
                } else {
                    onBack()
                }
            },
            onToggleVisualReorg: {
                if !vm.isVisualReorgActive && settings.sequentialDiff {
                    settings.sequentialDiff = false
                    vm.reDiff()
                    toastManager.show("Switched from Sequential to Align mode", severity: .info)
                }
                if !vm.isVisualReorgActive && vm.isReorgPreviewActive {
                    vm.clearReorgPreview()
                }
                vm.isVisualReorgActive.toggle()
            },
            onReorganizePreview: { hideComments in
                handleReorganizePreview(vm: vm, hideComments: hideComments)
            },
            onReorganizeApply: { scope, stripComments in
                initiateReorganizeApply(vm: vm, scope: scope, stripComments: stripComments)
            },
            onClearPreview: {
                vm.clearReorgPreview()
                toastManager.show("Preview cleared", severity: .info)
            },
            onDedup: { scope in performDedup(vm, scope: scope) },
            onToggleComments: {
                vm.areCommentsHidden.toggle()
                toastManager.show(vm.areCommentsHidden ? "Comments hidden" : "Comments shown", severity: .info)
            },
            onRemoveComments: { initiateRemoveComments(vm: vm) },
            onToggleCollapse: { vm.isCollapsed.toggle() },
            onReload: { handleReloadRequest(vm) },
            onToggleCaseInsensitive: { settings.caseInsensitiveKeys.toggle() },
            onToggleSequentialDiff: {
                if !settings.sequentialDiff && vm.isVisualReorgActive {
                    vm.isVisualReorgActive = false
                    toastManager.show("Switched from Align to Sequential mode", severity: .info)
                }
                if !settings.sequentialDiff && vm.isReorgPreviewActive {
                    vm.clearReorgPreview()
                }
                settings.sequentialDiff.toggle()
                vm.reDiff()
            },
            onToggleWordWrap: { settings.wordWrap.toggle() },
            onToggleLineNumbers: { settings.showLineNumbers.toggle() },
            onSetFontSize: { settings.fontSize = $0 },
            onShowSettings: { showSettings = true },
            onShowHelp: { showHelp = true }
        )
    }

    // MARK: - File Headers

    @ViewBuilder
    private func fileHeaders(_ vm: ComparisonViewModel) -> some View {
        GeometryReader { geo in
            let layout = vm.panelLayout(for: geo.size)

            HStack(spacing: 0) {
                FileHeaderView(
                    fileURL: appState.leftFileURL,
                    filePath: vm.leftFile.filePath,
                    isDirty: vm.isLeftDirty
                )
                .frame(width: layout.leftWidth)

                Color.clear
                    .frame(width: Theme.gutterWidth)
                    .contentShape(Rectangle())
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .onTapGesture(count: 1) {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.leftFraction = 0.5 }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let totalReserved = Theme.gutterWidth + Theme.scrollBarReservedWidth
                                let newFraction = (value.location.x + layout.leftWidth - Theme.gutterWidth / 2) / (geo.size.width - totalReserved)
                                vm.leftFraction = min(max(newFraction, 0.2), 0.8)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                FileHeaderView(
                    fileURL: appState.rightFileURL,
                    filePath: vm.rightFile.filePath,
                    isDirty: vm.isRightDirty
                )
                .frame(width: layout.rightWidth)
            }
        }
        .frame(height: Theme.headerHeight)
    }

    // MARK: - Action Bars

    @ViewBuilder
    private func actionBars(_ vm: ComparisonViewModel) -> some View {
        GeometryReader { geo in
            let layout = vm.panelLayout(for: geo.size)

            HStack(spacing: 0) {
                PanelActionBarView(
                    isDirty: vm.isLeftDirty,
                    undoManager: vm.leftUndoManager,
                    onSave: { savePanel(.left, vm: vm) },
                    onSearch: {
                        focusedSide = .left
                        vm.search.searchSide = .left
                        vm.search.isSearchActive = true
                    }
                )
                .frame(width: layout.leftWidth)

                Color.clear
                    .frame(width: Theme.gutterWidth, height: Theme.actionBarHeight)
                    .background(.bar)

                PanelActionBarView(
                    isDirty: vm.isRightDirty,
                    undoManager: vm.rightUndoManager,
                    onSave: { savePanel(.right, vm: vm) },
                    onSearch: {
                        focusedSide = .right
                        vm.search.searchSide = .right
                        vm.search.isSearchActive = true
                    }
                )
                .frame(width: layout.rightWidth)
            }
        }
        .frame(height: Theme.actionBarHeight)
    }

    // MARK: - Save

    private func savePanel(_ side: PanelSide, vm: ComparisonViewModel) {
        let filePath = side == .left ? vm.leftFile.filePath : vm.rightFile.filePath
        let fileURL = URL(fileURLWithPath: filePath)
        let fm = FileManager.default

        // BL-010: Inaccessible file → go straight to Save As
        let inaccessible = (side == .left && !vm.isLeftAccessible) || (side == .right && !vm.isRightAccessible)

        // BL-009: File deleted → go straight to Save As
        let fileDeleted = !inaccessible && !fm.fileExists(atPath: filePath)

        if inaccessible || fileDeleted {
            let message = inaccessible ? "File is unreachable. Choose a new location." : "File was deleted. Choose a new location."
            guard let newURL = EnvFilePanel.saveAs(
                suggestedName: fileURL.lastPathComponent,
                message: message
            ) else { return }

            fileWatcher.suppress()
            do {
                try vm.saveSideAs(side: side, to: newURL)
                // Update AppState and FileWatcher for new path
                switch side {
                case .left:
                    appState.leftFileURL = newURL
                    fileWatcher.stopWatching(url: fileURL)
                    fileWatcher.watch(url: newURL)
                case .right:
                    appState.rightFileURL = newURL
                    fileWatcher.stopWatching(url: fileURL)
                    fileWatcher.watch(url: newURL)
                }
                toastManager.show("File saved to \(newURL.lastPathComponent)", severity: .success)
            } catch {
                toastManager.show("Save As failed: \(error.localizedDescription)", severity: .error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + FileWatcher.suppressRecoveryDelay) { fileWatcher.unsuppress() }
            return
        }

        // Attempt direct save first — fall back to Save As only on actual permission error (DEC-055)
        do {
            var warning: String?
            try fileWatcher.suppressDuring {
                warning = try vm.save(side: side)
            }
            toastManager.show(warning ?? "File saved", severity: warning != nil ? .warning : .success)
        } catch {
            // Save failed — offer Save As as fallback (covers true read-only + sandbox edge cases)
            let message = "File is read-only. Choose a new location."
            guard let newURL = EnvFilePanel.saveAs(
                suggestedName: fileURL.lastPathComponent,
                message: message
            ) else {
                toastManager.show("Save failed: \(error.localizedDescription)", severity: .error)
                return
            }

            fileWatcher.suppress()
            do {
                try vm.saveSideAs(side: side, to: newURL)
                switch side {
                case .left:
                    appState.leftFileURL = newURL
                    fileWatcher.stopWatching(url: fileURL)
                    fileWatcher.watch(url: newURL)
                case .right:
                    appState.rightFileURL = newURL
                    fileWatcher.stopWatching(url: fileURL)
                    fileWatcher.watch(url: newURL)
                }
                toastManager.show("File saved to \(newURL.lastPathComponent)", severity: .success)
            } catch {
                toastManager.show("Save As failed: \(error.localizedDescription)", severity: .error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + FileWatcher.suppressRecoveryDelay) { fileWatcher.unsuppress() }
        }
    }

    // MARK: - Reload

    private func handleReloadRequest(_ vm: ComparisonViewModel) {
        if vm.hasUnsavedChanges {
            showUnsavedReloadModal = true
        } else {
            performReload(vm)
        }
    }

    private func performReload(_ vm: ComparisonViewModel) {
        guard let leftURL = appState.leftFileURL, let rightURL = appState.rightFileURL else { return }
        do {
            try fileWatcher.suppressDuring {
                try vm.reload(leftURL: leftURL, rightURL: rightURL)
            }
            toastManager.show("Files reloaded", severity: .success)
        } catch {
            toastManager.show("Reload failed: \(error.localizedDescription)", severity: .error)
        }
    }

    // MARK: - FileWatcher

    private func setupFileWatcher(_ vm: ComparisonViewModel) {
        guard let leftURL = appState.leftFileURL, let rightURL = appState.rightFileURL else { return }

        fileWatcher.setChangeHandler { [weak toastManager] changedURL in
            DispatchQueue.main.async {
                let leftPath = leftURL.resolvingSymlinksInPath().path
                let rightPath = rightURL.resolvingSymlinksInPath().path
                let changedPath = changedURL.resolvingSymlinksInPath().path

                let fm = FileManager.default

                if changedPath == leftPath {
                    if !fm.fileExists(atPath: leftPath) {
                        toastManager?.show("Left file was deleted — use ⌘S to Save As", severity: .error)
                    } else if vm.isLeftDirty {
                        self.showExternalChangeDiff(vm, url: leftURL, side: .left)
                    } else {
                        self.reloadSilently(vm, side: .left, url: leftURL)
                        toastManager?.show("Left file updated externally", severity: .info)
                    }
                } else if changedPath == rightPath {
                    if !fm.fileExists(atPath: rightPath) {
                        toastManager?.show("Right file was deleted — use ⌘S to Save As", severity: .error)
                    } else if vm.isRightDirty {
                        self.showExternalChangeDiff(vm, url: rightURL, side: .right)
                    } else {
                        self.reloadSilently(vm, side: .right, url: rightURL)
                        toastManager?.show("Right file updated externally", severity: .info)
                    }
                }
            }
        }

        fileWatcher.watch(url: leftURL)
        fileWatcher.watch(url: rightURL)

        // BL-010: VolumeMonitor setup
        let monitor = VolumeMonitor()
        monitor.monitor(url: leftURL)
        monitor.monitor(url: rightURL)
        monitor.setHandler { [weak toastManager] url, isAccessible in
            vm.setAccessibility(url: url, isAccessible: isAccessible)
            if isAccessible {
                // Volume remounted — reconnect file watcher
                fileWatcher.reconnect(url: url)
                toastManager?.show("File is accessible again", severity: .success)
            } else {
                toastManager?.show("File is unreachable — volume may be disconnected", severity: .warning)
            }
        }
        monitor.start()
        self.volumeMonitor = monitor
    }

    /// Show external change diff sheet, or fallback to toast if diff computation fails (BL-004).
    private func showExternalChangeDiff(_ vm: ComparisonViewModel, url: URL, side: PanelSide) {
        do {
            let summary = try vm.computeExternalChangeSummary(for: url, side: side)
            externalChangeSide = side
            externalChangeStats = summary.stats
            externalChangeResults = summary.changes
            externalChangeSideLabel = summary.sideLabel
            showExternalChangeDiffSheet = true
        } catch {
            // Fallback: file unreadable, show simple toast
            toastManager.show("File changed externally (couldn't compute diff)", severity: .warning)
        }
    }

    private func reloadSilently(_ vm: ComparisonViewModel, side: PanelSide, url: URL) {
        do {
            try fileWatcher.suppressDuring {
                try vm.reloadSide(url: url, side: side)
            }
        } catch {
            toastManager.show("Reload failed: \(error.localizedDescription)", severity: .error)
        }
    }

    // MARK: - Dedup Helpers

    private func performDedup(_ vm: ComparisonViewModel, scope: PanelSide?) {
        let sides: [PanelSide]
        if let scope {
            sides = [scope]
        } else {
            sides = [.left, .right]
        }

        var totalRemoved = 0
        var allRemovedKeys: [String] = []

        for side in sides {
            let result = vm.dedup(side: side)
            totalRemoved += result.removedCount
            allRemovedKeys.append(contentsOf: result.removedKeys)
        }

        if totalRemoved == 0 {
            toastManager.show("No duplicates found", severity: .info)
        } else {
            let keyList = allRemovedKeys.prefix(3).joined(separator: ", ")
            let suffix = allRemovedKeys.count > 3 ? " + \(allRemovedKeys.count - 3) more" : ""
            toastManager.show(
                "Removed \(totalRemoved) duplicates: \(keyList)\(suffix)",
                severity: .success
            )
        }
    }

    // MARK: - Warnings Panel (extracted to WarningsPanelView)

    // MARK: - Search Bar

    @ViewBuilder
    private func searchBar(_ vm: ComparisonViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search...", text: Bindable(vm.search).searchText)
                .textFieldStyle(.plain)
                .font(Theme.monoFont(size: 12))
                .focused($isSearchFieldFocused)
                .onSubmit { vm.nextMatch() }

            if !vm.search.searchText.isEmpty {
                if vm.search.searchMatchCount > 0 {
                    Text("\((vm.search.currentMatch.map { _ in vm.search.currentMatchIndex + 1 } ?? 0)) of \(vm.search.searchMatchCount)")
                        .font(Theme.monoFont(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No results")
                        .font(Theme.monoFont(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            Button {
                vm.previousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(vm.search.searchMatchCount == 0)

            Button {
                vm.nextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(vm.search.searchMatchCount == 0)

            Divider()
                .frame(height: 16)

            Text(vm.search.searchSide == .left ? "Left" : vm.search.searchSide == .right ? "Right" : "Both")
                .font(Theme.monoFont(size: 10))
                .foregroundStyle(.secondary)

            Button {
                vm.clearSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Identical Banner

    private var identicalBanner: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Files are identical")
                .font(Theme.monoFont(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.06))
    }

    // MARK: - Normal Rows (Original File Order)

    @ViewBuilder
    private func normalRowsList(_ vm: ComparisonViewModel, leftWidth: CGFloat, rightWidth: CGFloat) -> some View {
        let displayRows = vm.isReorgPreviewActive ? vm.previewRows : vm.visibleRows
        ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, row in
            HStack(alignment: .top, spacing: 0) {
                // Left panel
                panelContainer(width: leftWidth, wordWrap: settings.wordWrap) {
                    DiffRowView(
                        entry: row.leftEntry,
                        diffCategory: row.diffCategory,
                        contextCategory: row.contextCategory,
                        rowType: row.rowType,
                        lineIndex: lineIndex(for: row.leftEntry, in: vm.leftLines),
                        rowIndex: index,
                        onLineChanged: { idx, newValue in
                            vm.updateLine(at: idx, to: newValue, side: .left)
                        },
                        searchText: (vm.search.searchSide == nil || vm.search.searchSide == .left) ? vm.search.searchText : "",
                        isCurrentMatch: vm.search.currentMatch?.rowIndex == index && vm.search.currentMatch?.side == .left,
                        contentFontSize: settings.fontSize,
                        wordWrap: settings.wordWrap,
                        fontFamily: settings.fontFamily
                    )
                }
                .onTapGesture { focusedSide = .left }
                .overlay(alignment: .leading) {
                    if focusedSide == .left {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 2)
                    }
                }

                // Gutter
                GutterView(
                    row: row,
                    showLineNumbers: settings.showLineNumbers,
                    fontFamily: settings.fontFamily,
                    onTransferToRight: { vm.transfer(row: row, to: .right) },
                    onTransferToLeft: { vm.transfer(row: row, to: .left) }
                )
                    .frame(width: Theme.gutterWidth)
                    .frame(maxHeight: .infinity)
                    .background(gutterBackground(for: row))

                // Right panel
                panelContainer(width: rightWidth, wordWrap: settings.wordWrap) {
                    DiffRowView(
                        entry: row.rightEntry,
                        diffCategory: row.diffCategory,
                        contextCategory: row.contextCategory,
                        rowType: row.rowType,
                        lineIndex: lineIndex(for: row.rightEntry, in: vm.rightLines),
                        rowIndex: index,
                        onLineChanged: { idx, newValue in
                            vm.updateLine(at: idx, to: newValue, side: .right)
                        },
                        searchText: (vm.search.searchSide == nil || vm.search.searchSide == .right) ? vm.search.searchText : "",
                        isCurrentMatch: vm.search.currentMatch?.rowIndex == index && vm.search.currentMatch?.side == .right,
                        contentFontSize: settings.fontSize,
                        wordWrap: settings.wordWrap,
                        fontFamily: settings.fontFamily
                    )
                }
                .onTapGesture { focusedSide = .right }
                .overlay(alignment: .trailing) {
                    if focusedSide == .right {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 2)
                    }
                }

            }
        }
    }

    // MARK: - Aligned Rows (Visual Reorg Mode)

    @ViewBuilder
    private func alignedRowsList(_ vm: ComparisonViewModel, leftWidth: CGFloat, rightWidth: CGFloat) -> some View {
        let visibleRows = vm.visibleAlignedRows
        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
            // Prefix group section header
            if index == 0 || row.prefixGroup != visibleRows[index - 1].prefixGroup {
                alignedGroupHeader(row.prefixGroup)
            }

            HStack(alignment: .top, spacing: 0) {
                // Left panel
                panelContainer(width: leftWidth, wordWrap: settings.wordWrap) {
                    DiffRowView(
                        entry: row.leftEntry,
                        diffCategory: row.diffCategory,
                        contextCategory: nil,
                        rowType: .diff,
                        lineIndex: lineIndex(for: row.leftEntry, in: vm.leftLines),
                        rowIndex: index,
                        onLineChanged: row.leftEntry != nil ? { idx, newValue in
                            vm.updateLine(at: idx, to: newValue, side: .left)
                        } : nil,
                        searchText: (vm.search.searchSide == nil || vm.search.searchSide == .left) ? vm.search.searchText : "",
                        isCurrentMatch: vm.search.currentMatch?.rowIndex == index && vm.search.currentMatch?.side == .left,
                        contentFontSize: settings.fontSize,
                        wordWrap: settings.wordWrap,
                        fontFamily: settings.fontFamily,
                        isGapRow: row.isLeftGap
                    )
                }
                .onTapGesture { focusedSide = .left }
                .overlay(alignment: .leading) {
                    if focusedSide == .left {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 2)
                    }
                }

                // Gutter
                alignedGutterView(row: row, vm: vm)
                    .frame(width: Theme.gutterWidth)
                    .frame(maxHeight: .infinity)
                    .background(alignedGutterBackground(for: row))

                // Right panel
                panelContainer(width: rightWidth, wordWrap: settings.wordWrap) {
                    DiffRowView(
                        entry: row.rightEntry,
                        diffCategory: row.diffCategory,
                        contextCategory: nil,
                        rowType: .diff,
                        lineIndex: lineIndex(for: row.rightEntry, in: vm.rightLines),
                        rowIndex: index,
                        onLineChanged: row.rightEntry != nil ? { idx, newValue in
                            vm.updateLine(at: idx, to: newValue, side: .right)
                        } : nil,
                        searchText: (vm.search.searchSide == nil || vm.search.searchSide == .right) ? vm.search.searchText : "",
                        isCurrentMatch: vm.search.currentMatch?.rowIndex == index && vm.search.currentMatch?.side == .right,
                        contentFontSize: settings.fontSize,
                        wordWrap: settings.wordWrap,
                        fontFamily: settings.fontFamily,
                        isGapRow: row.isRightGap
                    )
                }
                .onTapGesture { focusedSide = .right }
                .overlay(alignment: .trailing) {
                    if focusedSide == .right {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 2)
                    }
                }
            }
        }
    }

    /// Prefix group section header.
    private func alignedGroupHeader(_ group: String) -> some View {
        HStack {
            Text(group)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.vertical, 2)
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// Gutter for aligned rows — uses AlignedRow data directly.
    @ViewBuilder
    private func alignedGutterView(row: AlignedRow, vm: ComparisonViewModel) -> some View {
        HStack(spacing: 0) {
            // Col1: transfer-to-right
            if row.diffCategory == .modified || row.diffCategory == .leftOnly {
                Button(action: { vm.transferAligned(row: row, to: .right) }) {
                    Text("\u{00BB}")
                        .font(Theme.monoFont(size: 14, family: settings.fontFamily).bold())
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: Theme.gutterActionWidth)
            } else {
                Color.clear.frame(width: Theme.gutterActionWidth, height: 20)
            }

            if settings.showLineNumbers {
                // Left line number
                Text(row.leftEntry.map { entry in
                    entry.isMultiline
                        ? "\(entry.lineNumber)\u{2012}\(entry.lineNumber + entry.lineCount - 1)"
                        : "\(entry.lineNumber)"
                } ?? "")
                    .font(Theme.monoFont(size: 11, family: settings.fontFamily))
                    .foregroundStyle(Theme.syntaxLineNumber)
                    .frame(width: Theme.gutterLineNumberWidth, alignment: .trailing)
            }

            // Status symbol
            Group {
                switch row.diffCategory {
                case .equal:
                    Text("=").font(Theme.monoFont(size: 14, family: settings.fontFamily).bold()).foregroundStyle(.primary.opacity(0.5))
                case .modified:
                    Text("~").font(Theme.monoFont(size: 14, family: settings.fontFamily).bold()).foregroundStyle(.primary.opacity(0.5))
                case .leftOnly, .rightOnly:
                    Color.clear
                }
            }
            .frame(width: Theme.gutterSymbolWidth)

            if settings.showLineNumbers {
                // Right line number
                Text(row.rightEntry.map { entry in
                    entry.isMultiline
                        ? "\(entry.lineNumber)\u{2012}\(entry.lineNumber + entry.lineCount - 1)"
                        : "\(entry.lineNumber)"
                } ?? "")
                    .font(Theme.monoFont(size: 11, family: settings.fontFamily))
                    .foregroundStyle(Theme.syntaxLineNumber)
                    .frame(width: Theme.gutterLineNumberWidth, alignment: .leading)
            }

            // Col5: transfer-to-left
            if row.diffCategory == .modified || row.diffCategory == .rightOnly {
                Button(action: { vm.transferAligned(row: row, to: .left) }) {
                    Text("\u{00AB}")
                        .font(Theme.monoFont(size: 14, family: settings.fontFamily).bold())
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: Theme.gutterActionWidth)
            } else {
                Color.clear.frame(width: Theme.gutterActionWidth, height: 20)
            }
        }
    }

    private func alignedGutterBackground(for row: AlignedRow) -> Color {
        switch row.diffCategory {
        case .equal: return Theme.gutterBackground
        case .modified: return Theme.gutterModifiedBackground
        case .leftOnly: return Theme.gutterRemovedBackground
        case .rightOnly: return Theme.gutterAddedBackground
        }
    }

    // MARK: - Reorganize Preview

    private func handleReorganizePreview(vm: ComparisonViewModel, hideComments: Bool) {
        if vm.isReorgPreviewActive && vm.previewCommentHandling == (hideComments ? .discard : .moveWithKey) {
            // Toggle off if same mode
            vm.clearReorgPreview()
            toastManager.show("Preview cleared", severity: .info)
        } else {
            vm.activateReorgPreview(hideComments: hideComments)
            let mode = hideComments ? "Preview active (comments hidden)" : "Preview active"
            toastManager.show("\(mode) — display only", severity: .info)
        }
    }

    // MARK: - Reorganize Apply

    @State private var pendingApplySides: [PanelSide] = []
    @State private var pendingApplyStripComments: Bool = false

    private func initiateReorganizeApply(vm: ComparisonViewModel, scope: PanelSide?, stripComments: Bool) {
        pendingApplySides = scope.map { [$0] } ?? [.left, .right]
        pendingApplyStripComments = stripComments

        let extraNote = stripComments ? " All comments will be removed." : " Comments are handled per your Settings preference."
        confirmationService.requestDecision(
            title: "Reorganize File",
            message: "This will rewrite the file: group keys by prefix and sort alphabetically.\(extraNote) This cannot be undone after save.",
            confirmLabel: "Apply",
            isDestructive: true,
            onConfirm: { executeReorganizeApply(vm) }
        )
    }

    private func executeReorganizeApply(_ vm: ComparisonViewModel) {
        var totalGroups = 0
        var totalKeys = 0

        for side in pendingApplySides {
            let detection = vm.detectConvention(side: side)

            if pendingApplyStripComments {
                // Use ConsolidateEngine for stripping comments
                let result = vm.consolidate(side: side, convention: detection.dominant, includeHeaders: false)
                totalGroups += result.groupCount
                totalKeys += result.keyCount
            } else {
                // Use SemanticReorg with settings preference
                let commentHandling = settings.reorgCommentHandling
                let result = vm.reorganize(side: side, convention: detection.dominant, commentHandling: commentHandling)
                totalGroups += result.groupCount
                totalKeys += result.keyCount
            }
        }

        // Clear preview if it was active
        if vm.isReorgPreviewActive {
            vm.clearReorgPreview()
        }

        toastManager.show(
            "Reorganized \(totalKeys) keys into \(totalGroups) groups",
            severity: .success
        )

        pendingApplySides = []
    }

    // MARK: - Remove Comments

    private func initiateRemoveComments(vm: ComparisonViewModel) {
        confirmationService.requestDecision(
            title: "Remove All Comments",
            message: "This will permanently strip all comment and blank lines from both files. This is undoable.",
            confirmLabel: "Remove All",
            isDestructive: true,
            onConfirm: { executeRemoveComments(vm) }
        )
    }

    private func executeRemoveComments(_ vm: ComparisonViewModel) {
        let leftResult = vm.removeComments(side: .left)
        let rightResult = vm.removeComments(side: .right)
        let total = leftResult.removedCount + rightResult.removedCount

        // Clear hidden state since comments are now gone
        vm.areCommentsHidden = false

        if total == 0 {
            toastManager.show("No comments to remove", severity: .info)
        } else {
            toastManager.show("Removed \(total) comment/blank lines", severity: .success)
        }
    }

    // MARK: - Panel Container

    /// Wraps content in a horizontal ScrollView when word wrap is OFF.
    /// When word wrap is ON, constrains content to the panel width so text actually wraps.
    @ViewBuilder
    private func panelContainer(width: CGFloat, wordWrap: Bool, @ViewBuilder content: () -> some View) -> some View {
        if wordWrap {
            content()
                .frame(width: width, alignment: .leading)
                .clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                content()
                    .frame(minWidth: width)
            }
            .frame(width: width)
            .clipped()
        }
    }

    // MARK: - Helpers

    /// Find the index of an entry's rawLine in the lines array (by line number).
    private func lineIndex(for entry: EnvEntry?, in lines: [String]) -> Int? {
        guard let entry else { return nil }
        let idx = entry.lineNumber - 1
        guard idx >= 0, idx < lines.count else { return nil }
        return idx
    }

    private func gutterBackground(for row: ComparisonRow) -> Color {
        guard let cat = row.diffCategory, row.rowType == .diff else {
            return Theme.gutterBackground
        }
        switch cat {
        case .equal: return Theme.gutterBackground
        case .modified: return Theme.gutterModifiedBackground
        case .leftOnly: return Theme.gutterRemovedBackground
        case .rightOnly: return Theme.gutterAddedBackground
        }
    }
}

#Preview {
    ComparisonView(onBack: {})
        .environment(AppState())
}
