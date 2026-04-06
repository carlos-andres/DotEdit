import SwiftUI

/// Settings sheet with immediate-apply controls.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Divider()

            Form {
                // MARK: - Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Editor font", selection: $settings.fontFamily) {
                        ForEach(MonospaceFontProvider.availableFonts(), id: \.self) { name in
                            Text(name)
                                .font(name == "System"
                                    ? .system(.body, design: .monospaced)
                                    : .custom(name, size: NSFont.systemFontSize))
                                .tag(name)
                        }
                    }

                    Toggle("Word wrap", isOn: $settings.wordWrap)
                    Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                }

                // MARK: - Diff
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Export prefix", selection: $settings.exportPrefixMode) {
                            ForEach(AppSettings.ExportPrefixMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }

                        Text("Some .env files use `export KEY=value` for shell sourcing.\n• Preserve — treat `export KEY` and `KEY` as different\n• Remove — strip `export` before comparing\n• Skip — exclude `export` lines from diff")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }

                    Toggle("Case-insensitive key matching", isOn: $settings.caseInsensitiveKeys)
                } header: {
                    Text("Diff Comparison")
                }

                // MARK: - Save
                Section("Save") {
                    Toggle("Create backup before saving", isOn: $settings.createBackupOnSave)
                }

                // MARK: - Transfer
                Section {
                    Picker("Transfer mode", selection: $settings.transferMode) {
                        ForEach(AppSettings.TransferMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Text("Full Line copies the entire raw line.\nValue Only keeps the target's key, export prefix, and quote style — replaces only the value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                } header: {
                    Text("Transfer")
                }

                // MARK: - Reorganize
                Section {
                    Picker("Comment handling", selection: $settings.reorgCommentHandling) {
                        ForEach(SemanticReorg.CommentHandling.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Text("Controls how comments are handled during Reorganize.\n• Move with key — attach comments to their following key\n• Move to end — collect all comments at the bottom\n• Discard — remove all comments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                } header: {
                    Text("Reorganize")
                }

            }
            .formStyle(.grouped)
        }
        // 80%×76% of min resolution (1024×768) — matches HelpView
        .frame(width: 820, height: 580)
    }
}
