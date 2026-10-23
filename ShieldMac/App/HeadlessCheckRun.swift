// `-FSRunChecksAndPrint`: the Mac smoke test (SPEC §13.3) without any UI.
//
// Runs `MacCheckService` once (the same suite the app uses), prints one line per check and the
// menu-bar word, then exits 0. With `-FSNoCloud` the version feed is not fetched (cache + bundled
// snapshot). It never builds the app model, so CloudKit, the Keychain, notifications and the login
// item are never touched. A run that takes longer than `deadline` prints "TIMEOUT" and exits 2:
// a hang means a tool blocked (or a dialog appeared), which is a bug.

import Foundation
import ShieldCore

enum HeadlessCheckRun {
    static let deadline: TimeInterval = 60

    static func start(options: LaunchOptions) {
        let clock = Clock.system
        let started = Date()
        let feed = FeedStore(platform: .mac, clock: clock)
        let service = MacCheckService(options: LaunchOptions(noCloud: options.noCloud), clock: clock, feedStore: feed)
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) {
            print("TIMEOUT after \(Int(deadline)) s")
            exit(2)
        }
        Task {
            let outcomes = await service.run()
            let catalog = CheckCatalog.shared
            let today = clock.today()
            let engine = StatusEngine(catalog: catalog, platform: .mac, osMajor: Platform.currentOSMajor, clock: clock)
            let snapshot = engine.evaluate(measured: outcomes.map { $0.measuredResult(today: today) },
                                           selfReports: SelfReportState())
            let lines = MacCheckReport.lines(outcomes, catalog: catalog, menuBarWord: snapshot.home.menuBarWord,
                                             elapsed: Date().timeIntervalSince(started))
            print(lines.joined(separator: "\n"))
            exit(0)
        }
    }
}
