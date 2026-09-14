import XCTest
@testable import DecideCore

final class AIValidationTests: XCTestCase {

    func testAWellFormedResponseValidates() throws {
        let validated = try Fixture.validated("valid_ready")
        XCTAssertEqual(validated.status, .ready)
        XCTAssertEqual(validated.category, .technology)
        XCTAssertEqual(validated.options.count, 2)
        XCTAssertEqual(validated.recommendedOptionID, "air")
        XCTAssertEqual(validated.reasons.count, 3)
        XCTAssertTrue(validated.repairedIssues.isEmpty, "Clean input should need no repair: \(validated.repairedIssues)")
    }

    func testGarbageJsonDecodesIntoSomethingThatFailsValidationRatherThanCrashing() throws {
        let response = try Fixture.response("garbage")
        XCTAssertThrowsError(try AIResponseValidator.validate(response)) { error in
            guard case AIValidationError.unrepairable(let issues) = error else {
                return XCTFail("Expected unrepairable, got \(error)")
            }
            XCTAssertFalse(issues.isEmpty)
        }
    }

    func testTruncatedJsonThrowsADecodingErrorNotACrash() {
        let data = Data("{ \"decisionStatus\": \"rea".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AIDecisionResponse.self, from: data))
    }

    func testARecommendationForAnUnknownOptionIsFatal() throws {
        let response = try Fixture.response("invalid_unknown_option")
        XCTAssertThrowsError(try AIResponseValidator.validate(response)) { error in
            guard case AIValidationError.unrepairable(let issues) = error else {
                return XCTFail("Expected unrepairable")
            }
            XCTAssertTrue(issues.contains(.recommendationForUnknownOption("ghost")))
        }
    }

    func testMessyButRecoverableResponseIsRepairedRatherThanRejected() throws {
        let validated = try Fixture.validated("messy_repairable")

        // Duplicates dropped.
        XCTAssertEqual(validated.criteria.filter { $0.id == "taste" }.count, 1)
        XCTAssertEqual(validated.options.filter { $0.id == "a" }.count, 1)
        // Nameless entries dropped.
        XCTAssertFalse(validated.criteria.contains { $0.name.isBlank })
        XCTAssertFalse(validated.options.contains { $0.id.isEmpty })
        // Out-of-range score clamped.
        XCTAssertEqual(validated.options.first { $0.id == "a" }?.score(for: "taste"), 1)
        // Missing scores filled with the explicit "unknown" midpoint.
        XCTAssertEqual(validated.options.first { $0.id == "b" }?.score(for: "taste"), 0.4)
        XCTAssertEqual(validated.options.first { $0.id == "a" }?.score(for: "ease"), 0.5)
        // Unknown enums fall back safely.
        XCTAssertEqual(validated.researchLevel, .none)
        XCTAssertEqual(validated.risks.first?.severity, .medium)
        XCTAssertEqual(validated.questions.first?.kind, .freeText)
    }

    func testInsecureAndMalformedSourcesAreNeverLinked() throws {
        let validated = try Fixture.validated("messy_repairable")
        XCTAssertEqual(validated.research.count, 3)
        for finding in validated.research {
            if let url = finding.sourceURL {
                XCTAssertEqual(url.scheme, "https")
            } else {
                XCTAssertTrue(finding.unverified, "A claim with no usable source cannot be presented as verified")
            }
        }
        XCTAssertTrue(validated.repairedIssues.contains(.insecureSourceURL("http://insecure.example.com/a")))
        XCTAssertTrue(validated.repairedIssues.contains(.malformedSourceURL("not a url")))
        XCTAssertTrue(validated.repairedIssues.contains(.malformedTimestamp("nonsense")))
    }

    func testAClaimWithNoRetrievalDateIsTreatedAsStale() throws {
        let validated = try Fixture.validated("messy_repairable")
        XCTAssertTrue(validated.research.allSatisfy { $0.isStale() })
    }

    func testAnUnsupportedSchemaVersionIsRejectedOutright() {
        let response = AIDecisionResponse(
            schemaVersion: 99,
            decisionStatus: "ready",
            category: "other",
            complexity: "simple",
            understanding: .init(restatement: "x")
        )
        XCTAssertThrowsError(try AIResponseValidator.validate(response))
    }

    func testAnEmptyRestatementIsRejected() {
        let response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "other",
            complexity: "simple",
            understanding: .init(restatement: "   ")
        )
        XCTAssertThrowsError(try AIResponseValidator.validate(response))
    }

    func testReadyWithNoOptionsIsRejected() {
        let response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "other",
            complexity: "simple",
            understanding: .init(restatement: "Choosing something")
        )
        XCTAssertThrowsError(try AIResponseValidator.validate(response)) { error in
            guard case AIValidationError.unrepairable(let issues) = error else { return XCTFail() }
            XCTAssertTrue(issues.contains(.noOptions))
        }
    }

    func testAQuestionResponseWithoutOptionsIsAllowed() throws {
        // Early in a decision there may be no options yet — that is not an error.
        let validated = try Fixture.validated("needs_question")
        XCTAssertEqual(validated.status, .needsOneQuestion)
        XCTAssertEqual(validated.questions.count, 3)
    }

    func testAnEliminatedOptionIsNeverRecommended() throws {
        let response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "purchase",
            complexity: "simple",
            understanding: .init(restatement: "Choosing a bike"),
            criteria: [.init(id: "price", name: "Price", weight: 1)],
            options: [
                .init(id: "a", name: "A", scores: ["price": 0.9], failedConstraints: ["Over budget"]),
                .init(id: "b", name: "B", scores: ["price": 0.5])
            ],
            recommendation: .init(optionId: "a", headline: "A", reasons: [.init(title: "Cheap", detail: "x")])
        )
        let validated = try AIResponseValidator.validate(response)
        XCTAssertNil(validated.recommendedOptionID)
        XCTAssertTrue(validated.repairedIssues.contains(.recommendationForEliminatedOption("a")))
    }

    func testEveryOptionEliminatedIsFatal() {
        let response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "purchase",
            complexity: "simple",
            understanding: .init(restatement: "Choosing a bike"),
            criteria: [.init(id: "price", name: "Price", weight: 1)],
            options: [.init(id: "a", name: "A", scores: ["price": 0.9], failedConstraints: ["Over budget"])]
        )
        XCTAssertThrowsError(try AIResponseValidator.validate(response))
    }

    func testHostileTextIsTruncated() throws {
        let long = String(repeating: "a", count: 50_000)
        let response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "other",
            complexity: "simple",
            understanding: .init(restatement: long),
            criteria: [.init(id: "c", name: long, weight: 1)],
            options: [.init(id: "o", name: long, summary: long, scores: ["c": 0.5])],
            recommendation: .init(optionId: "o", headline: long, reasons: [.init(title: long, detail: long)])
        )
        let validated = try AIResponseValidator.validate(response)
        XCTAssertLessThanOrEqual(validated.understanding.restatement.count, AIResponseValidator.maximumTextLength + 1)
        XCTAssertLessThanOrEqual(validated.options[0].name.count, 121)
        XCTAssertLessThanOrEqual(validated.headline.count, 201)
    }

    func testNonFiniteNumbersAreRejectedNotPropagated() throws {
        var response = AIDecisionResponse(
            decisionStatus: "ready",
            category: "other",
            complexity: "simple",
            understanding: .init(restatement: "x"),
            criteria: [.init(id: "c", name: "C", weight: .nan)],
            options: [.init(id: "o", name: "O", scores: ["c": .infinity])],
            recommendation: .init(optionId: "o", headline: "O", reasons: [.init(title: "t", detail: "d")])
        )
        response.schemaVersion = 1
        let validated = try AIResponseValidator.validate(response)
        XCTAssertTrue(validated.criteria.allSatisfy { $0.weight.isFinite })
        XCTAssertTrue(validated.options.allSatisfy { $0.scores.values.allSatisfy(\.isFinite) })
    }

    func testMissingOptionalArraysDecodeAsEmpty() throws {
        let data = Data("""
        {"schemaVersion":1,"decisionStatus":"ready","category":"other","complexity":"simple",
         "understanding":{"restatement":"Something"}}
        """.utf8)
        let response = try JSONDecoder().decode(AIDecisionResponse.self, from: data)
        XCTAssertTrue(response.criteria.isEmpty)
        XCTAssertTrue(response.options.isEmpty)
        XCTAssertTrue(response.understanding.knownContext.isEmpty)
    }

    func testTheContractRoundTrips() throws {
        let original = try Fixture.response("valid_ready")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIDecisionResponse.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }
}
