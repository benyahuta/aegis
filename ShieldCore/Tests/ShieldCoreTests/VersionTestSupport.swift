import Foundation
import os
import XCTest
@testable import ShieldCore

/// Fixture loading and fakes for the Version tests (VersionEvaluatorTests, FeedDecodeTests, FeedStoreTests).
enum VersionFixtures {
    /// When the 2026-10-22 fixtures were fetched (Fri, 23 Oct 2026 01:23:23 GMT).
    static let fetchedAt = utc("2026-10-23T01:23:23Z")
    /// "Now" for tests that use the captured feeds as fresh.
    static let now = utc("2026-10-23T01:30:00Z")

    static let iosToday = "sofa_ios_v2_2026-10-22"
    static let macToday = "sofa_macos_v2_2026-10-22"
    static let iosRollback = "rollback_ios_v2"
    static let macRollback = "rollback_macos_v2"
    static let iosStale = "stale_ios_v2_2026-09-21"
    static let macStale = "stale_macos_v2_2026-09-21"
    static let iosRaise = "raise_ios_v2_2026-10-29"

    static func utc(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else { fatalError("bad test date \(string)") }
        return date
    }

    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static func feed(_ name: String) throws -> SOFAFeed {
        try XCTUnwrap(SOFAFeed.decode(try data(name)), "fixture \(name) did not decode")
    }

    static func state(_ name: String, fetchedAt: Date = fetchedAt) throws -> FeedState {
        FeedState(feed: try feed(name), fetchedAt: fetchedAt, origin: .cache)
    }

    static func json(_ string: String) -> Data { Data(string.utf8) }

    /// A fresh temporary directory for a FeedStore cache.
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A scripted FeedTransport. Each fetch pops the next response; requests are recorded.
final class FakeFeedTransport: FeedTransport, Sendable {
    enum Reply: Sendable {
        case ok(Data, etag: String?)
        case status(Int, Data = Data())
        case failure
    }

    private struct State {
        var replies: [Reply] = []
        var requests: [URLRequest] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ replies: [Reply] = []) {
        state.withLock { $0.replies = replies }
    }

    func enqueue(_ reply: Reply) {
        state.withLock { $0.replies.append(reply) }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var requestCount: Int { state.withLock { $0.requests.count } }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        switch reply {
        case .ok(let data, let etag)?:
            var headers = ["Content-Type": "application/json"]
            if let etag { headers["ETag"] = etag }
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/2", headerFields: headers)!)
        case .status(let code, let data)?:
            return (data, HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/2", headerFields: [:])!)
        case .failure?, nil:
            throw URLError(.timedOut)
        }
    }
}
