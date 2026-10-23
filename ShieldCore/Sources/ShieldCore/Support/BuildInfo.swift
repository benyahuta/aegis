// Build facts for About, `app_build_fresh` (SPEC §6.1) and Ben's Feed & release health (§10.3).
//
// The build date is the day the app binary was produced. Order of preference:
//   1. Info.plist `FSBuildDate` ("YYYY-MM-DD", UTC), stamped on every build by the app targets'
//      "Stamp FSBuildDate" run-script phase (local clock, no network);
//   2. the modification date of the main executable (IPA and Developer ID archives keep it).
// When neither can be read the date is nil and `app_build_fresh` is `unknown` (H7).

import Foundation

public struct BuildInfo: Sendable, Hashable {
    /// `app_build_fresh` fails at this age (family banner, §6.1).
    public static let bannerAgeDays = 60
    /// Ben's second warning on Feed & release health (§10.3).
    public static let urgentAgeDays = 75

    public static let buildDateInfoKey = "FSBuildDate"

    public var version: String
    public var build: Int
    public var buildDay: DateDay?

    public init(version: String, build: Int, buildDay: DateDay?) {
        self.version = version
        self.build = build
        self.buildDay = buildDay
    }

    /// This app.
    public static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = Int((info["CFBundleVersion"] as? String) ?? "") ?? 0
        return BuildInfo(version: version, build: build, buildDay: resolveBuildDay(info: info, executable: Bundle.main.executableURL))
    }

    /// Whole days since the build, or nil when the build date is unknown.
    public func ageDays(today: DateDay) -> Int? {
        buildDay.map { max(0, today.days(since: $0)) }
    }

    /// `app_build_fresh` (§6.1): ≥ 60 days → fail; unknown build date → unknown; else pass.
    public func freshStatus(today: DateDay) -> Status {
        guard let age = ageDays(today: today) else { return .unknown }
        return age >= BuildInfo.bannerAgeDays ? .fail : .pass
    }

    /// The measured result for `app_build_fresh`.
    public func measuredResult(today: DateDay) -> MeasuredResult {
        MeasuredResult(checkID: .appBuildFresh, status: freshStatus(today: today), checkedOn: today)
    }

    static func resolveBuildDay(info: [String: Any], executable: URL?) -> DateDay? {
        if let stamped = info[buildDateInfoKey] as? String, let day = DateDay(iso8601: stamped) {
            return day
        }
        guard let executable,
              let values = try? executable.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate
        else { return nil }
        return DateDay(date)
    }
}
