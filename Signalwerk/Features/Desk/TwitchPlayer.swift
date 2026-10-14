import AVFoundation
import SwiftUI
import WebKit

/// Zustand des Twitch-Players, wie ihn die Seite im WKWebView meldet.
enum TwitchPlayerState: Equatable {
    case loading
    case playing
    case offline
    case failed(String)
}

/// Twitch-Player in einem WKWebView. Die kleine Seite lädt unter der Adresse des Dashboards
/// (`host`): Twitch spielt eingebettet nur, wenn `parent` zur Seite passt, wie im Arbeitsbereich
/// des Dashboards. Über die Embed-API lässt sich der Player anhalten und stumm schalten.
struct TwitchPlayerView: UIViewRepresentable {
    let channel: String
    let host: String
    var paused: Bool
    var onState: (TwitchPlayerState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onState: onState)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "player")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.view = view
        context.coordinator.show(channel: channel, host: host, paused: paused)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onState = onState
        context.coordinator.show(channel: channel, host: host, paused: paused)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onState: (TwitchPlayerState) -> Void
        weak var view: WKWebView?
        private var page: String?
        private var ready = false
        private var paused = false
        private var appliedPause: Bool?

        init(onState: @escaping (TwitchPlayerState) -> Void) {
            self.onState = onState
        }

        /// Seite nur bei neuem Kanal oder Server neu laden; Anhalten geht über die Embed-API.
        func show(channel: String, host: String, paused: Bool) {
            self.paused = paused
            let key = "\(host)|\(channel)"
            if page != key, let view {
                page = key
                ready = false
                appliedPause = nil
                onState(.loading)
                view.loadHTMLString(TwitchPlayerView.html(channel: channel, host: host), baseURL: URL(string: "https://\(host)/"))
            }
            applyPause()
        }

        private func applyPause() {
            guard ready, appliedPause != paused, let view else { return }
            appliedPause = paused
            view.evaluateJavaScript(paused ? "window.signalwerk && window.signalwerk.pause()" : "window.signalwerk && window.signalwerk.play()", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                applyPause()
            case "playing", "online":
                onState(.playing)
            case "offline":
                onState(.offline)
            case "error":
                onState(.failed(body["message"] as? String ?? "Der Twitch-Player ließ sich nicht laden."))
            default:
                break
            }
        }
    }

    /// Seite mit dem Player. Werte als JSON, damit nichts aus dem Skript ausbricht.
    static func html(channel: String, host: String) -> String {
        """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:absolute;top:0;right:0;bottom:0;left:0}#player iframe{width:100%;height:100%;border:0}</style>
        </head><body><div id="player"></div>
        <script>
        (function () {
          function post(type, extra) {
            try { window.webkit.messageHandlers.player.postMessage(Object.assign({ type: type }, extra || {})); } catch (e) {}
          }
          var script = document.createElement("script");
          script.src = "https://player.twitch.tv/js/embed/v1.js";
          script.onerror = function () { post("error", { message: "Twitch ist gerade nicht erreichbar." }); };
          script.onload = function () {
            if (!window.Twitch || !window.Twitch.Player) { post("error", { message: "Der Twitch-Player ließ sich nicht laden." }); return; }
            var Player = window.Twitch.Player;
            var player = new Player("player", { channel: \(json(channel)), parent: [\(json(host))], width: "100%", height: "100%", autoplay: true, muted: false });
            window.signalwerk = {
              pause: function () { try { player.pause(); } catch (e) {} },
              play: function () { try { player.play(); } catch (e) {} }
            };
            player.addEventListener(Player.READY, function () { post("ready"); });
            player.addEventListener(Player.PLAYING, function () { post("playing"); });
            player.addEventListener(Player.ONLINE, function () { post("online"); });
            player.addEventListener(Player.OFFLINE, function () { post("offline"); });
          };
          document.head.appendChild(script);
        })();
        </script>
        </body></html>
        """
    }

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
    }
}

/// Ton des Players auch bei stummgeschaltetem iPhone; andere Wiedergabe (Musik) läuft weiter.
enum PlayerAudio {
    static func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
