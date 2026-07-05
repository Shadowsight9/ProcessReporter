//
//  PreferencesDataModel+Integration.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/8.
//

import Foundation

struct ShellIntegration: UserDefaultsJSONStorable {
    static let slotCount = 4

    var slots: [ShellCommandSlot] = ShellCommandSlot.defaultSlots()
    var isEnabled: Bool = false
    var selectedSlotIndex: Int = 0

    var selectedSlot: ShellCommandSlot {
        guard !slots.isEmpty else { return .init(id: 0) }
        let normalized = normalizedSelectedSlotIndex
        return slots[normalized]
    }

    var normalizedSelectedSlotIndex: Int {
        min(max(selectedSlotIndex, 0), max(slots.count - 1, 0))
    }
}

struct ShellCommandSlot: UserDefaultsJSONStorable, Identifiable, Equatable {
    var id: Int
    var command: String = ""
    var timeoutSeconds: Int = 10
    var lastExitCode: Int?
    var lastStdout: String = ""
    var lastStderr: String = ""
}

extension PreferencesDataModel {
    @UserDefaultsRelay("shellIntegration", defaultValue: ShellIntegration())
    static var shellIntegration: BehaviorRelay<ShellIntegration>
}

extension ShellIntegration {
    func toDictionary() -> [String: Any] {
        [
            "isEnabled": isEnabled,
            "selectedSlotIndex": normalizedSelectedSlotIndex,
            "slots": slots.map { $0.toDictionary() },
        ]
    }

    static func fromDictionary(_ dict: Any) -> ShellIntegration {
        guard let dict = dict as? [String: Any] else { return ShellIntegration() }
        var integration = ShellIntegration()
        integration.isEnabled = dict["isEnabled"] as? Bool ?? false
        integration.selectedSlotIndex = dict["selectedSlotIndex"] as? Int ?? 0
        integration.slots = (dict["slots"] as? [[String: Any]])?
            .compactMap { ShellCommandSlot.fromDictionary($0) } ?? ShellCommandSlot.defaultSlots()
        return integration.sanitized()
    }

    func sanitized() -> ShellIntegration {
        var latest = self
        latest.slots = Array(latest.slots.prefix(Self.slotCount)).enumerated().map { index, slot in
            var sanitizedSlot = slot
            sanitizedSlot.id = index
            sanitizedSlot.timeoutSeconds = min(max(sanitizedSlot.timeoutSeconds, 1), 300)
            return sanitizedSlot
        }

        while latest.slots.count < Self.slotCount {
            latest.slots.append(.init(id: latest.slots.count))
        }

        latest.selectedSlotIndex = min(max(latest.selectedSlotIndex, 0), Self.slotCount - 1)
        return latest
    }
}

extension ShellCommandSlot {
    static func defaultSlots() -> [ShellCommandSlot] {
        (0..<ShellIntegration.slotCount).map { ShellCommandSlot(id: $0) }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "command": command,
            "timeoutSeconds": timeoutSeconds,
            "lastStdout": lastStdout,
            "lastStderr": lastStderr,
        ]
        dict["lastExitCode"] = lastExitCode
        return dict
    }

    static func fromDictionary(_ dict: Any) -> ShellCommandSlot? {
        guard let dict = dict as? [String: Any] else { return nil }
        var slot = ShellCommandSlot(id: dict["id"] as? Int ?? 0)
        slot.command = dict["command"] as? String ?? ""
        slot.timeoutSeconds = dict["timeoutSeconds"] as? Int ?? 10
        slot.lastExitCode = dict["lastExitCode"] as? Int
        slot.lastStdout = dict["lastStdout"] as? String ?? ""
        slot.lastStderr = dict["lastStderr"] as? String ?? ""
        return slot
    }
}
