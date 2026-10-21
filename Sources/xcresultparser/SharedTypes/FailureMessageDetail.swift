//
//  FailureMessageDetail.swift
//  xcresultparser
//

import Foundation

struct FailureMessageDetail {
    let message: String
    let documentLocation: String
}

extension FailureMessageDetail {
    init?(from raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        let file = String(parts[0])
        let line = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.allSatisfy(\.isNumber) else {
            return nil
        }
        let msg = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !file.isEmpty, !msg.isEmpty else {
            return nil
        }
        message = msg
        documentLocation = "\(file):\(line)"
    }

    /// Xcode 26+ keeps the location out of the message, in `sourceLocation`.
    init?(failureMessage node: XCTestNode) {
        if let parsed = FailureMessageDetail(from: node.name) {
            self = parsed
            return
        }
        guard let location = node.sourceLocation, !node.name.isEmpty else {
            return nil
        }
        message = node.name
        documentLocation = "\(URL(fileURLWithPath: location.filePath).lastPathComponent):\(location.lineNumber)"
    }
}
