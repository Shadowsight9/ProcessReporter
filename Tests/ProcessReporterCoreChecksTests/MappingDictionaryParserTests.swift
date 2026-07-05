import Testing
@testable import ProcessReporterCoreChecks

@Test func mappingDictionaryParserAcceptsValidRows() {
    let parsed = MappingDictionaryParser.parse([
        "type": "process_name",
        "from": "Code",
        "to": "Xcode",
    ])

    #expect(
        parsed == MappingDictionaryValue(
            id: nil,
            type: "process_name",
            from: "Code",
            to: "Xcode",
            description: ""
        )
    )
}

@Test func mappingDictionaryParserAcceptsDescriptionOnlyRows() {
    let parsed = MappingDictionaryParser.parse([
        "type": "process_application_identifier",
        "from": "com.google.Chrome",
        "description": "I am surfing the web",
    ])

    #expect(
        parsed == MappingDictionaryValue(
            id: nil,
            type: "process_application_identifier",
            from: "com.google.Chrome",
            to: "com.google.Chrome",
            description: "I am surfing the web"
        )
    )
}

@Test func mappingDictionaryParserRejectsInvalidRows() {
    #expect(MappingDictionaryParser.parse(["type": "process_name"]) == nil)
    #expect(MappingDictionaryParser.parse(["type": 1, "from": "Code", "to": "Xcode"]) == nil)
}
