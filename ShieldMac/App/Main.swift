// Process entry point for the Mac app.
//
// - `-FSRunChecksAndPrint` (hidden, SPEC §13.3 smoke test): runs the §6.2 checks once with no
//   window, no menu-bar item, no CloudKit and no login item, prints `check_id -> status` and exits.
// - `-FSSnapshot <dir>` (DEBUG builds only): renders the demo screens to PNG files and exits.
// - Otherwise: the SwiftUI app.

import Foundation
import ShieldCore

@main
enum FamilyShieldMain {
    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(MacCheckReport.flag) {
            HeadlessCheckRun.start(options: .current)
            dispatchMain()
        }
        #if DEBUG
        if let directory = SnapshotRunner.outputDirectory(arguments) {
            SnapshotRunner.run(outputDirectory: directory, arguments: arguments)
        }
        #endif
        ShieldMacApp.main()
    }
}
