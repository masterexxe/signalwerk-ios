import XCTest
@testable import SignalwerkKit

/// Echte Antworten des Dashboards (aufgenommen mit tools/e2e-app-api.mjs) müssen sich lesen lassen.
final class DecodingTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Fixture \(name) fehlt")
            return Data()
        }
        return try Data(contentsOf: url)
    }

    func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: fixture(name))
    }

    func testSession() throws {
        let session = try decode(SessionPayload.self, "session")
        XCTAssertTrue(session.token.hasPrefix("sw1."))
        XCTAssertEqual(session.user.role, "owner")
        XCTAssertEqual(session.user.roleLabel, "Owner")
        XCTAssertEqual(session.user.displayName, "Admin")
        XCTAssertTrue(session.permissions.contains(Permission.moderateDonations.rawValue))
        XCTAssertEqual(session.device.platform, "ipados")
        XCTAssertNil(session.device.push)
        XCTAssertEqual(session.server.api, 1)
        XCTAssertTrue(session.server.features.chat)
    }

    func testMe() throws {
        let me = try decode(MeResponse.self, "me")
        XCTAssertEqual(me.user.email, "admin@signalwerk.live")
    }

    func testOverview() throws {
        let overview = try decode(Overview.self, "overview")
        XCTAssertEqual(overview.stats.todaySumLabel, "15,50 €")
        XCTAssertEqual(overview.pending.total, overview.pending.donations + overview.pending.subBombs)
        XCTAssertEqual(overview.stream?.login, "signalwerk_live")
        XCTAssertEqual(overview.stream?.series.points.count, 0)
        XCTAssertTrue(overview.system.alertsReachable)
        XCTAssertEqual(overview.channels.defaultLogin, "signalwerk_live")
        XCTAssertNotNil(SignalwerkDate.parse(overview.at))
    }

    func testQueue() throws {
        let queue = try decode(QueueResponse.self, "queue-open")
        XCTAssertEqual(queue.filter, "open")
        XCTAssertTrue(queue.items.allSatisfy(\.isPending))
        let bomb = try XCTUnwrap(queue.items.first(where: \.isSubBomb))
        XCTAssertEqual(bomb.amountLabel, "12 Abos")
        let donation = try XCTUnwrap(queue.items.first(where: { !$0.isSubBomb }))
        XCTAssertTrue(donation.amountLabel.hasSuffix("€"))
        XCTAssertNotNil(donation.date)
        XCTAssertEqual(donation.key, "donation:\(donation.id)")
    }

    func testSoundsAndVoices() throws {
        let sounds = try decode(SoundsResponse.self, "sounds")
        XCTAssertEqual(sounds.master, 100)
        XCTAssertEqual(sounds.sounds.first?.name, "Jingle Spenden")
        XCTAssertTrue(sounds.sounds.allSatisfy { $0.previewUrl.hasPrefix("http") })
        let voices = try decode(VoicesResponse.self, "voices").voices
        XCTAssertEqual(voices.first?.value, "default")
        XCTAssertEqual(voices.first?.name, "Standard")
    }

    func testActionReplies() throws {
        let ok = try decode(ActionReply<Ignored>.self, "decide-ok")
        XCTAssertTrue(ok.ok)
        XCTAssertNil(ok.data)
        let stop = try decode(ActionReply<StopResult>.self, "stop")
        XCTAssertEqual(stop.data?.widgets, 0)
        XCTAssertEqual(stop.warning, "Kein OBS-Widget verbunden. Die Warteschlange im Alert-Dienst ist trotzdem geleert.")
    }

    func testErrorResponseBecomesServerText() throws {
        let data = try fixture("decide-error")
        let response = HTTPURLResponse(url: URL(string: "https://x.example")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try SignalwerkClient.decodeResponse(Ignored.self, data: data, response: response)) { error in
            XCTAssertEqual(error as? SignalwerkError, .server(status: 400, message: "Blockierte Spenden können nicht geändert werden."))
            XCTAssertEqual((error as? SignalwerkError)?.errorDescription, "Blockierte Spenden können nicht geändert werden.")
        }
    }

    func testUnauthorizedAndOldServer() {
        let unauthorized = HTTPURLResponse(url: URL(string: "https://x.example")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        let body = Data(#"{"ok":false,"error":"Die Anmeldung gilt nicht mehr. Bitte in der App neu anmelden."}"#.utf8)
        XCTAssertThrowsError(try SignalwerkClient.decodeResponse(Ignored.self, data: body, response: unauthorized)) { error in
            XCTAssertTrue((error as? SignalwerkError)?.isUnauthorized == true)
        }
        // Ältere Signalwerk-Version: HTML-Seite mit 404.
        let missing = HTTPURLResponse(url: URL(string: "https://x.example")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try SignalwerkClient.decodeResponse(Ignored.self, data: Data("<html>".utf8), response: missing)) { error in
            XCTAssertTrue(((error as? SignalwerkError)?.errorDescription ?? "").contains("2.5"))
        }
        // 200, aber kein JSON.
        let ok = HTTPURLResponse(url: URL(string: "https://x.example")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try SignalwerkClient.decodeResponse(MeResponse.self, data: Data("<html>".utf8), response: ok)) { error in
            guard case .invalidResponse = error as? SignalwerkError else { return XCTFail("\(error)") }
        }
    }

    func testDevicesAndStream() throws {
        let devices = try decode(DevicesResponse.self, "devices")
        XCTAssertTrue(devices.devices.contains { $0.id == devices.current })
        XCTAssertEqual(devices.devices.first?.own, true)
        let stream = try decode(StreamSnapshot.self, "stream")
        XCTAssertEqual(stream.uniqueChatters, 598)
        XCTAssertFalse(stream.live)
    }

    func testChatJoinAndBatch() throws {
        let reply = try decode(ChatJoinReply.self, "chat-join-lines")
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.lines.count, 2)
        guard case .message(let first) = reply.lines[0] else { return XCTFail("keine Nachricht") }
        XCTAssertEqual(first.name, "Lea_K")
        XCTAssertEqual(first.months, 14)
        XCTAssertEqual(first.emotes.count, 2)
        XCTAssertNotNil(reply.assets?.badges["subscriber/12"] ?? reply.assets?.badges.values.first)
        let batch = try decode(ChatBatch.self, "chat-batch")
        XCTAssertEqual(batch.channel, "signalwerk_live")
        guard case .line(.message(let line))? = batch.updates.first else { return XCTFail("keine Zeile") }
        XCTAssertEqual(line.login, "troll99")
    }

    func testUnknownChatLinesAreSkipped() throws {
        let json = #"{"ok":true,"lines":[{"kind":"neu","id":"x","at":1},{"kind":"system","id":"s","at":2,"tone":"info","text":"Hallo","userId":null,"login":null}]}"#
        let reply = try JSONDecoder().decode(ChatJoinReply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.lines.count, 1)
        XCTAssertEqual(reply.lines.first?.id, "s")
    }
}
