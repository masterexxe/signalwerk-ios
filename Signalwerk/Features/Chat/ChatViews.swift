import SwiftUI
import SignalwerkKit

struct ChatScreen: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ChatPanel(framed: false)
            .background(Palette.background)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EmergencyToolbar()
                ToolbarItem(placement: .topBarLeading) {
                    ChatChannelMenu()
                }
            }
    }
}

struct ChatChannelMenu: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let chat = session.chat
        Menu {
            ForEach(chat.channels) { channel in
                Button {
                    chat.select(channel.login)
                } label: {
                    if channel.login == chat.channel {
                        Label(channel.displayName, systemImage: "checkmark")
                    } else {
                        Text(channel.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                TallyLamp(color: chatLamp(chat), lit: chat.connection == .live && chat.twitchConnected, size: 7)
                Text(chat.channels.first(where: { $0.login == chat.channel })?.displayName ?? chat.channel ?? "Kanal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .accessibilityLabel("Kanal wählen")
    }

    private func chatLamp(_ chat: ChatStore) -> Color {
        switch chat.connection {
        case .live: return chat.twitchConnected ? Palette.green : Palette.orange
        case .connecting: return Palette.amber
        default: return Palette.red
        }
    }
}

/// Chat mit Verlauf, Moderation per langem Druck und Eingabe unten.
struct ChatPanel: View {
    @Environment(AppSession.self) private var session
    /// Im Pult mit Rahmen und Klebeband, sonst randlos.
    var framed = true
    @State private var atBottom = true
    @State private var selected: ChatMessage?

    var body: some View {
        let chat = session.chat
        VStack(spacing: 0) {
            if framed {
                HStack {
                    TapeLabel(title: "Chat", tone: Palette.violet, lit: chat.connection == .live)
                    Spacer()
                    ChatChannelMenu()
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            status
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chat.lines) { line in
                            ChatLineView(line: line)
                                .id(line.id)
                                .contentShape(Rectangle())
                                .onLongPressGesture {
                                    if case .message(let message) = line { selected = message }
                                }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: chat.lines.last?.id) { _, _ in
                    guard atBottom else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .overlay(alignment: .bottom) {
                    if !atBottom {
                        Button {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        } label: {
                            Label("Neueste", systemImage: "arrow.down")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.surface2, in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.lineStrong))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.text)
                        .padding(.bottom, 8)
                    }
                }
            }
            if session.can(.moderateChat) {
                ChatComposer()
            }
        }
        .background {
            if framed { PlateBackground() }
        }
        .task { await chat.start() }
        .sheet(item: $selected) { message in
            ChatUserSheet(message: message)
                .presentationDetents([.medium, .large])
                .presentationBackground(Palette.surface)
        }
    }

    @ViewBuilder
    private var status: some View {
        let chat = session.chat
        switch chat.connection {
        case .offline(let reason):
            StatusStrip(text: reason ?? "Chat nicht verbunden. Neuer Versuch läuft …", color: Palette.red)
        case .connecting, .idle:
            StatusStrip(text: "Chat verbindet …", color: Palette.amber)
        case .live:
            if !chat.twitchConnected {
                StatusStrip(text: chat.twitchError ?? "Der Alert-Dienst ist gerade nicht mit Twitch verbunden.", color: Palette.orange)
            }
        }
    }
}

struct StatusStrip: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            TallyLamp(color: color, size: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
    }
}

/// Eine Zeile: Uhrzeit, Badges, Name in seiner Farbe, Text mit Emotes.
struct ChatLineView: View {
    @Environment(AppSession.self) private var session
    let line: ChatLine

    var body: some View {
        switch line {
        case .message(let message):
            messageView(message)
        case .notice(let notice):
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.system)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.text)
                if !notice.text.isEmpty {
                    ChatTextView(text: notice.text, emotes: notice.emotes)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.violet).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .system(let system):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon(for: system.tone))
                    .font(.caption)
                Text(system.text)
                    .font(.footnote)
            }
            .foregroundStyle(color(for: system.tone))
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        let removed = message.deleted || message.cleared != nil
        VStack(alignment: .leading, spacing: 3) {
            if let reply = message.reply {
                Label("Antwort an \(reply.name): \(reply.text)", systemImage: "arrowshape.turn.up.left")
                    .font(.caption)
                    .foregroundStyle(Palette.textSubtle)
                    .lineLimit(1)
            }
            if message.first {
                Text("Erste Nachricht")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.violet)
            }
            let flow = FlowLayout(spacing: 0, lineSpacing: 2)
            flow {
                Text(SignalwerkFormat.clock(Date(timeIntervalSince1970: message.at / 1000)) + " ")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.textSubtle)
                ForEach(Array(session.chat.badgeImages(message.badges).enumerated()), id: \.offset) { _, badge in
                    RemoteImage(url: badge.url2, size: 16)
                        .padding(.trailing, 3)
                        .accessibilityLabel(badge.title)
                }
                Text(message.name + (message.action ? " " : ": "))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.chatName(message.color))
                ChatTextPieces(text: message.text, emotes: message.emotes, italic: message.action, tint: message.action ? Palette.chatName(message.color) : nil)
            }
            .strikethrough(removed)
            .opacity(removed ? 0.45 : 1)
            if let cleared = message.cleared {
                Text(cleared.kind == "timeout" ? "Timeout \(SignalwerkFormat.timeout(cleared.seconds ?? 0))" : cleared.kind == "ban" ? "Gebannt" : "Chat geleert")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.red)
            } else if message.deleted {
                Text("Gelöscht")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.red)
            }
        }
        .padding(.vertical, 2)
        .background(mentionsMe(message) ? Palette.amber.opacity(0.1) : .clear)
    }

    private func mentionsMe(_ message: ChatMessage) -> Bool {
        guard let login = session.user.twitchLogin else { return false }
        return ChatText.mentions(message.text, login: login)
    }

    private func icon(for tone: String) -> String {
        switch tone {
        case "timeout": return "timer"
        case "ban": return "nosign"
        case "unban": return "arrow.uturn.backward"
        case "clear": return "trash"
        case "error": return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }

    private func color(for tone: String) -> Color {
        switch tone {
        case "timeout", "ban", "error": return Palette.red
        case "unban": return Palette.green
        default: return Palette.textMuted
        }
    }
}

