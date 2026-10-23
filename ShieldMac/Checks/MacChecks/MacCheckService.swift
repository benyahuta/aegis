// The Mac app's entry point for the §6.2 measured checks.
//
// - Real run: `MacCheckSuite` with `ProcessRunner`, `LoopbackProber` and `MacSystemReader`.
// - `-FSDemoState <name>` (§13.2): fixed `MacDemoState` outcomes; no tool, file or port is touched.
//   An unrecognized name gives "all unknown" (never a fake green).
// - Version: `FeedMacVersionAssessor` (FeedStore + VersionEvaluator, §5.2). No feed, a stale feed
//   or a failed fetch never gives `os_patched` / `xprotect_current` a pass (H7). With `-FSNoCloud`
//   the feed is never fetched (cache + bundled snapshot only), so nothing touches the network.
// - Ben's "MDM is expected" mark is read on every run, so flipping it takes effect right away.
// Never changes a setting (H3); never calls SMAppService; needs no CloudKit.

import Foundation
import ShieldCore

struct MacCheckService: Sendable {
    /// Ben's local "this Mac's MDM is expected" mark (§6.2, his own Mac only). Local, never synced.
    static let mdmExpectedDefaultsKey = "FSMDMExpectedByOwner"

    private let options: LaunchOptions
    private let clock: Clock
    private let version: any MacVersionAssessing
    private let mdmExpected: @Sendable () -> Bool

    /// Ben's local mark, from UserDefaults (his own Mac only).
    static func mdmExpectedDefault() -> Bool {
        UserDefaults.standard.bool(forKey: mdmExpectedDefaultsKey)
    }

    /// Uses the app's shared macOS `FeedStore` for the version checks.
    init(
        options: LaunchOptions,
        clock: Clock = .system,
        feedStore: FeedStore,
        mdmExpected: @escaping @Sendable () -> Bool = MacCheckService.mdmExpectedDefault
    ) {
        self.init(options: options, clock: clock,
                  version: FeedMacVersionAssessor(store: feedStore, refreshFeed: !options.noCloud),
                  mdmExpected: mdmExpected)
    }

    init(
        options: LaunchOptions,
        clock: Clock = .system,
        version: any MacVersionAssessing,
        mdmExpected: @escaping @Sendable () -> Bool = MacCheckService.mdmExpectedDefault
    ) {
        self.options = options
        self.clock = clock
        self.version = version
        self.mdmExpected = mdmExpected
    }

    /// The IDs `run()` returns, in order.
    var checkIDs: [CheckID] { MacCheckSuite.p0Checks }

    /// Runs every P0 Mac check. Never throws; anything that can't be read is `.unknown`.
    func run() async -> [MacCheckOutcome] {
        if let name = options.demoState {
            let state = MacDemoState(name: name) ?? .allUnknown
            Log.checks.info("checks demo=\(state.rawValue, privacy: .public)")
            return state.outcomes
        }
        let suite = MacCheckSuite(
            tools: ProcessRunner(),
            probes: LoopbackProber(),
            system: MacSystemReader(),
            version: version,
            clock: clock,
            mdmExpectedByOwner: mdmExpected()
        )
        return await suite.run()
    }

    /// Runs the checks and returns the synced form (§8.2 fields only, `source = .measured`).
    func results(deviceID: UUID, catalogVersion: Int) async -> [CheckResult] {
        let outcomes = await run()
        return MacCheckSuite.results(outcomes, deviceID: deviceID, checkedOn: clock.today(), catalogVersion: catalogVersion)
    }
}
