//
//  AppPickerView.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/13.
//
import SwiftUI

// Add AppPickerView to show a dialog for selecting applications
struct AppPickerView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var installedApps: [AppItem] = []
	@State private var searchText: String = ""

	var onSelectApp: (String?, URL?) -> Void

	var body: some View {
		VStack {
			TextField("Search applications", text: $searchText)
				.textFieldStyle(.roundedBorder)
				.padding()

			List {
				ForEach(filteredApps, id: \.id) { app in
					Button(action: {
						onSelectApp(app.applicationIdentifier, app.url)
					}) {
						HStack {
							Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
								.resizable()
								.frame(width: 24, height: 24)
							Text(app.name)
							Spacer()
						}
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain)
				}
			}

			HStack {
				Spacer()
				Button("Cancel") {
					onSelectApp(nil, nil)
				}
				.keyboardShortcut(.cancelAction)
			}
			.padding()
		}
		.onAppear {
			loadInstalledApps()
		}
	}

	typealias AppItem = (id: String, name: String, url: URL, applicationIdentifier: String)
	private var filteredApps: [AppItem] {
		if searchText.isEmpty {
			return installedApps
		} else {
			return installedApps.filter { app in
				app.name.localizedCaseInsensitiveContains(searchText)
			}
		}
	}

	private func loadInstalledApps() {
		installedApps = AppUtility.shared.installedApplications().compactMap { app in
			guard let url = app.path else { return nil }
			return (id: app.bundleID + url.absoluteString, name: app.displayName, url: url, applicationIdentifier: app.bundleID)
		}
	}
}

extension AppPickerView {
	static func showAppPicker(for anchorView: NSView, completion: @escaping (String?, URL?) -> Void) {
		let appPicker = AppPickerView(onSelectApp: completion)
		let hostingController = NSHostingController(rootView: appPicker)

		let popover = NSPopover()
		popover.contentViewController = hostingController
		popover.behavior = .transient
		popover.contentSize = NSSize(width: 400, height: 500)
		popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
	}
}
