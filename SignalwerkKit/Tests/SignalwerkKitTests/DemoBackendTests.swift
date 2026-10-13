import XCTest
@testable import SignalwerkKit

final class DemoBackendTests: XCTestCase {
    func testDemoQueueDecisions() async throws {
        let demo = DemoBackend()
        let open = try await demo.queue(filter: .open)
        XCTAssertEqual(open.items.count, 4)
        XCTAssertEqual(open.pending.donations, 3)
        XCTAssertEqual(open.pending.subBombs, 1)
        let first = try XCTUnwrap(open.items.first)
        _ = try await demo.decide(first, action: .accept)
        let after = try await demo.queue(filter: .open)
        XCTAssertEqual(after.items.count, 3)
        _ = try await demo.decide(first, action: .replay)

        let all = try await demo.queue(filter: .all)
        let blocked = try XCTUnwrap(all.items.first(where: \.isBlocked))
        do {
            _ = try await demo.decide(blocked, action: .accept)
            XCTFail("blockiert bleibt blockiert")
        } catch {
            XCTAssertEqual((error as? SignalwerkError)?.errorDescription, "Blockierte Spenden können nicht geändert werden.")
        }
    }

    func testDemoOverviewIsLive() async throws {
        let overview = try await DemoBackend().overview()
        XCTAssertEqual(overview.stream?.live, true)
        XCTAssertEqual(overview.stream?.series.points.count, 120)
        XCTAssertGreaterThan(overview.stream?.viewers ?? 0, 5000)
        XCTAssertEqual(overview.pending.total, 4)
    }

    func testDemoEventsStartWithReady() async throws {
        let demo = DemoBackend()
        var iterator = demo.events().makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.name, "ready")
    }

    func testDemoSpeechValidation() async {
        do {
            _ = try await DemoBackend().speak(text: "  ", voice: "default", speed: nil)
            XCTFail("leer geht nicht")
        } catch {
            XCTAssertEqual((error as? SignalwerkError)?.errorDescription, "Kein Text.")
        }
    }
}
