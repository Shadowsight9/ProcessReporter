import SwiftUI

struct MappingSettingsView: View {
	@ObservedObject var store: PreferencesStore
	@State var selectedItem: Set<String> = []

	@State var addNewItemSheetOpen = false
	@State var editingItem: PreferencesDataModel.Mapping? = nil
	@State var editingIndex: Int? = nil

	var body: some View {
		VStack {
			HStack {
				VStack(alignment: .leading) {
					Text("Mapping").font(.headline)
						.padding(.bottom, 4)

					Text("Setting the rewrite rules for the display name when a process is reported.")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}.padding()
				Spacer()
			}

			Table(store.mappings, selection: $selectedItem) {
				TableColumn("type") { item in
					Text(item.type.toCopyable())
						.lineLimit(1)
				}.width(min: 150)

				TableColumn("from") { item in
					Text(item.from)
						.lineLimit(1)
				}
				TableColumn("to") { item in
					Text(item.to.isEmpty ? item.from : item.to)
						.lineLimit(1)
				}
				TableColumn("description") { item in
					Text(item.description)
						.lineLimit(1)
				}
			}.frame(maxHeight: .infinity)
				.tableStyle(.inset)
				.contextMenu(forSelectionType: PreferencesDataModel.Mapping.ID.self) { selection in
					Button("Edit") {
						if let id = selection.first, let item = store.mappings.first(where: { $0.id == id }) {
							editingItem = item
							editingIndex = store.mappings.firstIndex(where: { $0.id == id })
						}
					}
					Divider()
					Button("Delete", role: .destructive) {
						removeMappings(withIDs: selection)
					}
				} primaryAction: { _ in
					if selectedItem.count == 1, let id = selectedItem.first, let itemIndex = store.mappings.firstIndex(where: { $0.id == id }) {
						let item = store.mappings[itemIndex]
						editingItem = item
						editingIndex = itemIndex
					}
				}

			HStack(spacing: 8) {
				Spacer()
				Button {
					addNewItemSheetOpen.toggle()
				} label: {
					Label("Add Mapping", systemImage: "plus")
				}
				.buttonStyle(.bordered)
				.controlSize(.small)

				Button(role: .destructive) {
					removeSelectedMappings()
				} label: {
					Label("Remove", systemImage: "minus")
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.disabled(selectedItem.isEmpty)
				.keyboardShortcut(.delete, modifiers: [])
			}.padding(.bottom, 12).padding(.top, 6).padding(.trailing, 12)
		}
		.onDeleteCommand {
			removeSelectedMappings()
		}
		.onChange(of: store.mappings.map(\.id)) { _, ids in
			selectedItem.formIntersection(Set(ids))
		}
		.sheet(isPresented: $addNewItemSheetOpen) {
			withAnimation {
				AddNewMappingView(mode: .add, onComplete: { from, to, description, type in
					store.addMapping(type: type, from: from, to: to, description: description)
				})
			}
		}
		.sheet(item: $editingItem) { item in
			AddNewMappingView(mode: .edit(item), onComplete: { from, to, description, type in
				if let editingIndex {
					store.editMapping(
						type: type,
						from: from,
						to: to,
						description: description,
						index: editingIndex
					)
				}
			})
		}
	}

	private func removeSelectedMappings() {
		removeMappings(withIDs: selectedItem)
	}

	private func removeMappings(withIDs ids: Set<PreferencesDataModel.Mapping.ID>) {
		guard !ids.isEmpty else { return }
		withAnimation {
			store.removeMappings(store.mappings.filter { ids.contains($0.id) })
			selectedItem.subtract(ids)
		}
	}
}

struct AddNewMappingView: View {
	enum Mode: Identifiable, Equatable {
		static func == (lhs: AddNewMappingView.Mode, rhs: AddNewMappingView.Mode) -> Bool {
			switch (lhs, rhs) {
			case (.add, .add): return true
			case (.edit(let lhsMapping), .edit(let rhsMapping)): return lhsMapping == rhsMapping
			default: return false
			}
		}

		case add
		case edit(PreferencesDataModel.Mapping)
		var id: String {
			switch self {
			case .add: return "add"
			case .edit(let mapping): return "edit-" + mapping.id
			}
		}
	}

	@State var from: String = ""
	@State var to: String = ""
	@State var description: String = ""
	@State var type: PreferencesDataModel.MappingType = .processApplicationIdentifier
	@State private var lastAutoFilledTarget: String = ""

