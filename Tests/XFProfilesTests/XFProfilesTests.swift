// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

final class XFProfilesTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFProfiles.apiVersion, 1)
    }

    func testGlobMatch() {
        XCTAssertTrue(GlobMatch.matches(pattern: "*Seventy-Two*", "Rane Seventy-Two MIDI 1"))
        XCTAssertTrue(GlobMatch.matches(pattern: "*DJM-S9*", "PIONEER DJM-S9"))          // sin distinguir caso
        XCTAssertTrue(GlobMatch.matches(pattern: "abc", "abc"))
        XCTAssertTrue(GlobMatch.matches(pattern: "*", "cualquier cosa"))
        XCTAssertTrue(GlobMatch.matches(pattern: "a*c", "abbbbc"))
        XCTAssertFalse(GlobMatch.matches(pattern: "*DJM-S11*", "Rane Seventy-Two"))
        XCTAssertFalse(GlobMatch.matches(pattern: "abc", "abd"))
        XCTAssertFalse(GlobMatch.matches(pattern: "a*c", "ab"))
        XCTAssertTrue(GlobMatch.matches(pattern: "", ""))
        XCTAssertFalse(GlobMatch.matches(pattern: "", "x"))
    }
}
