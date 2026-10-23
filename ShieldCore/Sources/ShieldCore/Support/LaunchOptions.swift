// SHARED CONTRACT (scaffold). Every builder depends on this file.
// Launch arguments (SPEC §13.2):
//   -FSNoCloud            use InMemoryResultSink; never touch CloudKit or the network.
//   -FSDemoState <name>   inject a fixed demo state for screenshots / UI tests. Implies -FSNoCloud.

import Foundation

public struct LaunchOptions: Sendable, Equatable {
    public static let noCloudFlag = "-FSNoCloud"
    public static let demoStateFlag = "-FSDemoState"

    /// True when CloudKit must not be used (`-FSNoCloud`, or any `-FSDemoState`).
    public let noCloud: Bool
    /// The demo state name after `-FSDemoState`, if any.
    public let demoState: String?

    public init(noCloud: Bool = false, demoState: String? = nil) {
        self.demoState = demoState
        self.noCloud = noCloud || demoState != nil
    }

    /// Parses process arguments. `-FSNoCloud` may be bare or followed by YES/NO
    /// (UserDefaults argument-domain style).
    public init(arguments: [String]) {
        var noCloud = false
        var demoState: String?
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next = arguments.index(after: index) < arguments.endIndex ? arguments[arguments.index(after: index)] : nil
            if argument == LaunchOptions.noCloudFlag {
                switch next?.lowercased() {
                case "no", "false", "0":
                    noCloud = false
                    index = arguments.index(after: index)
                case "yes", "true", "1":
                    noCloud = true
                    index = arguments.index(after: index)
                default:
                    noCloud = true
                }
            } else if argument == LaunchOptions.demoStateFlag {
                if let name = next, !name.hasPrefix("-"), !name.isEmpty {
                    demoState = name
                    index = arguments.index(after: index)
                }
            }
            index = arguments.index(after: index)
        }
        self.init(noCloud: noCloud, demoState: demoState)
    }

    /// The options for this process.
    public static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
}
