import Foundation
import XCTest
@testable import ShieldCore

/// SPEC §13.1 FeedDecodeTests: captured SOFA v2 fixtures from 2026-10-22 decode; unknown keys are
/// ignored; truncated JSON → nil. Plus the other defensive-decoding rules from §5.2.
final class FeedDecodeTests: XCTestCase {
    // MARK: Captured fixtures

    func testCapturedIOSFeedDecodes() throws {
        let feed = try VersionFixtures.feed(VersionFixtures.iosToday)
        XCTAssertEqual(feed.majors, [27, 26, 18])
        XCTAssertEqual(feed.osVersion(major: 27)?.highestVersion, OSVersion(27, 0, 1))
        XCTAssertEqual(feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1))
        XCTAssertEqual(feed.osVersion(major: 18)?.highestVersion, OSVersion(18, 7, 10))
        XCTAssertEqual(feed.osVersion(major: 18)?.latest?.productVersion, OSVersion(18, 7, 8),
                       "v2 Latest is the latest universal release, not the newest")
        XCTAssertNotNil(feed.lastCheck)
        XCTAssertNotNil(feed.updateHash)
        XCTAssertGreaterThanOrEqual(feed.devices.count, 100)
        XCTAssertNotNil(feed.devices["iPhone11,2"])
        XCTAssertNil(feed.devices["iPhone10,3"], "iPhone 8/X are out of every list")
        XCTAssertTrue(feed.models.isEmpty)
        XCTAssertNil(feed.xProtect)

        let top26 = try XCTUnwrap(feed.osVersion(major: 26)?.securityReleases.first)
        XCTAssertEqual(top26.productVersion, OSVersion(26, 7, 1))
        XCTAssertEqual(top26.build, "23H6030")
        XCTAssertEqual(top26.deviceScope, .universal)
        XCTAssertTrue(top26.activelyExploitedCVEs.contains("CVE-2026-86950"))
        XCTAssertNotNil(top26.releaseDate)

        let top18 = try XCTUnwrap(feed.osVersion(major: 18)?.securityReleases.first)
        XCTAssertEqual(top18.productVersion, OSVersion(18, 7, 10))
        XCTAssertEqual(top18.deviceScope, .deviceSpecific)
        XCTAssertTrue(BundledMinimums.iPhoneXSFamily.isSubset(of: Set(top18.supportedDevices)))

