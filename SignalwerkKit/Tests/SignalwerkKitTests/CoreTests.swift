import XCTest
@testable import SignalwerkKit

final class CoreTests: XCTestCase {
    func testDates() {
        XCTAssertNotNil(SignalwerkDate.parse("2026-10-13T11:01:05.106Z"))
        XCTAssertNotNil(SignalwerkDate.parse("2026-10-13T11:01:05Z"))
        XCTAssertNil(SignalwerkDate.parse("gestern"))
        XCTAssertNil(SignalwerkDate.parse(nil))
        let date = Date(timeIntervalSince1970: 1_791_890_000)
        XCTAssertEqual(SignalwerkDate.parse(SignalwerkDate.string(date))?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFormats() {
        XCTAssertEqual(SignalwerkFormat.count(12055), "12.055")
        XCTAssertEqual(SignalwerkFormat.count(7), "7")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(SignalwerkFormat.ago(now.addingTimeInterval(-10), now: now), "jetzt")
        XCTAssertEqual(SignalwerkFormat.ago(now.addingTimeInterval(-5 * 60), now: now), "vor 5 Min.")
        XCTAssertEqual(SignalwerkFormat.ago(now.addingTimeInterval(-3 * 3600), now: now), "vor 3 Std.")
        XCTAssertEqual(SignalwerkFormat.ago(now.addingTimeInterval(-86400 * 2), now: now), "vor 2 Tagen")
        XCTAssertEqual(SignalwerkFormat.timeout(600), "10 min")
        XCTAssertEqual(SignalwerkFormat.timeout(3600), "1 h")
        XCTAssertEqual(SignalwerkFormat.timeout(86400), "1 Tag")
        XCTAssertEqual(SignalwerkFormat.duration(from: now.addingTimeInterval(-188 * 60), to: now), "3:08 h")
        XCTAssertEqual(SignalwerkFormat.duration(from: now.addingTimeInterval(-42 * 60), to: now), "42 min")
    }

    func testServerAddress() {
        XCTAssertEqual(ServerAddress.normalize("dashboard.signalwerk.live")?.absoluteString, "https://dashboard.signalwerk.live")
        XCTAssertEqual(ServerAddress.normalize(" https://Dashboard.Signalwerk.live/login?x=1 ")?.absoluteString, "https://dashboard.signalwerk.live")
        XCTAssertEqual(ServerAddress.normalize("http://localhost:8080/")?.absoluteString, "http://localhost:8080")
        XCTAssertNil(ServerAddress.normalize(""))
        XCTAssertNil(ServerAddress.normalize("ftp://x.example"))
        XCTAssertNil(ServerAddress.normalize("zwei wörter"))
        XCTAssertEqual(ServerAddress.display(URL(string: "https://dashboard.signalwerk.live")!), "dashboard.signalwerk.live")
    }

    func testPKCEMatchesRFC7636() {
        // Beispiel aus RFC 7636, Anhang B.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let pkce = PKCE()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertLessThanOrEqual(pkce.verifier.count, 128)
        XCTAssertEqual(pkce.challenge.count, 43)
        XCTAssertNotEqual(PKCE().verifier, pkce.verifier)
    }

    func testWebConnect() throws {
        let server = URL(string: "https://dashboard.signalwerk.live")!
        let connect = try XCTUnwrap(WebConnect(server: server, deviceName: "iPad von Yusuf", platform: "ipados"))
        let components = try XCTUnwrap(URLComponents(url: connect.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/app-verbinden")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "challenge" })?.value, connect.pkce.challenge)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "device" })?.value, "iPad von Yusuf")
        XCTAssertGreaterThanOrEqual(connect.state.count, 16)

        let good = URL(string: "signalwerk://verbunden?code=abc.def&state=\(connect.state)")!
        XCTAssertEqual(connect.evaluate(good), .code("abc.def"))
        let cancelled = URL(string: "signalwerk://verbunden?error=abgebrochen&state=\(connect.state)")!
        XCTAssertEqual(connect.evaluate(cancelled), .cancelled)
        let foreign = URL(string: "signalwerk://verbunden?code=abc.def&state=fremd")!
        XCTAssertEqual(connect.evaluate(foreign), .invalid)
        let otherScheme = URL(string: "https://evil.example/?code=x&state=\(connect.state)")!
        XCTAssertEqual(connect.evaluate(otherScheme), .invalid)
    }

    func testSSEParser() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("event: ready"))
        XCTAssertEqual(parser.feed("data: {}"), ServerEvent(name: "ready", data: "{}"))
        XCTAssertNil(parser.feed(""))
        XCTAssertNil(parser.feed(": ping"))
        XCTAssertNil(parser.feed("event: refresh\r"))
        XCTAssertEqual(parser.feed("data: {\"source\":\"poll\"}"), ServerEvent(name: "refresh", data: "{\"source\":\"poll\"}"))
        // Ohne Namen: "message".
        XCTAssertEqual(parser.feed("data: x"), ServerEvent(name: "message", data: "x"))
    }

    func testBinaryPacing() {
        let spacing = SocketIOClient.binarySpacing
        let start = DispatchTime.now()
        // Erster Rahmen geht sofort, ohne Daten oder bei Rückstau nichts.
        XCTAssertEqual(BinaryPacing.next(now: start, last: nil, queued: 1, underway: 0), .send)
        XCTAssertEqual(BinaryPacing.next(now: start, last: nil, queued: 0, underway: 0), .hold)
        XCTAssertEqual(BinaryPacing.next(now: start, last: nil, queued: 3, underway: SocketIOClient.binaryInFlight), .hold)
        // Danach im Abstand von binarySpacing, bei Stau doppelt so schnell.
        guard case .wait(let due) = BinaryPacing.next(now: start, last: start, queued: 4, underway: 0) else {
            return XCTFail("muss warten")
        }
        XCTAssertEqual(Double(due.uptimeNanoseconds - start.uptimeNanoseconds) / 1e9, spacing, accuracy: 0.0005)
        guard case .wait(let faster) = BinaryPacing.next(now: start, last: start, queued: 8, underway: 0) else {
            return XCTFail("muss warten")
        }
        XCTAssertEqual(Double(faster.uptimeNanoseconds - start.uptimeNanoseconds) / 1e9, spacing / 2, accuracy: 0.0005)
        XCTAssertEqual(BinaryPacing.next(now: start + spacing, last: start, queued: 4, underway: 0), .send)

        // Fünf Rahmen auf einmal (100 ms Mikrofon) gehen gleichmäßig verteilt hinaus, nie als Stoß.
        var clock = start
        var last: DispatchTime?
        var queued = 5
        var sent: [DispatchTime] = []
        while queued > 0 {
            switch BinaryPacing.next(now: clock, last: last, queued: queued, underway: 0) {
            case .send:
                sent.append(clock)
                last = clock
                queued -= 1
            case .wait(let until):
                clock = until
            case .hold:
                return XCTFail("darf nicht anhalten")
            }
        }
        XCTAssertEqual(sent.count, 5)
        for (earlier, later) in zip(sent, sent.dropFirst()) {
            XCTAssertGreaterThanOrEqual(Double(later.uptimeNanoseconds - earlier.uptimeNanoseconds) / 1e9, spacing - 0.0005)
        }
        XCTAssertLessThan(Double(sent[4].uptimeNanoseconds - sent[0].uptimeNanoseconds) / 1e9, 0.1)
    }

    func testSpokenQueueSummary() {
        func item(_ kind: String, _ name: String, _ amount: String, _ state: String = "pending") -> QueueItem {
            QueueItem(kind: kind, id: name, name: name, message: "", amount: amount, voice: "default", state: state, at: "2026-10-13T11:00:00.000Z")
        }
        let empty = QueueResponse(filter: "open", items: [], pending: PendingCounts(donations: 0, subBombs: 0))
        XCTAssertEqual(empty.spokenSummary, "Nichts offen, die Warteschlange ist leer.")
        let one = QueueResponse(filter: "open", items: [item("donation", "Lea_K", "10,00 €")], pending: PendingCounts(donations: 1, subBombs: 0))
        XCTAssertEqual(one.spokenSummary, "1 Spende wartet. Als Nächstes: Lea_K mit 10,00 €.")
        let mixed = QueueResponse(
            filter: "open",
            items: [item("donation", "Alt", "5,00 €", "accepted"), item("subbomb", "GifterKing", "20"), item("donation", "MaxPower", "25,00 €")],
            pending: PendingCounts(donations: 3, subBombs: 1)
        )
        XCTAssertEqual(mixed.spokenSummary, "3 Spenden und 1 Sub-Bomb warten. Als Nächstes: GifterKing mit 20 Abos.")
        let bombs = QueueResponse(filter: "open", items: [], pending: PendingCounts(donations: 0, subBombs: 2))
        XCTAssertEqual(bombs.spokenSummary, "2 Sub-Bombs warten.")
    }

    func testQueueAmounts() {
        let one = QueueItem(kind: "subbomb", id: "1", name: "a", message: "", amount: "1", voice: "default", state: "pending", at: "")
        XCTAssertEqual(one.amountLabel, "1 Abo")
        let many = QueueItem(kind: "subbomb", id: "2", name: "a", message: "", amount: "25", voice: "default", state: "pending", at: "")
        XCTAssertEqual(many.amountLabel, "25 Abos")
        let donation = QueueItem(kind: "donation", id: "3", name: "a", message: "m", amount: "7,00 €", voice: "default", state: "accepted", at: "")
        XCTAssertEqual(donation.amountLabel, "7,00 €")
        XCTAssertTrue(donation.isAccepted)
    }

    func testStreamSeriesPoints() {
        let series = StreamSeries(times: [1_000, 61_000, 121_000], viewers: [10, 20, 30], chatters: [1, 2])
        XCTAssertEqual(series.points.count, 2)
        XCTAssertEqual(series.points[1].viewers, 20)
        XCTAssertEqual(series.points[1].date.timeIntervalSince1970, 61, accuracy: 0.001)
    }
}
