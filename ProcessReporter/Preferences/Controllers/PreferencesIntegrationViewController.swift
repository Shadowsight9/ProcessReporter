//
//  PreferencesIntegrationViewController.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/6.
//

import AppKit
import SnapKit

class PreferencesIntegrationViewController: NSViewController, SettingWindowProtocol {
    var frameSize: NSSize = NSSize(width: 600, height: 400)

    override func loadView() {
        let shellView = PreferencesIntegrationShellView()
        view = NSView()
        view.addSubview(shellView)
        shellView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