        let top27 = try XCTUnwrap(feed.osVersion(major: 27)?.securityReleases.first)
        XCTAssertEqual(top27.cves.count, 0, "27.0.1 lists 0 CVEs")
    }

    func testCapturedMacFeedDecodes() throws {
        let feed = try VersionFixtures.feed(VersionFixtures.macToday)
        XCTAssertEqual(feed.majors, [27, 26, 15, 14, 13, 12])
        XCTAssertEqual(feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1))
        XCTAssertEqual(feed.osVersion(major: 15)?.highestVersion, OSVersion(15, 8, 1))
        XCTAssertEqual(feed.osVersion(major: 14)?.highestVersion, OSVersion(14, 8, 9))
        XCTAssertEqual(feed.models["Mac17,2"]?.osVersions, [27, 26])
        XCTAssertEqual(feed.devices["J704AP"]?.deviceID, "Mac17,2")
        XCTAssertGreaterThanOrEqual(feed.models.count, 90)
        XCTAssertEqual(feed.xProtect?.xprotectVersion, "170")
        XCTAssertEqual(feed.xProtect?.pluginServiceVersion, "74")
        XCTAssertEqual(feed.xProtect?.plistConfigVersion, "5368")
        let tahoe = try XCTUnwrap(feed.osVersion(major: 26)?.securityReleases.first)
        XCTAssertEqual(tahoe.build, "25G241")
        XCTAssertTrue(tahoe.fixesActivelyExploited)
    }

    func testDerivedFixturesDecode() throws {
        for name in [VersionFixtures.iosRollback, VersionFixtures.macRollback, VersionFixtures.iosStale,
                     VersionFixtures.macStale, VersionFixtures.iosRaise] {
            XCTAssertNotNil(SOFAFeed.decode(try VersionFixtures.data(name)), name)
        }
        XCTAssertEqual(try VersionFixtures.feed(VersionFixtures.iosStale).osVersion(major: 26)?.highestVersion, OSVersion(26, 7))
        XCTAssertEqual(try VersionFixtures.feed(VersionFixtures.iosRaise).osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 2))
    }

    func testBundledSnapshotsDecodeAndMatchTheCapture() throws {
        for (platform, fixture) in [(Platform.ios, VersionFixtures.iosToday), (.mac, VersionFixtures.macToday)] {
            let snapshot = try XCTUnwrap(FeedStore.bundledSnapshot(for: platform), "\(platform)")
            let captured = try VersionFixtures.feed(fixture)
            XCTAssertEqual(snapshot.fetchedAt, FeedStore.snapshotDate.date)
            XCTAssertEqual(snapshot.feed.majors, captured.majors)
            for major in captured.majors {
                XCTAssertEqual(snapshot.feed.osVersion(major: major)?.highestVersion,
                               captured.osVersion(major: major)?.highestVersion, "\(platform) \(major)")
                XCTAssertEqual(snapshot.feed.osVersion(major: major)?.deviceList,
                               captured.osVersion(major: major)?.deviceList, "\(platform) \(major)")
            }
            XCTAssertEqual(snapshot.feed.models, captured.models)
            XCTAssertEqual(snapshot.feed.xProtect, captured.xProtect)
            XCTAssertTrue(FeedStore.loweredMajors(new: captured, baseline: snapshot.feed, floors: [:],
                                                  bundled: .current, platform: platform).isEmpty)
        }
    }

    func testBundledMinimumsAgreeWithTheCapturedFeeds() throws {
        // The bundled table must never be above what Apple actually shipped (or nobody could pass).
        let ios = try VersionFixtures.feed(VersionFixtures.iosToday)
        let mac = try VersionFixtures.feed(VersionFixtures.macToday)
        for (platform, feed) in [(Platform.ios, ios), (.mac, mac)] {
            for major in BundledMinimums.current.majors(for: platform) {
                let highest = try XCTUnwrap(feed.osVersion(major: major)?.highestVersion)
                let table = try XCTUnwrap(BundledMinimums.current.highestMinimum(platform: platform, major: major))
                XCTAssertEqual(table, highest, "\(platform) \(major)")
            }
        }
    }

    // MARK: Defensive decoding

    func testUnknownKeysIgnored() throws {
        let data = VersionFixtures.json("""
        {"Brand":"new","OSVersions":[{"OSVersion":"Tahoe 26","Extra":{"a":[1,2]},
          "Latest":{"ProductVersion":"26.7.1","Whatever":null,"UpdateSummary":{"Stats":{"Exploited":0}}},
          "SecurityReleases":[{"ProductVersion":"26.7.1","Build":"25G241","Future":true,"CVEs":{},
            "SecurityInfo":"https://example.invalid","ActivelyExploitedCVEs":["CVE-2026-86950"]}]}],
         "InstallationApps":{"LatestUMA":{"URL":"https://example.invalid"}}}
        """)
        let feed = try XCTUnwrap(SOFAFeed.decode(data))
        XCTAssertEqual(feed.majors, [26])
        XCTAssertTrue(feed.osVersion(major: 26)?.securityReleases.first?.fixesActivelyExploited ?? false)
    }

    func testTruncatedJSONIsNil() throws {
        let data = try VersionFixtures.data(VersionFixtures.iosToday)
        for fraction in [0.0, 0.1, 0.5, 0.99] {
            let cut = data.prefix(Int(Double(data.count) * fraction))
            XCTAssertNil(SOFAFeed.decode(Data(cut)), "fraction \(fraction)")
        }
        // The capture ends in "}\n": dropping the newline alone is still valid JSON, dropping "}" is not.
        XCTAssertNotNil(SOFAFeed.decode(data.dropLast(1)))
        XCTAssertNil(SOFAFeed.decode(data.dropLast(2)))
    }

    func testStructuralFailuresAreNil() {
        let cases: [String: String] = [
            "not json": "<html>503</html>",
            "array top level": "[]",
            "no OSVersions": #"{"Devices":{}}"#,
            "OSVersions wrong type": #"{"OSVersions":{"26":{}}}"#,
            "empty OSVersions": #"{"OSVersions":[]}"#,
            "no releases": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[]}]}"#,
            "major without number": #"{"OSVersions":[{"OSVersion":"Tahoe","SecurityReleases":[{"ProductVersion":"26.1"}]}]}"#,
            "bad ProductVersion": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"latest"}]}]}"#,
            "ProductVersion number": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":26.1}]}]}"#,
            "release in wrong major": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"25.1"}]}]}"#,
            "CVEs string": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"26.1","CVEs":"many"}]}]}"#,
            "SupportedDevices string": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"26.1","SupportedDevices":"all"}]}]}"#,
            "exploited list string": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"26.1","ActivelyExploitedCVEs":"CVE-1"}]}]}"#,
            "Build number": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"26.1","Build":25}]}]}"#,
            "Models wrong type": #"{"OSVersions":[{"OSVersion":"26","SecurityReleases":[{"ProductVersion":"26.1"}]}],"Models":[]}"#,
        ]
        for (name, json) in cases {
            XCTAssertNil(SOFAFeed.decode(VersionFixtures.json(json)), name)
        }
    }

    func testLenientOptionalFields() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(VersionFixtures.json("""
        {"LastCheck":"2026-10-22T20:18:20.379737709+00:00","OSVersions":[{"OSVersion":26,
          "Latest":null,"SecurityReleases":[{"ProductVersion":"26.7.1","Build":"","SupportedDevices":null,
          "ActivelyExploitedCVEs":null,"CVEs":null,"DeviceScope":null,"ReleaseDate":"someday"}]}],
         "Models":{"Mac17,2":{"OSVersions":[27,"Tahoe 26"]}},"XProtectPayloads":{"com.apple.XProtectFramework.XProtect":171}}
        """)))
        XCTAssertEqual(feed.lastCheck, VersionFixtures.utc("2026-10-22T20:18:20Z"))
        let release = try XCTUnwrap(feed.osVersion(major: 26)?.securityReleases.first)
        XCTAssertNil(release.build)
        XCTAssertEqual(release.supportedDevices, [])
        XCTAssertEqual(release.cves, .none)
        XCTAssertEqual(release.deviceScope, .unspecified)
        XCTAssertNil(release.releaseDate)
        XCTAssertEqual(feed.models["Mac17,2"]?.osVersions, [27, 26])
        XCTAssertEqual(feed.xProtect?.xprotectVersion, "171")
    }

    func testOSVersionTrailingInteger() {
        XCTAssertEqual(SOFAOSVersion.trailingInteger("Tahoe 26"), 26)
        XCTAssertEqual(SOFAOSVersion.trailingInteger("Golden Gate 27"), 27)
        XCTAssertEqual(SOFAOSVersion.trailingInteger("18"), 18)
        XCTAssertNil(SOFAOSVersion.trailingInteger("Sequoia"))
        XCTAssertNil(SOFAOSVersion.trailingInteger(""))
    }
}

