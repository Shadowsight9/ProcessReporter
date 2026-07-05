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
		static func fromDictionary(_ dict: Any) -> MappingType? {
			guard let value = dict as? String else { return nil }
			return self.init(rawValue: value)
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
		let id: String
		
		static func fromDictionary(_ dict: Any) -> Mapping? {
			guard let parsed = MappingDictionaryParser.parse(dict),
			      let type = MappingType.fromDictionary(parsed.type)
			else {
				return nil
			}
			return Mapping(
				id: parsed.id ?? UUID().uuidString,
				type: type,
				from: parsed.from,
				to: parsed.to,
				description: parsed.description
			)
		}

		func toDictionary() -> [String: Any] {
			[
				"id": id,
				"type": type.rawValue,
				"from": from,
				"to": to,
				"description": description,
			]
		}
	 
		let type: MappingType
		let from: String
		let to: String
		let description: String
		
		static func == (lhs: Mapping, rhs: Mapping) -> Bool {
			return lhs.id == rhs.id
				&& lhs.type == rhs.type
				&& lhs.from == rhs.from
				&& lhs.to == rhs.to
				&& lhs.description == rhs.description
		}
	}

}

extension Array: UserDefaultsStorable where Element == PreferencesDataModel.Mapping {
	func toStorable() -> Any? {
		map { $0.toDictionary() }
	}

	static func fromStorable(_ value: Any?) -> [PreferencesDataModel.Mapping]? {
		guard let value = value as? [[String: Any]] else { return nil }
		return value.compactMap { PreferencesDataModel.Mapping.fromDictionary($0) }
	}
}
