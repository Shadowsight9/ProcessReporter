import Foundation

struct MappingDictionaryValue: Equatable {
    let id: String?
    let type: String
    let from: String
    let to: String
    let description: String
}

enum MappingDictionaryParser {
    static func parse(_ value: Any) -> MappingDictionaryValue? {
        guard let dict = value as? [String: Any],
              let type = dict["type"] as? String,
              let from = dict["from"] as? String
        else {
            return nil
        }

        let rawTo = dict["to"] as? String ?? ""
        let to = rawTo.isEmpty ? from : rawTo
        let description = dict["description"] as? String ?? ""
        return MappingDictionaryValue(
            id: dict["id"] as? String,
            type: type,
            from: from,
            to: to,
            description: description
        )
    }
}
