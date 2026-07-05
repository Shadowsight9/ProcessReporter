import Foundation

struct ForegroundUsageAppSnapshot: Codable, Equatable, Sendable {
    var bundleIdentifier: String
    var name: String
    var description: String
    var duration: Double
}

struct ForegroundUsageSnapshot: Codable, Equatable, Sendable {
    var date: String
    var apps: [ForegroundUsageAppSnapshot]
    var totalDuration: Double
    var currentBundleIdentifier: String?

    func duration(forBundleIdentifier bundleIdentifier: String?) -> Double {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return 0 }
        return apps.first { $0.bundleIdentifier == bundleIdentifier }?.duration ?? 0
    }
}

@MainActor
final class ForegroundUsageTracker {
    static let shared = ForegroundUsageTracker()

    private struct StoredEntry: Codable {
        var bundleIdentifier: String
        var name: String
        var duration: Double
    }

    private struct StoredState: Codable {
        var date: String
        var entries: [StoredEntry]
    }

    private let storageKey = "foregroundUsageDailyStats"
    private var currentBundleIdentifier: String?
    private var currentName: String?
    private var currentStartDate: Date?
    private var activeDateKey: String
    private var durations: [String: StoredEntry] = [:]
    private let calendar = Calendar.autoupdatingCurrent

    private init() {
        let now = Date()
        activeDateKey = Self.dateKey(for: now, calendar: calendar)
        loadStoredState(for: now)
    }

    func focusChanged(to info: FocusedWindowInfo, at date: Date = Date()) {
        settleCurrentApp(until: date)
        rollToCurrentDayIfNeeded(at: date)
        currentBundleIdentifier = info.applicationIdentifier
        currentName = info.appName
        currentStartDate = date
        ensureEntry(bundleIdentifier: info.applicationIdentifier, name: info.appName)
    }

    func pause(at date: Date = Date()) {
        settleCurrentApp(until: date)
        currentBundleIdentifier = nil
        currentName = nil
        currentStartDate = nil
    }

    func snapshot(at date: Date = Date(), mappings: [PreferencesDataModel.Mapping]) -> ForegroundUsageSnapshot {
        rollToCurrentDayIfNeeded(at: date)

        var entries = durations
        if let bundleIdentifier = currentBundleIdentifier,
           let name = currentName,
           let currentStartDate {
            addDuration(
                from: max(currentStartDate, calendar.startOfDay(for: date)),
                to: date,
                bundleIdentifier: bundleIdentifier,
                name: name,
                entries: &entries
            )
        }

        let apps = entries.values
            .map { entry in
                let display = Self.displayValues(
                    bundleIdentifier: entry.bundleIdentifier,
                    name: entry.name,
                    mappings: mappings
                )
                return ForegroundUsageAppSnapshot(
                    bundleIdentifier: entry.bundleIdentifier,
                    name: display.name,
                    description: display.description,
                    duration: max(0, entry.duration)
                )
            }
            .filter { $0.duration > 0 }
            .sorted {
                if $0.duration == $1.duration {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.duration > $1.duration
            }

        return ForegroundUsageSnapshot(
            date: Self.dateKey(for: date, calendar: calendar),
            apps: apps,
            totalDuration: apps.reduce(0) { $0 + $1.duration },
            currentBundleIdentifier: currentBundleIdentifier
        )
    }

    private func settleCurrentApp(until date: Date) {
        guard let bundleIdentifier = currentBundleIdentifier,
              let name = currentName,
              let startDate = currentStartDate
        else {
            rollToCurrentDayIfNeeded(at: date)
            return
        }

        addDuration(
            from: startDate,
            to: date,
            bundleIdentifier: bundleIdentifier,
            name: name,
            entries: &durations
        )
        currentStartDate = date
        persist()
    }

    private func addDuration(
        from startDate: Date,
        to endDate: Date,
        bundleIdentifier: String,
        name: String,
        entries: inout [String: StoredEntry]
    ) {
        guard endDate > startDate, !bundleIdentifier.isEmpty else { return }

        let endDateKey = Self.dateKey(for: endDate, calendar: calendar)
        if activeDateKey != endDateKey {
            activeDateKey = endDateKey
            durations.removeAll()
            entries.removeAll()
        }

        let effectiveStartDate = max(startDate, calendar.startOfDay(for: endDate))
        let duration = max(0, endDate.timeIntervalSince(effectiveStartDate))
        guard duration > 0 else {
            ensureEntry(bundleIdentifier: bundleIdentifier, name: name)
            return
        }

        var entry = entries[bundleIdentifier] ?? StoredEntry(
            bundleIdentifier: bundleIdentifier,
            name: name,
            duration: 0
        )
        entry.name = name
        entry.duration += duration
        entries[bundleIdentifier] = entry
    }

    private func rollToCurrentDayIfNeeded(at date: Date) {
        let dateKey = Self.dateKey(for: date, calendar: calendar)
        guard activeDateKey != dateKey else { return }
        activeDateKey = dateKey
        durations.removeAll()
        if currentStartDate != nil {
            currentStartDate = calendar.startOfDay(for: date)
        }
        persist()
    }

    private func ensureEntry(bundleIdentifier: String, name: String) {
        guard !bundleIdentifier.isEmpty else { return }
        if durations[bundleIdentifier] == nil {
            durations[bundleIdentifier] = StoredEntry(
                bundleIdentifier: bundleIdentifier,
                name: name,
                duration: 0
            )
            persist()
        }
    }

    private func loadStoredState(for date: Date) {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(StoredState.self, from: data),
              state.date == Self.dateKey(for: date, calendar: calendar)
        else {
            durations.removeAll()
            persist()
            return
        }

        activeDateKey = state.date
        durations = Dictionary(uniqueKeysWithValues: state.entries.map { ($0.bundleIdentifier, $0) })
    }

    private func persist() {
        let state = StoredState(
            date: activeDateKey,
            entries: durations.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func displayValues(
        bundleIdentifier: String,
        name: String,
        mappings: [PreferencesDataModel.Mapping]
    ) -> (name: String, description: String) {
        var displayName = name
        var description = ""

        for rule in mappings where rule.type == .processApplicationIdentifier {
            if rule.from == bundleIdentifier {
                displayName = rule.to
                description = rule.description
                break
            }
        }

        for rule in mappings where rule.type == .processName {
            if rule.from == name {
                displayName = rule.to
                description = rule.description
                break
            }
        }

        return (displayName, description)
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
