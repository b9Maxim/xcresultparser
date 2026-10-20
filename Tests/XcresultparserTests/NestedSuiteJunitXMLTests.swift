import Foundation
@testable import XcresultparserLib
import Testing

// Swift Testing suites nest (`@Suite struct Outer { @Suite struct Inner {} }`), so
// `xcresulttool ... tests` returns Test Suite nodes inside Test Suite nodes. Every
// test of every nested suite must reach the JUnit XML as its own `<testcase>`.
@MainActor
struct NestedSuiteJunitXMLTests {
    private let summaryJSON = """
    {
      "title": "Test - Demo",
      "environmentDescription": "Demo",
      "topInsights": [],
      "result": "Passed",
      "totalTestCount": 4,
      "passedTests": 4,
      "failedTests": 0,
      "skippedTests": 0,
      "expectedFailures": 0,
      "statistics": [],
      "devicesAndConfigurations": [],
      "testFailures": [],
      "startTime": 100.0,
      "finishTime": 120.0
    }
    """

    // Outer holds one test and Inner; Inner holds one test and Deeper; Deeper holds two.
    private let testsJSON = """
    {
      "testPlanConfigurations": [
        {
          "configurationId": "1",
          "configurationName": "Default"
        }
      ],
      "devices": [],
      "testNodes": [
        {
          "name": "Test Plan",
          "nodeType": "Test Plan",
          "children": [
            {
              "name": "Default",
              "nodeType": "Test Plan Configuration",
              "children": [
                {
                  "name": "DemoTests.xctest",
                  "nodeType": "Unit test bundle",
                  "children": [
                    {
                      "name": "Outer",
                      "nodeType": "Test Suite",
                      "nodeIdentifier": "Outer",
                      "children": [
                        {
                          "name": "outerTest()",
                          "nodeType": "Test Case",
                          "nodeIdentifier": "Outer/outerTest()",
                          "result": "Passed",
                          "durationInSeconds": 0.1
                        },
                        {
                          "name": "Inner",
                          "nodeType": "Test Suite",
                          "nodeIdentifier": "Outer/Inner",
                          "children": [
                            {
                              "name": "innerTest()",
                              "nodeType": "Test Case",
                              "nodeIdentifier": "Outer/Inner/innerTest()",
                              "result": "Passed",
                              "durationInSeconds": 0.1
                            },
                            {
                              "name": "Deeper",
                              "nodeType": "Test Suite",
                              "nodeIdentifier": "Outer/Inner/Deeper",
                              "children": [
                                {
                                  "name": "deeperTestA()",
                                  "nodeType": "Test Case",
                                  "nodeIdentifier": "Outer/Inner/Deeper/deeperTestA()",
                                  "result": "Passed",
                                  "durationInSeconds": 0.1
                                },
                                {
                                  "name": "deeperTestB()",
                                  "nodeType": "Test Case",
                                  "nodeIdentifier": "Outer/Inner/Deeper/deeperTestB()",
                                  "result": "Passed",
                                  "durationInSeconds": 0.1
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
    """

    private func makeProvider() throws -> XCResultToolJunitXMLDataProvider {
        let shell = NestedLookupShell(
            responses: [
                "xcresulttool get test-results summary --path /tmp/test.xcresult": Data(summaryJSON.utf8),
                "xcresulttool get test-results tests --path /tmp/test.xcresult": Data(testsJSON.utf8)
            ]
        )
        return try XCResultToolJunitXMLDataProvider(
            url: URL(fileURLWithPath: "/tmp/test.xcresult"),
            client: XCResultToolClient(shell: shell)
        )
    }

    private func testcases(in xml: String, element: String) throws -> [XMLElement] {
        let document = try XMLDocument(xmlString: xml)
        return try document.nodes(forXPath: "//\(element)").compactMap { $0 as? XMLElement }
    }

    @Test
    func junitXMLListsTestsOfNestedSuites() throws {
        let xml = JunitXML(dataProvider: try makeProvider()).xmlString
        let cases = try testcases(in: xml, element: "testcase")

        #expect(cases.compactMap { $0.attribute(forName: "name")?.stringValue } == [
            "outerTest()", "innerTest()", "deeperTestA()", "deeperTestB()"
        ])
        #expect(cases.compactMap { $0.attribute(forName: "classname")?.stringValue } == [
            "Outer", "Outer.Inner", "Outer.Inner.Deeper", "Outer.Inner.Deeper"
        ])
    }

    @Test
    func junitXMLTestsuiteCountMatchesItsTestcases() throws {
        let xml = JunitXML(dataProvider: try makeProvider()).xmlString
        let suite = try #require(try testcases(in: xml, element: "testsuite").first)

        #expect(suite.attribute(forName: "tests")?.stringValue == "4")
        #expect(suite.elements(forName: "testcase").count == 4)
    }

    @Test
    func sonarXMLListsTestsOfNestedSuites() throws {
        let xml = JunitXML(dataProvider: try makeProvider(), format: .sonar).xmlString
        let cases = try testcases(in: xml, element: "testCase")

        #expect(cases.count == 4)
    }
}

private final class NestedLookupShell: Commandline {
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
