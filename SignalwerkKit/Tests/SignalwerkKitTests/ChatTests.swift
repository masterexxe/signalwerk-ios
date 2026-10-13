import XCTest
@testable import SignalwerkKit

final class ChatTests: XCTestCase {
    func testSegmentsCountCodepointsLikeTheDashboard() {
        // Hautton-Emoji sind zwei Codepoints; die Positionen kommen von Twitch in Codepoints.
        let text = "Kappa Grüße 👋🏽 aus Köln Kappa"
        let segments = ChatText.segments(text, emotes: [ChatEmote(id: "25", start: 0, end: 4), ChatEmote(id: "25", start: 24, end: 28)])
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .emote(name: "Kappa", url: ChatText.twitchEmoteURL("25"), url2: ChatText.twitchEmoteURL("25", scale: "2.0"), provider: "twitch"))
        XCTAssertEqual(segments[1], .text(" Grüße 👋🏽 aus Köln "))
        if case .emote(let name, _, _, _) = segments[2] {
            XCTAssertEqual(name, "Kappa")
        } else {
            XCTFail("zweites Emote fehlt")
        }
    }

    func testSegmentsFindLinksMentionsAndExtraEmotes() {
        let extra = ["monkaS": ChatExtraEmote(url: "https://cdn.betterttv.net/emote/x/1x", url2: "https://cdn.betterttv.net/emote/x/2x", provider: "bttv", channel: nil)]
        let segments = ChatText.segments("@lea_k, schau auf signalwerk.live monkaS https://twitch.tv/x", emotes: [], extra: extra)
        XCTAssertEqual(segments[0], .mention(text: "@lea_k", login: "lea_k"))
        XCTAssertEqual(segments[1], .text(", schau auf "))
        XCTAssertEqual(segments[2], .link(text: "signalwerk.live", href: "https://signalwerk.live"))
        XCTAssertEqual(segments[3], .text(" "))
        XCTAssertEqual(segments[4], .emote(name: "monkaS", url: "https://cdn.betterttv.net/emote/x/1x", url2: "https://cdn.betterttv.net/emote/x/2x", provider: "bttv"))
        XCTAssertEqual(segments[6], .link(text: "https://twitch.tv/x", href: "https://twitch.tv/x"))
        // Kein Link: unbekannte Endung, kein Erwähnungs-Login.
        XCTAssertEqual(ChatText.segments("bitte.nicht @ab", emotes: []), [.text("bitte.nicht @ab")])
    }

    func testSegmentsIgnoreBrokenEmotePositions() {
        let segments = ChatText.segments("hi", emotes: [ChatEmote(id: "1", start: 5, end: 9)])
        XCTAssertEqual(segments, [.text("hi")])
    }

    func testMentions() {
        XCTAssertTrue(ChatText.mentions("hallo @Signalwerk_Live!", login: "signalwerk_live"))
        XCTAssertTrue(ChatText.mentions("signalwerk_live, hallo", login: "signalwerk_live"))
        XCTAssertFalse(ChatText.mentions("signalwerk_livex", login: "signalwerk_live"))
    }

    func message(_ id: String, user: String = "u1", at: Double = 1) -> ChatLine {
        .message(ChatMessage(id: id, at: at, userId: user, login: user, name: user, color: "", badges: [], months: 0, text: "x", emotes: []))
    }

    func testBufferAppliesUpdates() {
        var buffer = ChatBuffer(limit: 3)
        buffer.replace(with: [message("a", at: 1), message("b", user: "u2", at: 2)])
        buffer.apply([.line(message("c", at: 3)), .line(message("c", at: 3))])
        XCTAssertEqual(buffer.lines.map(\.id), ["a", "b", "c"])
        buffer.apply([.delete(id: "b")])
        if case .message(let deleted) = buffer.lines[1] { XCTAssertTrue(deleted.deleted) } else { XCTFail() }
        buffer.apply([.clearUser(userId: "u1", clear: ChatClear(kind: "timeout", seconds: 600, at: 4))])
        if case .message(let cleared) = buffer.lines[0] { XCTAssertEqual(cleared.cleared?.seconds, 600) } else { XCTFail() }
        buffer.apply([.line(message("d", at: 5))])
        XCTAssertEqual(buffer.lines.map(\.id), ["b", "c", "d"])
        buffer.apply([.clearAll(at: 4)])
        if case .message(let old) = buffer.lines[0] { XCTAssertEqual(old.cleared?.kind, "chat") } else { XCTFail() }
        if case .message(let fresh) = buffer.lines[2] { XCTAssertNil(fresh.cleared) } else { XCTFail() }
    }

    func testSocketCodecParsesServerPackets() {
        XCTAssertEqual(SocketCodec.parse(#"0{"sid":"x","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#), .open(pingInterval: 25000, pingTimeout: 20000))
        XCTAssertEqual(SocketCodec.parse("2"), .ping)
        XCTAssertEqual(SocketCodec.parse(#"40{"sid":"abc"}"#), .connected)
        XCTAssertEqual(SocketCodec.parse("41"), .disconnected)
        XCTAssertEqual(SocketCodec.parse(#"44{"message":"Nein"}"#), .connectError("Nein"))
        XCTAssertEqual(SocketCodec.parse(#"431[{"ok":true}]"#), .ack(id: 31, argumentsJSON: #"[{"ok":true}]"#))
        guard case .event(let name, let json, let ackId) = SocketCodec.parse(#"42["chat-state",{"channel":"x","connected":true}]"#) else {
            return XCTFail("kein Ereignis")
        }
        XCTAssertEqual(name, "chat-state")
        XCTAssertNil(ackId)
        XCTAssertEqual(SocketCodec.decodeFirst(ChatState.self, from: json), ChatState(channel: "x", connected: true, error: nil))
        guard case .event(_, _, let ack) = SocketCodec.parse(#"427["frage"]"#) else { return XCTFail() }
        XCTAssertEqual(ack, 7)
        XCTAssertEqual(SocketCodec.parse("6"), .unknown("6"))
    }

    func testSocketCodecEncodes() {
        XCTAssertEqual(SocketCodec.encodeEvent("chat-leave", [["channel": "x"]]), #"42["chat-leave",{"channel":"x"}]"#)
        XCTAssertEqual(SocketCodec.encodeEvent("chat-join", [], ackId: 3), #"423["chat-join"]"#)
        XCTAssertEqual(SocketCodec.encodeBinaryEvent("live-audio"), #"451-["live-audio",{"_placeholder":true,"num":0}]"#)
        let url = SocketIOClient.socketURL(for: URL(string: "https://dashboard.signalwerk.live")!)
        XCTAssertEqual(url.absoluteString, "wss://dashboard.signalwerk.live/socket.io/?EIO=4&transport=websocket")
        let local = SocketIOClient.socketURL(for: URL(string: "http://localhost:8080")!)
        XCTAssertEqual(local.absoluteString, "ws://localhost:8080/socket.io/?EIO=4&transport=websocket")
    }
}