/// Text einer Nachricht für Hinweise (ohne Uhrzeit und Namen).
struct ChatTextView: View {
    let text: String
    let emotes: [ChatEmote]

    var body: some View {
        let flow = FlowLayout(spacing: 0, lineSpacing: 2)
        flow {
            ChatTextPieces(text: text, emotes: emotes, italic: false, tint: nil)
        }
    }
}

/// Stücke als einzelne Views im Fließlayout: Wörter, Emotes, Links, Erwähnungen.
struct ChatTextPieces: View {
    @Environment(AppSession.self) private var session
    let text: String
    let emotes: [ChatEmote]
    let italic: Bool
    let tint: Color?

    var body: some View {
        let segments = ChatText.segments(text, emotes: emotes, extra: session.chat.assets.emotes)
        ForEach(Array(pieces(segments).enumerated()), id: \.offset) { _, piece in
            switch piece {
            case .word(let word):
                Text(word)
                    .font(.subheadline)
                    .italic(italic)
                    .foregroundStyle(tint ?? Palette.text)
            case .emote(let name, let url):
                RemoteImage(url: url, size: 24)
                    .accessibilityLabel(name)
            case .mention(let text):
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.amber)
            case .link(let text, let href):
                if let destination = URL(string: href) {
                    Link(text, destination: destination)
                        .font(.subheadline)
                        .foregroundStyle(Palette.blue)
                } else {
                    Text(text).font(.subheadline)
                }
            }
        }
    }

    enum Piece {
        case word(String)
        case emote(name: String, url: String)
        case mention(String)
        case link(String, String)
    }

    /// Text in Wörter zerlegen, damit das Fließlayout umbrechen kann; Leerzeichen bleiben am Wort.
    private func pieces(_ segments: [ChatSegment]) -> [Piece] {
        var result: [Piece] = []
        for segment in segments {
            switch segment {
            case .text(let text):
                var current = ""
                for character in text {
                    current.append(character)
                    if character == " " {
                        result.append(.word(current))
                        current = ""
                    }
                }
                if !current.isEmpty { result.append(.word(current)) }
            case .emote(let name, _, let url2, _):
                result.append(.emote(name: name, url: url2))
            case .mention(let text, _):
                result.append(.mention(text))
            case .link(let text, let href):
                result.append(.link(text, href))
            }
        }
        return result
    }
}

