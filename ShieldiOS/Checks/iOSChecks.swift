// The iPhone's measured checks (SPEC §6.1). No permissions, no prompts:
// - os_patched / device_supported: FeedStore (SOFA iOS feed, cache, bundled snapshot; raise-only)
//   + VersionEvaluator (§5.2).
// - passcode_set / biometrics_enrolled: `LAContext.canEvaluatePolicy` (never shows UI).
// - app_build_fresh: the embedded build date (BuildInfo); ≥ 60 days → fail.
// H7: any error is `unknown`, never `pass`. Nothing here changes a setting (H3).

import Foundation
import LocalAuthentication
import ShieldCore
import ShieldUI

struct IOSChecks: Sendable {
    let feed: FeedStore
    let clock: Clock
    let build: BuildInfo

    /// Runs every P0 iPhone check.
    func measure() async -> [MeasuredResult] {
        let today = clock.today()
        // Throttled to one network attempt per 6 h; every failure keeps the cache (§5.2).
        _ = await feed.refresh()
        let state = await feed.currentFeed()
        let floors = await feed.minimumFloors()
        let evaluation = VersionEvaluator().evaluate(.current(feed: state, cachedMinimums: floors, clock: clock))
        await feed.raiseMinimumFloors(evaluation.minimumsToRemember)

        var results = evaluation.measuredResults(today: today)
        let (passcodeOK, passcodeError) = DeviceAuthCheck.evaluate(.deviceOwnerAuthentication)
        results.append(MeasuredResult(checkID: .passcodeSet,
                                      status: DeviceAuthCheck.passcodeStatus(canEvaluate: passcodeOK, errorCode: passcodeError),
                                      checkedOn: today))
        let (bioOK, bioError) = DeviceAuthCheck.evaluate(.deviceOwnerAuthenticationWithBiometrics)
        results.append(MeasuredResult(checkID: .biometricsEnrolled,
                                      status: DeviceAuthCheck.biometricsStatus(canEvaluate: bioOK, errorCode: bioError),
                                      checkedOn: today))
        results.append(build.measuredResult(today: today))
        Log.checks.info("ios.checks count=\(results.count, privacy: .public)")
        return results
    }

    func feedInfo() async -> FeedInfo? {
        FeedInfo(state: await feed.currentFeed(), now: clock.now())
    }
}
