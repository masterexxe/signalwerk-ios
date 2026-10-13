import AppIntents
import SwiftUI
import SignalwerkKit

struct SettingsScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        let devices = session.devices
        List {
            Section("Angemeldet") {
                LabeledContent("Name", value: session.user.displayName)
                LabeledContent("Rolle", value: session.user.roleLabel)
                LabeledContent("Dashboard", value: session.isDemo ? "Demo" : ServerAddress.display(session.backend.serverURL))
                LabeledContent("Signalwerk", value: session.me.server.release)
            }
            .listRowBackground(Palette.card)

            if !session.isDemo {
                NotificationsSection()
                    .listRowBackground(Palette.card)
            }

            Section {
                if devices.devices.isEmpty && devices.loading {
                    ProgressView()
                }
                ForEach(devices.devices) { device in
                    DeviceRow(device: device, current: device.id == devices.current)
                        .swipeActions {
                            if device.id != devices.current {
                                Button(role: .destructive) {
                                    Task { await devices.revoke(device) }
                                } label: {
                                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        }
                }
            } header: {
                Text("Geräte")
            } footer: {
                Text("Geräte mit der Signalwerk-App. Zum Abmelden eines anderen Geräts nach links wischen.")
            }
            .listRowBackground(Palette.card)

            Section("OBS-Widget") {
                Button {
                    Task { await session.testAlert() }
                } label: {
                    Label("Test-Ton abspielen", systemImage: "speaker.wave.2")
                }
                .disabled(!session.can(.reloadWidget))
                Button {
                    Task { await session.reloadWidget() }
                } label: {
                    Label("Widget neu laden", systemImage: "arrow.clockwise")
                }
                .disabled(!session.can(.reloadWidget))
            }
            .listRowBackground(Palette.card)

            if !session.isDemo {
                Section {
                    ShortcutsLink()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Kurzbefehle und Siri")
                } footer: {
                    Text("„Notbremse in Signalwerk“, „Was wartet in Signalwerk“, „Sound in Signalwerk abspielen“. Auf iPhones mit Aktionstaste lässt sich die Notbremse dort ablegen: iOS-Einstellungen → Aktionstaste → Kurzbefehl.")
                }
                .listRowBackground(Palette.card)
            }

            Section {
                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    Label(session.isDemo ? "Demo beenden" : "Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("sign-out")
            } footer: {
                Text("Signalwerk für iPhone und iPad · Version \(Bundle.main.appVersion)")
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Einstellungen")
        .toolbar { EmergencyToolbar() }
        .task { await devices.load() }
        .refreshable { await devices.load() }
        .confirmationDialog(session.isDemo ? "Demo beenden?" : "Von diesem Gerät abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(session.isDemo ? "Demo beenden" : "Abmelden", role: .destructive) {
                model.signOut()
            }
        } message: {
            if !session.isDemo {
                Text("Das Gerät verliert seinen Zugang. Zum Wiederkommen meldest du dich neu an.")
            }
        }
    }
}

struct DeviceRow: View {
    let device: DeviceInfo
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.platform == "ipados" ? "ipad" : "iphone")
                .font(.title3)
                .foregroundStyle(current ? Palette.amber : Palette.textMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.text)
                    if current {
                        Text("dieses Gerät")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.amberInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Palette.amber, in: Capsule())
                    }
                }
                Text("zuletzt \(SignalwerkFormat.ago(SignalwerkDate.parse(device.lastSeenAt)))\(device.push != nil ? " · Mitteilungen an" : "")")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Mitteilungen bei neuen Spenden und Sub-Bombs.
struct NotificationsSection: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var testing = false

    var body: some View {
        let push = PushCenter.shared
        Section {
            switch push.status {
            case .on, .waiting:
                Toggle(isOn: Binding(get: { push.queueEnabled }, set: { push.setQueueEnabled($0) })) {
                    Label("Neue Spenden und Sub-Bombs", systemImage: "bell.badge")
                }
                .tint(Palette.amber)
                Button {
                    testing = true
                    Task {
                        do {
                            try await session.backend.testPush()
                            session.toasts.show("Test-Mitteilung ist unterwegs.")
                        } catch {
                            session.context.report(error)
                        }
                        testing = false
                    }
                } label: {
                    Label(testing ? "Wird gesendet …" : "Test-Mitteilung senden", systemImage: "paperplane")
                }
                .disabled(testing || push.status != .on)
            case .denied:
                Label("Mitteilungen sind in den iOS-Einstellungen aus.", systemImage: "bell.slash")
                    .foregroundStyle(Palette.textMuted)
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.orange)
                Button("Noch einmal versuchen") {
                    Task { await push.enable() }
                }
            case .off, .unknown:
                Button {
                    Task { await push.enable() }
                } label: {
                    Label("Mitteilungen einschalten", systemImage: "bell")
                }
            }
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text(session.me.server.features.push
                ? "Bei jeder neuen Spende oder Sub-Bomb, die auf dich wartet: Mitteilung mit „Annehmen“ und „Blockieren“."
                : "Im Dashboard ist Push noch nicht eingerichtet (APNS_KEY_ID, APNS_TEAM_ID und APNS_KEY in der .env). Bis dahin kommen keine Mitteilungen an.")
        }
        .task { await push.refresh() }
    }
}