	var mode: Mode = .add
	typealias OnCompleteCallback = (
		_ from: String,
		_ to: String,
		_ description: String,
		_ type: PreferencesDataModel.MappingType
	) -> Void
	var onComplete: OnCompleteCallback

	@Environment(\.presentationMode) private var presentationMode

	init(mode: Mode = .add, onComplete: @escaping OnCompleteCallback) {
		self.mode = mode
		self.onComplete = onComplete
		switch mode {
		case .add:
			break
		case .edit(let mapping):
			_from = State(initialValue: mapping.from)
			let target = mapping.to.isEmpty
				? Self.defaultTargetName(from: mapping.from, type: mapping.type)
				: mapping.to
			_to = State(initialValue: target)
			_lastAutoFilledTarget = State(initialValue: target)
			_description = State(initialValue: mapping.description)
			_type = State(initialValue: mapping.type)
		}
	}

	@State var appSelectorOpen = false

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Text(mode == Mode.add ? "Add New Mapping" : "Edit Mapping")
				.font(.title2)
				.bold()
				.padding(.bottom, 8)

			Grid(horizontalSpacing: 16, verticalSpacing: 12) {
				GridRow {
					Text("From")
						.frame(width: 70, alignment: .trailing)
					ZStack(alignment: .trailing) {
						TextField("Enter the original name", text: $from)
							.textFieldStyle(RoundedBorderTextFieldStyle())
							.frame(minWidth: 200)

						if type == .processApplicationIdentifier || type == .mediaProcessApplicationIdentifier {
							Button {
								appSelectorOpen.toggle()
							} label: {
								Image(systemName: "scope").font(.system(size: 12, weight: .bold))
							}.buttonStyle(.plain).padding(.trailing, 3)
						}
					}
				}
				GridRow {
					Text("Filter Type")
						.frame(width: 70, alignment: .trailing)
					Picker("", selection: $type) {
						ForEach(PreferencesDataModel.MappingType.allCases, id: \.self) { type in
							Text(type.toCopyable()).tag(type)
						}
					}
					.pickerStyle(.menu)
					.frame(minWidth: 200)
				}
				GridRow {
					Text("Target Name")
						.frame(width: 100, alignment: .trailing)
					TextField("Defaults to the original name", text: $to)
						.textFieldStyle(RoundedBorderTextFieldStyle())
						.frame(minWidth: 200)
				}
				GridRow {
					Text("Description")
						.frame(width: 100, alignment: .trailing)
					TextField("Add a note for this app", text: $description)
						.textFieldStyle(RoundedBorderTextFieldStyle())
						.frame(minWidth: 200)
				}
			}
			.padding(.horizontal, 8)

			HStack {
				Spacer()
				Button("Cancel") {
					presentationMode.wrappedValue.dismiss()
				}
				.keyboardShortcut(.cancelAction)
				.buttonStyle(.bordered)

				Button("Done") {
					onComplete(from, normalizedTargetName(), description, type)
					presentationMode.wrappedValue.dismiss()
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
				.disabled(from.isEmpty || normalizedTargetName().isEmpty)
			}
			.padding(.top, 8)
		}
		.onChange(of: from) { _, newValue in
			refreshTargetNameIfNeeded(from: newValue, type: type)
		}
		.onChange(of: type) { _, newValue in
			refreshTargetNameIfNeeded(from: from, type: newValue)
		}
		.padding(24)
		.frame(width: 420)
		.sheet(isPresented: $appSelectorOpen) {
			AppPickerView { id, _ in
				appSelectorOpen = false
				guard let id = id else { return }
				from = id
				refreshTargetNameIfNeeded(from: id, type: type)
			}.frame(width: 400, height: 500)
		}
	}

	private func normalizedTargetName() -> String {
		let trimmedTarget = to.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedTarget.isEmpty {
			return trimmedTarget
		}
		return Self.defaultTargetName(from: from, type: type)
	}

	private func refreshTargetNameIfNeeded(
		from newFrom: String,
		type newType: PreferencesDataModel.MappingType
	) {
		let nextTarget = Self.defaultTargetName(from: newFrom, type: newType)
		if to.isEmpty || to == lastAutoFilledTarget {
			to = nextTarget
			lastAutoFilledTarget = nextTarget
		}
	}

	private static func defaultTargetName(
		from: String,
		type: PreferencesDataModel.MappingType
	) -> String {
		guard !from.isEmpty else { return "" }
		switch type {
		case .processApplicationIdentifier, .mediaProcessApplicationIdentifier:
			return AppUtility.shared.getAppInfo(for: from).displayName
		case .processName, .mediaProcessName:
			return from
		}
	}
}
