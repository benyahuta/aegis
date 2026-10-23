import XCTest
@testable import ShieldCore

/// §6.1 `app_build_fresh` needs a real build date: both app targets stamp `FSBuildDate` into the
/// built Info.plist from the local clock (no network) on every build.
final class BuildDateStampTests: XCTestCase {
    static let appTargets = ["ShieldiOS", "ShieldMac"]

    private func project() throws -> String {
        let url = CatalogLintTests.repoRoot.appendingPathComponent("FamilyShield.xcodeproj/project.pbxproj")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("project.pbxproj not readable from this test host")
        }
        return text
    }

    /// The `buildPhases = ( ... );` list of one native target, by name.
    private func buildPhases(of target: String, in text: String) -> String? {
        guard let header = text.range(of: "/* \(target) */ = {\n\t\t\tisa = PBXNativeTarget;"),
              let start = text.range(of: "buildPhases = (", range: header.upperBound..<text.endIndex),
              let end = text.range(of: ");", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    func testBothAppsRunTheStampPhaseLast() throws {
        let text = try project()
        for target in Self.appTargets {
            let phases = try XCTUnwrap(buildPhases(of: target, in: text), target)
            let names = phases.components(separatedBy: "\n").compactMap { line -> String? in
                guard let open = line.range(of: "/* "), let close = line.range(of: " */") else { return nil }
                return String(line[open.upperBound..<close.lowerBound])
            }
            XCTAssertEqual(names.last, "Stamp FSBuildDate", "\(target): stamp after Resources, before signing")
        }
    }

    func testStampScriptWritesTheInfoPlistKeyFromTheLocalClock() throws {
        let text = try project()
        let scripts = text.components(separatedBy: "isa = PBXShellScriptBuildPhase;").dropFirst()
        XCTAssertEqual(scripts.count, Self.appTargets.count)
        for phase in scripts {
            let body = phase.components(separatedBy: "\n\t\t};").first ?? ""
            XCTAssertTrue(body.contains("Add :\(BuildInfo.buildDateInfoKey) string"), "writes FSBuildDate")
            XCTAssertTrue(body.contains("${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"), "into the built Info.plist")
            XCTAssertTrue(body.contains("/bin/date -u +%Y-%m-%d"), "YYYY-MM-DD, the format BuildInfo parses")
            XCTAssertTrue(body.contains("alwaysOutOfDate = 1;"), "runs on every build")
            for banned in ["curl", "http", "git ", "ssh"] {
                XCTAssertFalse(body.contains(banned), "no network or repo access: \(banned)")
            }
        }
    }

    func testStampedFormatResolvesAndWinsOverTheExecutableDate() {
        let stamped = BuildInfo.resolveBuildDay(info: [BuildInfo.buildDateInfoKey: "2026-10-23"],
                                                executable: Bundle.main.executableURL)
        XCTAssertEqual(stamped, DateDay(year: 2026, month: 10, day: 23))
        let info = BuildInfo(version: "1.0", build: 1, buildDay: stamped)
        XCTAssertEqual(info.freshStatus(today: DateDay(year: 2026, month: 12, day: 21)!), .pass, "day 59")
        XCTAssertEqual(info.freshStatus(today: DateDay(year: 2026, month: 12, day: 22)!), .fail, "day 60: banner")
    }
}
