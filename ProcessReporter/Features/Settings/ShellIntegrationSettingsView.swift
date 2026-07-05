import AppKit
import SwiftUI

struct ShellIntegrationSettingsView: View {
    @ObservedObject var store: PreferencesStore
    @State private var draft = PreferencesDataModel.shellIntegration.value
    @State private var isTesting = false
    @State private var environmentVariablesExpanded = false

    private let environmentVariables = [
        "PROCESS_REPORTER_JSON",
        "PROCESS_REPORTER_PROCESS_NAME",
        "PROCESS_REPORTER_PROCESS_DESCRIPTION",
        "PROCESS_REPORTER_PROCESS_DAILY_FOREGROUND_DURATION",
        "PROCESS_REPORTER_WINDOW_TITLE",
        "PROCESS_REPORTER_PROCESS_BUNDLE_ID",
        "PROCESS_REPORTER_MEDIA_NAME",
        "PROCESS_REPORTER_MEDIA_ARTIST",
        "PROCESS_REPORTER_MEDIA_ALBUM",
        "PROCESS_REPORTER_MEDIA_PROCESS_NAME",
        "PROCESS_REPORTER_MEDIA_PROCESS_DESCRIPTION",
        "PROCESS_REPORTER_MEDIA_PROCESS_BUNDLE_ID",
        "PROCESS_REPORTER_MEDIA_DURATION",
        "PROCESS_REPORTER_MEDIA_ELAPSED_TIME",
        "PROCESS_REPORTER_MEDIA_PLAYING",
        "PROCESS_REPORTER_FOREGROUND_USAGE_JSON",
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
                Label("Command \(selectedSlot.id + 1)", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                
                LabeledContent("Timeout") {
                   TextField(
                       "Seconds",
                       value: Binding(
                           get: { selectedSlot.timeoutSeconds },
                           set: { setSelectedSlotTimeout($0) }
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

                TextEditor(text: Binding(
                    get: { selectedSlot.command },
                    set: { setSelectedSlotCommand($0) }
                ))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)

                if selectedSlot.command.isEmpty {
                    Text("curl -X POST \"https://example.com/report\" -H \"Content-Type: application/json\" -d \"$PROCESS_REPORTER_JSON\"")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                }
            }

            slotPicker
        }
    }

    private var slotPicker: some View {
        HStack(spacing: 8) {
            ForEach(0..<ShellIntegration.slotCount, id: \.self) { index in
                Button {
                    draft.selectedSlotIndex = index
                    draft = draft.sanitized()
                } label: {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(draft.normalizedSelectedSlotIndex == index ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(draft.normalizedSelectedSlotIndex == index ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Command slot \(index + 1)")
            }
        }
    }

    private var environmentVariableGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                    environmentVariablesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                        .rotationEffect(.degrees(environmentVariablesExpanded ? 90 : 0))
                    Label("Environment Variables", systemImage: "curlybraces")
                        .font(.headline)
                    Text("\(environmentVariables.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .animation(.snappy(duration: 0.2, extraBounce: 0), value: environmentVariablesExpanded)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if environmentVariablesExpanded {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 6)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(environmentVariables, id: \.self) { variable in
                        EnvironmentVariableButton(variable: variable) {
                            copy("$" + variable)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var lastResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Last Result", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(selectedSlot.lastExitCode.map { "Exit \($0)" } ?? "Not tested")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(selectedSlot.lastExitCode == 0 ? .green : .secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                outputView(title: "Stdout", text: selectedSlot.lastStdout)
                outputView(title: "Stderr", text: selectedSlot.lastStderr)
            }
        }
    }

    private var commandIsEmpty: Bool {
        selectedSlot.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedSlot: ShellCommandSlot {
        draft.sanitized().selectedSlot
    }

    private func setSelectedSlotCommand(_ command: String) {
        draft = draft.sanitized()
        let index = draft.normalizedSelectedSlotIndex
        guard draft.slots.indices.contains(index) else { return }
        draft.slots[index].command = command
    }

    private func setSelectedSlotTimeout(_ timeoutSeconds: Int) {
        draft = draft.sanitized()
        let index = draft.normalizedSelectedSlotIndex
        guard draft.slots.indices.contains(index) else { return }
        draft.slots[index].timeoutSeconds = min(max(timeoutSeconds, 1), 300)
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
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("$" + variable)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Copy $" + variable)
    }
}
