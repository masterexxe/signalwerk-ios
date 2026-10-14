import XCTest
@testable import SignalwerkKit

final class TwitchWebTests: XCTestCase {
    func testPlayerURL() throws {
        let url = TwitchWeb.playerURL(channel: " Signalwerk_Live ")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "player.twitch.tv")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["channel"], "signalwerk_live")
        XCTAssertEqual(items["parent"], "twitch.tv")
        XCTAssertEqual(items["autoplay"], "true")
        XCTAssertEqual(items["muted"], "false")
        XCTAssertTrue(TwitchWeb.isPlayer(host: url.host()))
    }

    func testHosts() {
        XCTAssertTrue(TwitchWeb.isTwitch(host: "twitch.tv"))
        XCTAssertTrue(TwitchWeb.isTwitch(host: ".twitch.tv"))
        XCTAssertTrue(TwitchWeb.isTwitch(host: "WWW.Twitch.tv"))
        XCTAssertTrue(TwitchWeb.isTwitch(host: "player.twitch.tv"))
        XCTAssertFalse(TwitchWeb.isTwitch(host: "eviltwitch.tv"))
        XCTAssertFalse(TwitchWeb.isTwitch(host: "twitch.tv.example.com"))
        XCTAssertFalse(TwitchWeb.isTwitch(host: nil))
        XCTAssertTrue(TwitchWeb.isPlayer(host: "player.twitch.tv"))
        XCTAssertFalse(TwitchWeb.isPlayer(host: "www.twitch.tv"))
    }

    func testAccountNeedsAuthToken() {
        XCTAssertNil(TwitchWeb.account(from: []))
        XCTAssertNil(TwitchWeb.account(from: [WebCookie(name: "login", value: "yusuf", domain: ".twitch.tv")]))
        XCTAssertNil(TwitchWeb.account(from: [WebCookie(name: "auth-token", value: " ", domain: ".twitch.tv")]))
        // Gleichnamiger Cookie einer anderen Seite zählt nicht.
        XCTAssertNil(TwitchWeb.account(from: [WebCookie(name: "auth-token", value: "abc", domain: "example.com")]))
    }

    func testAccountFromTwilightUser() {
        let user = #"{"authToken":"abc","displayName":"SignalwerkLive","id":"123","login":"signalwerklive","version":2}"#
        let encoded = user.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? user
        let account = TwitchWeb.account(from: [
            WebCookie(name: "auth-token", value: "abc", domain: ".twitch.tv"),
            WebCookie(name: "twilight-user", value: encoded, domain: ".twitch.tv"),
        ])
        XCTAssertEqual(account, TwitchWebAccount(login: "signalwerklive", displayName: "SignalwerkLive"))
        XCTAssertEqual(account?.label, "SignalwerkLive")
    }

    func testAccountFallbacks() {
        let fromLogin = TwitchWeb.account(from: [
            WebCookie(name: "auth-token", value: "abc", domain: "twitch.tv"),
            WebCookie(name: "login", value: "yusuf", domain: ".twitch.tv"),
            WebCookie(name: "twilight-user", value: "kaputt", domain: ".twitch.tv"),
        ])
        XCTAssertEqual(fromLogin, TwitchWebAccount(login: "yusuf", displayName: "yusuf"))
        let anonymous = TwitchWeb.account(from: [WebCookie(name: "auth-token", value: "abc", domain: "www.twitch.tv")])
        XCTAssertEqual(anonymous?.label, "Twitch-Konto")
    }
}