/// Bild aus dem Netz (Emotes, Badges) mit festem Platz.
struct RemoteImage: View {
    let url: String
    var size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url), transaction: Transaction(animation: nil)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(height: size)
        .frame(minWidth: size * 0.6, maxWidth: size * 3.2)
    }
}

/// Eingabe unten: Nachricht schreiben (mit dem Konto, das auch moderiert).
struct ChatComposer: View {
    @Environment(AppSession.self) private var session
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var chat = session.chat
        VStack(spacing: 6) {
            if let reply = chat.replyTo {
                HStack {
                    Label("Antwort an \(reply.name)", systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                    Spacer()
                    Button {
                        chat.replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSubtle)
                }
            }
            HStack(spacing: 8) {
                TextField(chat.channel.map { "Nachricht an #\($0)" } ?? "Nachricht", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { Task { await chat.send() } }
                    .fieldStyle()
                Button {
                    Task { await chat.send() }
                } label: {
                    Image(systemName: chat.sending ? "hourglass" : "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(chat.canSend ? Palette.amber : Palette.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(chat.canSend ? Palette.amberInk : Palette.textSubtle)
                }
                .buttonStyle(.plain)
                .disabled(!chat.canSend)
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }
}

/// Nutzerkarte: Verlauf und Moderation (löschen, Timeout, Bann, aufheben, antworten).
struct ChatUserSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var history: [ChatLine] = []

    var body: some View {
        let chat = session.chat
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text(message.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.chatName(message.color))
                    if message.months > 0 {
                        Text("\(message.months) Monate Abo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.input, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if session.can(.moderateChat) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        modButton("Antworten", symbol: "arrowshape.turn.up.left", tone: Palette.text) {
                            chat.replyTo = message
                        }
                        modButton("Löschen", symbol: "trash", tone: Palette.orange) {
                            Task { await chat.moderate(message, action: "delete") }
                        }
                        modButton("Timeout 10 min", symbol: "timer", tone: Palette.orange) {
                            Task { await chat.moderate(message, action: "timeout", seconds: 600) }
                        }
                        modButton("Timeout 1 h", symbol: "timer", tone: Palette.orange) {
                            Task { await chat.moderate(message, action: "timeout", seconds: 3600) }
                        }
                        modButton("Bannen", symbol: "nosign", tone: Palette.red) {
                            Task { await chat.moderate(message, action: "ban") }
                        }
                        modButton("Aufheben", symbol: "arrow.uturn.backward", tone: Palette.green) {
                            Task { await chat.moderate(message, action: "unban") }
                        }
                    }
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verlauf")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textMuted)
                        ForEach(history) { line in
                            ChatLineView(line: line)
                        }
                    }
                }
            }
            .padding(22)
        }
        .task {
            history = await chat.history(for: message)
        }
    }

    private func modButton(_ title: String, symbol: String, tone: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PultKeyStyle(tone: tone, compact: true))
    }
}

