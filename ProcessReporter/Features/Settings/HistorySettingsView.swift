import SwiftUI

struct HistorySettingsView: View {
    @State private var reports: [ReportValue] = []
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search by process or media name", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await loadReports() } }
                Button("Search") { Task { await loadReports() } }
                Button("Open Database Location", action: openDatabaseLocation)
                Button("Clear History", role: .destructive) {
                    Task {
                        try? await DataStore.shared.deleteAllReports()
                        await loadReports()
                    }
                }
            }

            List(reports, id: \.id) { report in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(report.processName ?? "-")
                            .font(.headline)
                        Spacer()
                        Text(report.timeStamp.formatted(date: .abbreviated, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                    Text(report.mediaName ?? "-")
                        .foregroundStyle(.secondary)
                    if !report.integrations.isEmpty {
                        Text(report.integrations.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .task { await loadReports() }
        .onReceive(NotificationCenter.default.publisher(for: DataStore.changedNotification)) { _ in
            Task { await loadReports() }
        }
    }

    private func loadReports() async {
        reports = await DataStore.shared.fetchReports(
            searchText: searchText.isEmpty ? nil : searchText,
            offset: 0,
            limit: 50,
            ascending: false
        )
    }

    private func openDatabaseLocation() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appSupportURL.appendingPathComponent(bundleID).path)
    }
}
