// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XFNotation

enum AnalysisFixtures {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/XFAnalysisTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    static func primitives() throws -> PrimitiveSet {
        try PrimitiveSet(
            handPatternsJSON: try Data(contentsOf: repoRoot.appendingPathComponent("data/primitives/hand_patterns.json")),
            faderPatternsJSON: try Data(contentsOf: repoRoot.appendingPathComponent("data/primitives/fader_patterns.json"))
        )
    }
}
