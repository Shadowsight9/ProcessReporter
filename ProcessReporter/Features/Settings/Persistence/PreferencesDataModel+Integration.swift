//
//  PreferencesDataModel+Integration.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/8.
//

import Foundation

struct ShellIntegration: UserDefaultsJSONStorable, DictionaryConvertible {
    var isEnabled: Bool = false
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
    static func fromDictionary(_ dict: Any) -> ShellIntegration {
        guard let dict = dict as? [String: Any] else { return ShellIntegration() }
        var integration = ShellIntegration()
        integration.isEnabled = dict["isEnabled"] as? Bool ?? false
        integration.command = dict["command"] as? String ?? ""
        integration.timeoutSeconds = dict["timeoutSeconds"] as? Int ?? 10
        integration.lastExitCode = dict["lastExitCode"] as? Int
        integration.lastStdout = dict["lastStdout"] as? String ?? ""
        integration.lastStderr = dict["lastStderr"] as? String ?? ""
        return integration
    }
}
