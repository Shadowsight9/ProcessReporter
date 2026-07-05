import AppKit
import SnapKit

class PreferencesIntegrationShellView: IntegrationView {
    private let enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let commandInput = NSScrollTextField()
    private let timeoutInput = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let stdoutTextView = NSTextView()
    private let stderrTextView = NSTextView()

    private lazy var saveButton: NSButton = {
        let button = NSButton(title: "Save", target: self, action: #selector(save))
        button.bezelStyle = .push
        button.keyEquivalent = "\r"
        return button
    }()

    private lazy var resetButton: NSButton = {
        let button = NSButton(title: "Reset", target: self, action: #selector(reset))
        button.bezelStyle = .rounded
        return button
    }()

    private lazy var testButton: NSButton = {
        let button = NSButton(title: "Test", target: self, action: #selector(testCommand))
        button.bezelStyle = .rounded
        return button
    }()

    init() {
        super.init(frame: .zero)
        commandInput.placeholderString = "curl -X POST https://example.com/report -d \"$PROCESS_REPORTER_JSON\""
        timeoutInput.placeholderString = "10"
        setupGridView()
        synchronizeUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupGridView() {
        setupUI()

        createRow(leftView: NSTextField(labelWithString: "Enabled"), rightView: enabledButton)
        createRow(leftView: NSTextField(labelWithString: "Command"), rightView: commandInput)
        createRow(leftView: NSTextField(labelWithString: "Timeout"), rightView: timeoutInput)
        createRowDescription(text: "Runs locally with your user permissions. Imported commands stay disabled until enabled here.")

        let buttonStack = NSStackView(views: [resetButton, testButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        gridView.addRow(with: [NSView(), buttonStack])
        gridView.cell(for: buttonStack)?.xPlacement = .trailing

        createRow(leftView: NSTextField(labelWithString: "Last Exit"), rightView: statusLabel)
        createRow(leftView: NSTextField(labelWithString: "Stdout"), rightView: scrollView(for: stdoutTextView))
        createRow(leftView: NSTextField(labelWithString: "Stderr"), rightView: scrollView(for: stderrTextView))
    }

    private func scrollView(for textView: NSTextView) -> NSScrollView {
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(360)
            make.height.equalTo(90)
        }
        return scrollView
    }

    private func synchronizeUI() {
        let integration = PreferencesDataModel.shellIntegration.value
        enabledButton.state = integration.isEnabled ? .on : .off
        commandInput.stringValue = integration.command
        timeoutInput.stringValue = String(integration.timeoutSeconds)
        statusLabel.stringValue = integration.lastExitCode.map(String.init) ?? "-"
        stdoutTextView.string = integration.lastStdout
        stderrTextView.string = integration.lastStderr
    }

    @objc private func reset() {
        synchronizeUI()
    }

    @objc private func save() {
        saveToModel()
        ToastManager.shared.success("Saved!")
    }

    @objc private func testCommand() {
        saveToModel()
        testButton.isEnabled = false
        Task {
            let report = await makeCurrentReport()
            _ = await ShellReporterExtension.send(data: report, requireEnabled: false)
            await MainActor.run {
                self.testButton.isEnabled = true
                self.synchronizeUI()
            }
        }
    }

    private func saveToModel() {
        var integration = PreferencesDataModel.shellIntegration.value
        integration.isEnabled = enabledButton.state == .on
        integration.command = commandInput.stringValue
        integration.timeoutSeconds = max(Int(timeoutInput.stringValue) ?? 10, 1)
        PreferencesDataModel.shellIntegration.accept(integration)
    }

    private func makeCurrentReport() async -> ReportModel {
        let report = ReportModel(
            windowInfo: ApplicationMonitor.shared.getFocusedWindowInfo(),
            integrations: [],
            mediaInfo: try? await MediaInfoManager.getMediaInfoAsync(timeout: 1.0)
        )
        return report
    }
}