final class OSVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(OSVersion("26.7.1"), OSVersion(26, 7, 1))
        XCTAssertEqual(OSVersion("27"), OSVersion(27))
        XCTAssertEqual(OSVersion(" 15.8.1 (a)"), OSVersion(15, 8, 1))
        XCTAssertEqual(OSVersion("18.7.10")?.patch, 10)
        XCTAssertNil(OSVersion(""))
        XCTAssertNil(OSVersion("latest"))
        XCTAssertNil(OSVersion("26."))
        XCTAssertNil(OSVersion(".1"))
        XCTAssertNil(OSVersion("1234567890.1"))
        XCTAssertNil(OSVersion(components: []))
        XCTAssertNil(OSVersion(components: [26, -1]))
    }

    func testComparisonIsNumeric() {
        XCTAssertLessThan(OSVersion(18, 7, 8), OSVersion(18, 7, 10))
        XCTAssertLessThan(OSVersion(26, 5, 1), OSVersion(26, 7, 1))
        XCTAssertLessThan(OSVersion(26, 7, 1), OSVersion(27))
        XCTAssertEqual(OSVersion("26.7.0"), OSVersion("26.7"))
        XCTAssertEqual(Set([OSVersion("26.7.0"), OSVersion("26.7")]).count, 1)
        XCTAssertFalse(OSVersion(26, 7) < OSVersion(26, 7, 0))
    }

    func testDescriptionAndCodable() throws {
        XCTAssertEqual(OSVersion(26, 7, 1).description, "26.7.1")
        XCTAssertEqual(OSVersion(27).description, "27.0")
        XCTAssertEqual(OSVersion(OperatingSystemVersion(majorVersion: 14, minorVersion: 8, patchVersion: 9)), OSVersion(14, 8, 9))
        let data = try JSONEncoder().encode([OSVersion(18, 7, 10)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["18.7.10"]"#)
        XCTAssertEqual(try JSONDecoder().decode([OSVersion].self, from: data), [OSVersion(18, 7, 10)])
        XCTAssertGreaterThan(OSVersion.running.major, 0)
    }
}

final class DeviceIdentifierTests: XCTestCase {
    func noSysctl(_: String) -> String? { nil }

    func testIOSDeviceUsesMachine() {
        let id = DeviceIdentifier.resolve(platform: .ios, machine: "iPhone14,5", environment: [:], sysctl: noSysctl)
        XCTAssertEqual(id.modelIdentifier, "iPhone14,5")
        XCTAssertNil(id.boardID)
        XCTAssertEqual(id.feedIdentifiers, ["iPhone14,5"])
    }

    func testIOSSimulatorUsesEnvironment() {
        let id = DeviceIdentifier.resolve(platform: .ios, machine: "arm64",
                                          environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone18,1"], sysctl: noSysctl)
        XCTAssertEqual(id.modelIdentifier, "iPhone18,1")
    }

    func testIOSSimulatorWithoutEnvironmentIsUnknown() {
        let id = DeviceIdentifier.resolve(platform: .ios, machine: "arm64", environment: [:], sysctl: noSysctl)
        XCTAssertTrue(id.isUnknown)
        XCTAssertEqual(id.feedIdentifiers, [])
    }

    func testMacUsesSysctl() {
        let values = ["hw.model": "Mac17,2", "hw.target": "J704AP\0"]
        let id = DeviceIdentifier.resolve(platform: .mac, machine: "arm64", environment: [:], sysctl: { values[$0] })
        XCTAssertEqual(id.modelIdentifier, "Mac17,2")
        XCTAssertEqual(id.boardID, "J704AP")
        XCTAssertEqual(id.feedIdentifiers, ["J704AP", "Mac17,2"])
    }

    func testMacWithoutHWTarget() {
        let id = DeviceIdentifier.resolve(platform: .mac, machine: "x86_64", environment: [:],
                                          sysctl: { $0 == "hw.model" ? "MacBookAir8,1" : nil })
        XCTAssertEqual(id.modelIdentifier, "MacBookAir8,1")
        XCTAssertNil(id.boardID)
    }

    func testCleanRejectsJunk() {
        XCTAssertNil(DeviceIdentifier.clean(""))
        XCTAssertNil(DeviceIdentifier.clean("  \n"))
        XCTAssertNil(DeviceIdentifier.clean("iPhone14,5; rm -rf"))
        XCTAssertNil(DeviceIdentifier.clean(String(repeating: "a", count: 65)))
        XCTAssertEqual(DeviceIdentifier.clean(" iPhone14,5 "), "iPhone14,5")
    }

    func testRealHostReads() {
        XCTAssertNotNil(DeviceIdentifier.utsnameMachine())
        XCTAssertNil(DeviceIdentifier.sysctlString("hw.no_such_key_familyshield"))
        #if os(macOS)
        XCTAssertNotNil(DeviceIdentifier.sysctlString("hw.model"))
        XCTAssertNotNil(DeviceIdentifier.current.modelIdentifier)
        #endif
    }
}
