// SHARED CONTRACT (scaffold). Every builder depends on this file.
// Injectable time source (SPEC §3 Support/Clock.swift). Never call `Date()` directly in
// logic that tests need to control (pacing, staleness, 90-day re-ask, feed age); take a
// `Clock` instead and default it to `.system`.
//
// Note: this type shadows the standard library's `Clock` protocol for code that imports
// ShieldCore. Use `Swift.Clock` / `ContinuousClock` explicitly if you need the stdlib one.

import Foundation
import os

/// A source of "now". A value type wrapping a closure, so it is trivially `Sendable`.
public struct Clock: Sendable {
    private let nowProvider: @Sendable () -> Date

    public init(_ now: @escaping @Sendable () -> Date) {
        self.nowProvider = now
    }

    /// The current instant.
    public func now() -> Date { nowProvider() }

    /// The current UTC day.
    public func today() -> DateDay { DateDay(nowProvider()) }

    /// The real wall clock.
    public static let system = Clock { Date() }

    /// A clock frozen at `date`.
    public static func fixed(_ date: Date) -> Clock {
        Clock { date }
    }
}

/// A clock tests can move forward. Thread-safe.
public final class TestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    public init(_ start: Date) {
        self.state = OSAllocatedUnfairLock(initialState: start)
    }

    /// Starts at 00:00 UTC on `day`.
    public convenience init(day: DateDay) {
        self.init(day.date)
    }

    public var now: Date { state.withLock { $0 } }

    public func set(_ date: Date) { state.withLock { $0 = date } }

    public func advance(seconds: TimeInterval) { state.withLock { $0 = $0.addingTimeInterval(seconds) } }

    public func advance(days: Int) { advance(seconds: TimeInterval(days) * 86_400) }

    /// A `Clock` that reads this test clock.
    public var clock: Clock {
        Clock { [state] in state.withLock { $0 } }
    }
}
