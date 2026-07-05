//
//  PreferencesDataModel+Mapping.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/21.
//
import Foundation

extension PreferencesDataModel {
	@UserDefaultsRelay("mappingList", defaultValue: [Mapping]())
	static var mappingList: BehaviorRelay<[Mapping]>
}

extension PreferencesDataModel {
	enum MappingType: String, CaseIterable, UserDefaultsJSONStorable {
		static func fromDictionary(_ dict: Any) -> MappingType {
			return self.init(rawValue: dict as! String) ?? .processApplicationIdentifier
		}
	 
		static func fromStorable(_ value: Any?) -> MappingType? {
			guard let value = value else { return nil }
			return fromDictionary(value)
		}
	 
		func toStorable() -> Any? {
			return rawValue
		}
	 
		case processApplicationIdentifier = "process_application_identifier"
		case processName = "process_name"
		case mediaProcessApplicationIdentifier = "media_process_application_identifier"
		case mediaProcessName = "media_process_name"
		
		func toCopyable() -> String {
			switch self {
				case .processApplicationIdentifier:
					return "Process Application Identifier"
				case .mediaProcessName:
					return "Media Process Name"
				case .mediaProcessApplicationIdentifier:
					return "Media Process Application Identifier"
				case .processName:
					return "Process Name"
			}
		}
	}

	struct Mapping: UserDefaultsJSONStorable, Identifiable {
		var id: String {
			"\(from)-\(to)-\(type.rawValue)"
		}
		
		static func fromDictionary(_ dict: Any) -> Mapping {
			let dict = dict as! [String: Any]
			let type = MappingType.fromDictionary(dict["type"]!)
			let from = dict["from"] as! String
			let to = dict["to"] as! String
			return Mapping(type: type, from: from, to: to)
		}

		func toDictionary() -> [String: Any] {
			[
				"type": type.rawValue,
				"from": from,
				"to": to,
			]
		}
	 
		let type: MappingType
		let from: String
		let to: String
		
		static func == (lhs: Mapping, rhs: Mapping) -> Bool {
			return lhs.type == rhs.type && lhs.from == rhs.from && lhs.to == rhs.to
		}
	}

}

extension Array: UserDefaultsStorable where Element == PreferencesDataModel.Mapping {
	func toStorable() -> Any? {
		map { $0.toDictionary() }
	}

	static func fromStorable(_ value: Any?) -> [PreferencesDataModel.Mapping]? {
		guard let value = value as? [[String: Any]] else { return nil }
		return value.map { PreferencesDataModel.Mapping.fromDictionary($0) }
	}
}
