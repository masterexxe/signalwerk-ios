import SignalwerkKit
import SwiftUI
import WebKit

/// Anmeldung bei Twitch für den Player. Sie liegt als Cookies von twitch.tv im dauerhaften
/// Web-Speicher der App, den der Player mitbenutzt, und bleibt auf diesem Gerät.
@MainActor
enum TwitchSignIn {
    private static var store: WKWebsiteDataStore { .default() }

    static func currentAccount() async -> TwitchWebAccount? {
        let cookies = await store.httpCookieStore.allCookies()
        return TwitchWeb.account(from: cookies.map { WebCookie(name: $0.name, value: $0.value, domain: $0.domain) })
    }

    /// Cookies und gespeicherte Daten von twitch.tv löschen; der Player läuft danach als Gast.
    static func signOut() async {
        let cookieStore = store.httpCookieStore
        for cookie in await cookieStore.allCookies() where TwitchWeb.isTwitch(host: cookie.domain) {
            await cookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter { TwitchWeb.isTwitch(host: $0.displayName) }
        if !records.isEmpty {
            await store.removeData(ofTypes: types, for: records)
        }
    }
}

/// Anmeldeseite von twitch.tv. Sobald Twitch angemeldet hat, schließt sich das Blatt und der
/// Player lädt mit dem Konto neu.
struct TwitchLoginSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var failure: String?
    @State private var attempt = 0
    @State private var address = "www.twitch.tv"

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                TwitchLoginView(attempt: attempt, loading: $loading, failure: $failure, address: $address) {
                    Task {
                        await session.desk.refreshTwitch()
                        if let account = session.desk.twitchAccount {
                            let named = !account.displayName.isEmpty || !account.login.isEmpty
                            session.toasts.show(named ? "Bei Twitch angemeldet als \(account.label)." : "Bei Twitch angemeldet.")
                        }
                        dismiss()
                    }
                }
                .opacity(failure == nil ? 1 : 0)
                if let failure {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(Palette.textSubtle)
                        Text(failure)
                            .font(.callout)
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.center)
                        Button("Noch einmal laden") {
                            self.failure = nil
                            attempt += 1
                        }
                        .buttonStyle(PultKeyStyle(tone: Palette.amber, compact: true))
                    }
                    .padding(24)
                } else if loading {
                    ProgressView()
                        .tint(Palette.amber)
                }
            }
            .navigationTitle("Bei Twitch anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .accessibilityIdentifier("twitch-login-cancel")
                }
                ToolbarItem(placement: .principal) {
                    // Wie bei Anmeldungen in Safari: welche Seite gerade offen ist.
                    VStack(spacing: 1) {
                        Text("Bei Twitch anmelden")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Label(address, systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.textMuted)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .accessibilityIdentifier("twitch-login-address")
                    }
                }
            }
        }
    }
}

/// Web-Ansicht mit der Anmeldeseite von twitch.tv, im selben Web-Speicher wie der Player.
/// Angemeldet ist, sobald Twitch das Cookie `auth-token` setzt.
struct TwitchLoginView: UIViewRepresentable {
    var attempt: Int
    @Binding var loading: Bool
    @Binding var failure: String?
    @Binding var address: String
    var onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: TwitchWebKit.configuration())
        view.isOpaque = false
        view.backgroundColor = UIColor(Palette.background)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.view = view
        context.coordinator.start(attempt: attempt)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.start(attempt: attempt)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        view.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        var parent: TwitchLoginView
        weak var view: WKWebView?
        private var loadedAttempt: Int?
        private var signedIn = false
        private var checking = false
        private var recheck = false

        init(parent: TwitchLoginView) {
            self.parent = parent
        }

        func start(attempt: Int) {
            guard loadedAttempt != attempt, let view else { return }
            loadedAttempt = attempt
            view.load(URLRequest(url: TwitchWeb.loginURL))
        }

        /// Nach jeder Änderung an den Cookies: Hat Twitch angemeldet? Ändert sich während des
        /// Lesens wieder etwas, gleich noch einmal lesen.
        private func check() {
            guard !signedIn else { return }
            if checking {
                recheck = true
                return
            }
            checking = true
            Task { @MainActor [weak self] in
                let account = await TwitchSignIn.currentAccount()
                guard let self else { return }
                self.checking = false
                if account != nil {
                    self.finish()
                } else if self.recheck {
                    self.recheck = false
                    self.check()
                }
            }
        }

        /// Angemeldet: kurz warten, bis Twitch auch den Namen in die Cookies geschrieben hat.
        private func finish() {
            guard !signedIn else { return }
            signedIn = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.parent.onSignedIn()
            }
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in
                self?.check()
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Seiten laden; Links auf Apps (twitch://, App Store) nicht.
            guard let url = navigationAction.request.url else { return .cancel }
            return TwitchWebKit.isWebAddress(url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let host = webView.url?.host(), !host.isEmpty { parent.address = host }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            if let host = webView.url?.host(), !host.isEmpty { parent.address = host }
            check()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Neue Fenster (Hilfe, Passwort vergessen) im selben Blatt öffnen.
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        private func fail(_ error: any Error) {
            parent.loading = false
            guard TwitchWebKit.isConnectionProblem(error) else { return }
            parent.failure = "Die Anmeldeseite von Twitch lädt nicht. Prüfe die Verbindung."
        }
    }
}
