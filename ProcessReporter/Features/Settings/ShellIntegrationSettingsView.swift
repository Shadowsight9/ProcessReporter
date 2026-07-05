import AppKit
import SwiftUI

struct ShellIntegrationSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @State private var draft = PreferencesDataModel.shellIntegration.value
    @State private var isTesting = false

    private let environmentVariables = [
        "PROCESS_REPORTER_JSON",
        "PROCESS_REPORTER_PROCESS_NAME",
        "PROCESS_REPORTER_WINDOW_TITLE",
        "PROCESS_REPORTER_PROCESS_BUNDLE_ID",
        "PROCESS_REPORTER_MEDIA_NAME",
        "PROCESS_REPORTER_MEDIA_ARTIST",
        "PROCESS_REPORTER_MEDIA_ALBUM",
        "PROCESS_REPORTER_MEDIA_PROCESS_NAME",
        "PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID",
        "PROCESS_REPORTER_MEDIA_DURATION",
        "PROCESS_REPORTER_MEDIA_ELAPSED_TIME",
        "PROCESS_REPORTER_MEDIA_PLAYING",
        "PROCESS_REPORTER_TIMESTAMP",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                commandEditor
                environmentVariableGrid
                lastResult
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(store.$shellIntegration) { draft = $0 }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shell Integration")
                    .font(.title2.weight(.semibold))
                Text("Runs locally with your user permissions. Imported commands stay disabled until enabled here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Enabled", isOn: $draft.isEnabled)
                .toggleStyle(.switch)

            Button {
                draft = store.shellIntegration
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }

            Button {
                store.saveShell(draft)
            } label: {
                Label("Save", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)

            Button {
                Task {
                    store.saveShell(draft)
                    isTesting = true
                    await store.testShell()
                    draft = store.shellIntegration
                    isTesting = false
                }
            } label: {
                Label(isTesting ? "Testing..." : "Test", systemImage: "play.circle")
            }
            .disabled(commandIsEmpty || isTesting)
        }
    }

    private var commandEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Command", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                
                LabeledContent("Timeout") {
                   TextField(
                       "Seconds",
                       value: Binding(
                           get: { draft.timeoutSeconds },
                           set: { draft.timeoutSeconds = min(max($0, 1), 300) }
                       ),
                       format: .number
                   )
                   .textFieldStyle(.roundedBorder)
                   .monospacedDigit()
                   .frame(width: 72)
               }
                
               Text("s")
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                TextEditor(text: $draft.command)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)

                if draft.command.isEmpty {
                    Text("curl -X POST \"https://example.com/report\" -H \"Content-Type: application/json\" -d \"$PROCESS_REPORTER_JSON\"")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var environmentVariableGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Environment Variables", systemImage: "curlybraces")
                    .font(.headline)
                Spacer()
                Button {
                    copy(environmentVariables.map { "$" + $0 }.joined(separator: "\n"))
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(environmentVariables, id: \.self) { variable in
                    EnvironmentVariableButton(variable: variable) {
                        copy("$" + variable)
                    }
                }
            }
        }
    }

    private var lastResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Last Result", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(draft.lastExitCode.map { "Exit \($0)" } ?? "Not tested")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(draft.lastExitCode == 0 ? .green : .secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                outputView(title: "Stdout", text: draft.lastStdout)
                outputView(title: "Stderr", text: draft.lastStderr)
            }
        }
    }

    private var commandIsEmpty: Bool {
        draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func outputView(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            ScrollView {
                Text(text.isEmpty ? "-" : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 110, maxHeight: 150)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastManager.shared.success("Copied")
    }
}

private struct EnvironmentVariableButton: View {
    let variable: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
                Text("$" + variable)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Copy $" + variable)
    }
}
