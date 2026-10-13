import AuthenticationServices
import SwiftUI
import SignalwerkKit

/// Anmeldung: Adresse des Dashboards, dann über die Webseite (Passwort oder Twitch) oder direkt
/// mit E-Mail und Passwort. Dazu die Demo ohne Server.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case server, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let message = error ?? model.signOutMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.red.opacity(0.4)))
                        .accessibilityIdentifier("login-error")
                }
                serverPlate
                Button {
                    model.startDemo()
                } label: {
                    Label("Demo ansehen", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textMuted)
                .accessibilityIdentifier("demo-button")
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 22)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .onAppear {
            if server.isEmpty { server = model.lastServer }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandMark(size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text("Signalwerk")
                    .font(.display(38, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text("Spenden, Sounds, TTS und Chat deines Streams – am Pult und unterwegs.")
                    .font(.body)
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var serverPlate: some View {
        Plate(title: "Anmelden", tone: Palette.amber) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adresse des Dashboards")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.textMuted)
                    TextField("dashboard.signalwerk.live", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus, equals: .server)
                        .onSubmit { Task { await webLogin() } }
                        .fieldStyle()
                        .accessibilityIdentifier("server-field")
                }

                Button {
                    Task { await webLogin() }
                } label: {
                    HStack {
                        if busy && !showPassword { ProgressView().tint(Palette.amberInk) }
                        Text("Anmelden")
                    }
                }
                .buttonStyle(AmberKeyStyle())
                .disabled(busy)
                .accessibilityIdentifier("login-button")

                Text("Öffnet die Anmeldung deines Dashboards – mit Team-Zugang oder Twitch. Danach bleibt dieses Gerät angemeldet, bis du dich abmeldest.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Palette.line)

                DisclosureGroup(isExpanded: $showPassword) {
                    VStack(spacing: 12) {
                        TextField("E-Mail", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .fieldStyle()
                        SecureField("Passwort", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await passwordLogin() } }
                            .fieldStyle()
                        Button {
                            Task { await passwordLogin() }
                        } label: {
                            HStack {
                                if busy && showPassword { ProgressView() }
                                Text("Mit Passwort anmelden")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PultKeyStyle(tone: Palette.text))
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Mit E-Mail und Passwort")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.text)
                }
                .tint(Palette.textMuted)
            }
        }
    }

    private func serverURL() -> URL? {
        guard let url = ServerAddress.normalize(server) else {
            error = "Bitte die Adresse des Dashboards eingeben, etwa dashboard.signalwerk.live."
            return nil
        }
        return url
    }

    private func webLogin() async {
        guard !busy, let url = serverURL() else { return }
        guard let connect = WebConnect(server: url, deviceName: AppModel.deviceName, platform: AppModel.platform) else { return }
        focus = nil
        busy = true
        error = nil
        defer { busy = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: connect.url,
                callbackURLScheme: WebConnect.callbackScheme,
                preferredBrowserSession: .shared
            )
            switch connect.evaluate(callback) {
            case .code(let code):
                let payload = try await SignalwerkLogin.exchange(server: url, code: code, verifier: connect.pkce.verifier)
                model.signedIn(server: url, payload: payload)
            case .cancelled:
                return
            case .invalid:
                error = "Die Anmeldung kam nicht zurück. Bitte noch einmal versuchen."
            }
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func passwordLogin() async {
        guard !busy, let url = serverURL() else { return }
        focus = nil
        busy = true
        error = nil
        defer { busy = false }
        do {
            let payload = try await SignalwerkLogin.password(
                server: url,
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                deviceName: AppModel.deviceName,
                platform: AppModel.platform
            )
            password = ""
            model.signedIn(server: url, payload: payload)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Zeichen von Signalwerk: Pulslinie auf Bernstein.
struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFFC14D), Palette.amber], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                PulseShape()
                    .stroke(Palette.amberInk, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                    .padding(size * 0.16)
            )
            .shadow(color: Palette.amber.opacity(0.35), radius: size * 0.25)
            .accessibilityHidden(true)
    }
}

/// Die Pulslinie aus dem Logo des Dashboards (icon.svg), auf 0…1 skaliert.
struct PulseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(5.5, 17.5), (9.7, 17.5), (12.3, 11.0), (16.5, 23.0), (19.5, 13.8), (21.1, 17.5), (26.5, 17.5)]
        // Ursprünglich im Feld 32×32; Bereich x 5,5…26,5 und y 11…23 auf das Rechteck legen.
        let minX: CGFloat = 5.5, maxX: CGFloat = 26.5, minY: CGFloat = 9, maxY: CGFloat = 25
        var path = Path()
        for (index, point) in points.enumerated() {
            let x = rect.minX + (point.0 - minX) / (maxX - minX) * rect.width
            let y = rect.minY + (point.1 - minY) / (maxY - minY) * rect.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

extension View {
    /// Eingabefeld wie im Pult: vertieft, dunkel.
    func fieldStyle() -> some View {
        self
            .font(.body)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Palette.input, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}
