import Foundation
@testable import XcresultparserLib
import Testing

// Test shapes Xcode 26+ writes that a JUnit report must keep: a top-level `@Test`
// function, a disabled test without a duration, and a parameterized test whose
// failure the summary names without its arguments. Failure messages carry their
// location in `sourceLocation`, and retries repeat them once per repetition.
@MainActor
struct TestShapesJunitXMLTests {
    private let summaryJSON = """
    {
      "title": "Test - Demo",
      "environmentDescription": "Demo",
      "topInsights": [],
      "result": "Failed",
      "totalTestCount": 3,
      "passedTests": 1,
      "failedTests": 1,
      "skippedTests": 1,
      "expectedFailures": 0,
      "statistics": [],
      "devicesAndConfigurations": [],
      "testFailures": [
        {
          "failureText": "Expectation failed: value != 2\\nvalue → 2: Deliberate",
          "targetName": "DemoTests",
          "testIdentifier": 1,
          "testIdentifierString": "Variants/fails(value:)",
          "testName": "fails(value:)"
        }
      ],
      "startTime": 100.0,
      "finishTime": 120.0
    }
    """

    private let failureMessage = """
    {
      "name": "Expectation failed: value != 2\\nvalue → 2: Deliberate",
      "nodeType": "Failure Message",
      "sourceLocation": { "filePath": "/agent/work/Tests/VariantTests.swift", "lineNumber": 29 }
    }
    """

    private var testsJSON: String {
        """
        {
          "testPlanConfigurations": [{ "configurationId": "1", "configurationName": "Default" }],
          "devices": [],
          "testNodes": [{
            "name": "Test Plan",
            "nodeType": "Test Plan",
            "children": [{
              "name": "Default",
              "nodeType": "Test Plan Configuration",
              "children": [{
                "name": "DemoTests.xctest",
                "nodeType": "Unit test bundle",
                "children": [
                  {
                    "name": "freeFunction()",
                    "nodeType": "Test Case",
                    "nodeIdentifier": "freeFunction()",
                    "result": "Passed",
                    "durationInSeconds": 0.1
                  },
                  {
                    "name": "Variants",
                    "nodeType": "Test Suite",
                    "nodeIdentifier": "Variants",
                    "children": [
                      {
                        "name": "disabled()",
                        "nodeType": "Test Case",
                        "nodeIdentifier": "Variants/disabled()",
                        "result": "Skipped",
                        "children": [{ "name": "Test skipped: Off", "nodeType": "Skip Message" }]
                      },
                      {
                        "name": "fails(value:)",
                        "nodeType": "Test Case",
                        "nodeIdentifier": "Variants/fails(value:)",
                        "result": "Failed",
                        "durationInSeconds": 0.2,
                        "children": [
                          { "name": "1", "nodeType": "Arguments", "result": "Passed", "durationInSeconds": 0.1 },
                          {
                            "name": "2",
                            "nodeType": "Arguments",
                            "result": "Failed",
                            "durationInSeconds": 0.1,
                            "children": [
                              { "name": "First Run", "nodeType": "Repetition", "result": "Failed",
                                "children": [\(failureMessage)] },
                              { "name": "Retry 1", "nodeType": "Repetition", "result": "Failed",
                                "children": [\(failureMessage)] }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              }]
            }]
          }]
        }
        """
    }

    private func xmlDocument(format: TestReportFormat = .junit) throws -> XMLDocument {
        let shell = ShapesLookupShell(
            responses: [
                "xcresulttool get test-results summary --path /tmp/test.xcresult": Data(summaryJSON.utf8),
                "xcresulttool get test-results tests --path /tmp/test.xcresult": Data(testsJSON.utf8)
            ]
        )
        let provider = try XCResultToolJunitXMLDataProvider(
            url: URL(fileURLWithPath: "/tmp/test.xcresult"),
            client: XCResultToolClient(shell: shell)
        )
        return try XMLDocument(xmlString: JunitXML(dataProvider: provider, format: format).xmlString)
    }

    private func testcase(named name: String, in document: XMLDocument) throws -> XMLElement {
        let nodes = try document.nodes(forXPath: "//testcase[@name='\(name)']")
        return try #require(nodes.first as? XMLElement)
    }

    @Test
    func topLevelTestFunctionIsListedWithItsModuleAsClassname() throws {
        let freeFunction = try testcase(named: "freeFunction()", in: try xmlDocument())

        #expect(freeFunction.attribute(forName: "classname")?.stringValue == "DemoTests")
    }

    @Test
    func sonarListsTopLevelTestFunction() throws {
        let names = try xmlDocument(format: .sonar).nodes(forXPath: "//testCase/@name").compactMap(\.stringValue)

        #expect(names.contains("freeFunction()"))
    }

    @Test
    func testWithoutDurationKeepsItsClassname() throws {
        let disabled = try testcase(named: "disabled()", in: try xmlDocument())

        #expect(disabled.attribute(forName: "classname")?.stringValue == "Variants")
        #expect(disabled.attribute(forName: "time") == nil)
        #expect(disabled.elements(forName: "skipped").count == 1)
    }

    @Test
    func failingArgumentCarriesItsMessageAndLocationOnce() throws {
        let failing = try testcase(named: "fails(value: 2)", in: try xmlDocument())
        let failures = failing.elements(forName: "failure")

        #expect(failures.count == 1)
        #expect(failures.first?.attribute(forName: "message")?.stringValue == "Expectation failed: value != 2")
        #expect(failures.first?.stringValue == "Expectation failed: value != 2\nvalue → 2: Deliberate (VariantTests.swift:29)")
    }

    @Test
    func passingArgumentHasNoFailure() throws {
        let passing = try testcase(named: "fails(value: 1)", in: try xmlDocument())

        #expect(passing.elements(forName: "failure").isEmpty)
    }

    @Test
    func rootCountsMatchTheTestcases() throws {
        let root = try #require(try xmlDocument().rootElement())

        #expect(root.attribute(forName: "tests")?.stringValue == "4")
        #expect(root.attribute(forName: "failures")?.stringValue == "1")
    }
}

private final class ShapesLookupShell: Commandline {
    let responses: [String: Data]

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func execute(program: String, with arguments: [String], at executionPath: URL?) throws -> Data {
        guard let response = responses[arguments.joined(separator: " ")] else {
            throw NSError(domain: "missing_response", code: 1)
        }
        return response
    }
}
