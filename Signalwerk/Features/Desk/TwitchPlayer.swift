import AVFoundation
import SignalwerkKit
import SwiftUI
import UIKit
import WebKit

/// Zustand des Twitch-Players, wie ihn das Skript in der Seite meldet.
enum TwitchPlayerState: Equatable {
    case loading
    case playing
    case stopped
    case failed(String)
}

/// Twitch-Player als eigene Seite von player.twitch.tv, wie das Popout-Fenster von Twitch. Er nutzt
/// denselben Web-Speicher wie die Twitch-Anmeldung der App: Angemeldet zeigt Twitch dieselbe
/// Werbung wie auf twitch.tv. Ein kleines Skript in der Seite meldet, ob das Video läuft, und
/// schaltet den Ton aus, solange Live-Voice läuft.
struct TwitchPlayerView: UIViewRepresentable {
    let channel: String
    /// Neu laden, sobald sich das ändert (An- und Abmelden bei Twitch, „Noch einmal laden“).
    var reload: Int
    var muted: Bool
    var onState: (TwitchPlayerState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onState: onState)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = TwitchWebKit.configuration()
        configuration.userContentController.add(context.coordinator, name: "player")
        configuration.userContentController.addUserScript(
            WKUserScript(source: TwitchPlayerView.controlScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.show(channel: channel, reload: reload, muted: muted)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onState = onState
        context.coordinator.show(channel: channel, reload: reload, muted: muted)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "player")
        view.stopLoading()
        // Leere Seite: Der Ton endet sofort, nicht erst, wenn die Ansicht freigegeben ist.
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var onState: (TwitchPlayerState) -> Void
        weak var view: WKWebView?
        private var channel = ""
        private var page: String?
        private var ready = false
        private var muted = false
        private var appliedMute: Bool?

        init(onState: @escaping (TwitchPlayerState) -> Void) {
            self.onState = onState
        }

        /// Seite nur bei neuem Kanal oder neuem Ladeauftrag laden; den Ton steuert das Skript.
        func show(channel: String, reload: Int, muted: Bool) {
            self.channel = channel
            self.muted = muted
            let key = "\(channel)|\(reload)"
            if page != key, let view {
                page = key
                load(view)
            }
            applyMute()
        }

        private func load(_ view: WKWebView) {
            ready = false
            appliedMute = nil
            report(.loading)
            view.load(URLRequest(url: TwitchWeb.playerURL(channel: channel)))
        }

        /// Zustand erst nach dem laufenden Aktualisieren der Ansicht weitergeben.
        private func report(_ state: TwitchPlayerState) {
            Task { @MainActor [weak self] in
                self?.onState(state)
            }
        }

        private func applyMute() {
            guard ready, appliedMute != muted, let view else { return }
            appliedMute = muted
            view.evaluateJavaScript("window.signalwerk && window.signalwerk.setMuted(\(muted ? "true" : "false"))", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                // Jede geladene Seite meldet sich neu und startet mit Ton.
                ready = true
                appliedMute = nil
                applyMute()
            case "playing":
                report(.playing)
            case "stopped":
                report(.stopped)
            default:
                break
            }
        }

        // MARK: Navigation: Die Ansicht bleibt beim Player; Links gehen nach außen.

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            // Rahmen in der Seite (Werbung, Erweiterungen) lädt der Player selbst.
            if let frame = navigationAction.targetFrame, !frame.isMainFrame { return .allow }
            if url.scheme == "about" || TwitchWeb.isPlayer(host: url.host()) { return .allow }
            if navigationAction.navigationType == .linkActivated {
                openOutside(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // „Auf Twitch ansehen“ und andere Links in neuem Fenster: in Safari oder der Twitch-App.
            if let url = navigationAction.request.url { openOutside(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // iOS hat die Seite beendet (Speicher): neu laden.
            load(webView)
        }

        private func fail(_ error: any Error) {
            guard TwitchWebKit.isConnectionProblem(error) else { return }
            report(.failed("Twitch ist gerade nicht erreichbar. Prüfe die Verbindung."))
        }

        private func openOutside(_ url: URL) {
            guard url.scheme == "https" || url.scheme == "http" else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    /// Läuft in der Seite des Players: meldet Wiedergabe, schaltet den Ton für Live-Voice aus und
    /// danach wieder an. Twitch kann Videos austauschen (Werbung), daher immer alle Videos der Seite.
    static let controlScript = """
    (function () {
      if (window.signalwerk) { return; }
      function post(type) {
        try { window.webkit.messageHandlers.player.postMessage({ type: type }); } catch (e) {}
      }
      var wantMuted = false;
      var mutedByUs = [];
      var playedBefore = [];
      var scheduled = false;
      function videos() { return Array.prototype.slice.call(document.querySelectorAll("video")); }
      function watch(video) {
        if (video.signalwerkWatched) { return; }
        video.signalwerkWatched = true;
        video.addEventListener("playing", function () { post("playing"); });
        video.addEventListener("pause", function () {
          if (videos().every(function (other) { return other.paused; })) { post("stopped"); }
        });
        video.addEventListener("ended", function () { post("stopped"); });
        // Während Live-Voice bleibt der Ton aus, auch wenn der Player ihn selbst wieder einschaltet.
        video.addEventListener("volumechange", function () {
          if (wantMuted && !video.muted) {
            video.muted = true;
            if (mutedByUs.indexOf(video) < 0) { mutedByUs.push(video); }
          }
        });
        if (!video.paused) { post("playing"); }
      }
      function apply() {
        videos().forEach(function (video) {
          watch(video);
          if (wantMuted && !video.muted) {
            video.muted = true;
            mutedByUs.push(video);
          }
        });
      }
      new MutationObserver(function () {
        if (scheduled) { return; }
        scheduled = true;
        setTimeout(function () { scheduled = false; apply(); }, 300);
      }).observe(document.documentElement, { childList: true, subtree: true });
      window.signalwerk = {
        setMuted: function (on) {
          on = !!on;
          if (on === wantMuted) { apply(); return; }
          wantMuted = on;
          if (on) {
            playedBefore = videos().filter(function (video) { return !video.paused; });
            apply();
            return;
          }
          mutedByUs.forEach(function (video) { video.muted = false; });
          mutedByUs = [];
          // Hat die Aufnahme die Wiedergabe angehalten, weiterspielen.
          playedBefore.forEach(function (video) {
            if (video.isConnected && video.paused) {
              var started = video.play();
              if (started && started.catch) { started.catch(function () {}); }
            }
          });
          playedBefore = [];
        }
      };
      apply();
      post("ready");
    })();
    """
}

/// Gemeinsame Einstellungen der Web-Ansichten für Twitch (Player und Anmeldung): derselbe
/// dauerhafte Web-Speicher, Video im Bild statt Vollbild, Ton ohne Antippen, Browserkennung
/// wie Safari.
@MainActor
enum TwitchWebKit {
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = TwitchWeb.userAgentSuffix(
            systemVersion: UIDevice.current.systemVersion,
            pad: UIDevice.current.userInterfaceIdiom == .pad
        )
        return configuration
    }

    /// Nur echte Verbindungsprobleme zeigen. Abbrüche, neue Seiten und Links auf Apps
    /// (twitch://, App Store) sind kein Fehler der Seite.
    nonisolated static func isConnectionProblem(_ error: any Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed, NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed,
        ].contains(error.code)
    }

    /// Adressen, die in der Web-Ansicht laden dürfen; andere (Apps, Mail) nicht.
    nonisolated static func isWebAddress(_ url: URL) -> Bool {
        ["http", "https", "about", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
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
