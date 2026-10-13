import Observation
import SignalwerkKit
import SwiftUI
import UIKit

/// Emotes und Badges als fertig skalierte Bilder, damit eine Chatzeile ein einziger `Text` sein
/// kann (Bilder im Fließtext, Umbruch wie bei Text). Jede Adresse wird je Höhe einmal geladen.
@MainActor
@Observable
final class ChatImageCache {
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private let limit = 500

    /// Bild, falls schon geladen; sonst `nil` und das Laden beginnt (die Zeile zeigt solange den Namen).
    func image(_ url: String, height: CGFloat) -> UIImage? {
        let key = "\(Int(height))|\(url)"
        if let image = images[key] { return image }
        guard !requested.contains(key), let address = URL(string: url) else { return nil }
        requested.insert(key)
        Task { [weak self] in
            guard let loaded = try? await URLSession.shared.data(from: address),
                  let source = UIImage(data: loaded.0)
            else { return }
            let scaled = ChatImageCache.scaled(source, height: height)
            self?.store(scaled, for: key)
        }
        return nil
    }

    private func store(_ image: UIImage, for key: String) {
        images[key] = image
        order.append(key)
        if order.count > limit {
            let old = order.removeFirst()
            images.removeValue(forKey: old)
            requested.remove(old)
        }
    }

    static func scaled(_ image: UIImage, height: CGFloat) -> UIImage {
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = CGSize(width: max(1, (height * ratio).rounded(.up)), height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Baut aus den Stücken einer Nachricht einen einzigen `Text`: Wörter, Emotes als Bilder im
/// Fließtext, Erwähnungen hervorgehoben, Links antippbar.
enum ChatRichText {
    static let emoteHeight: CGFloat = 24
    static let badgeHeight: CGFloat = 16

    @MainActor
    static func text(_ segments: [ChatSegment], images: ChatImageCache, italic: Bool = false, tint: Color? = nil) -> Text {
        var result = Text(verbatim: "")
        for segment in segments {
            switch segment {
            case .text(let value):
                result = result + Text(verbatim: value)
                    .font(.subheadline)
                    .italic(italic)
                    .foregroundStyle(tint ?? Palette.text)
            case .emote(let name, _, let url2, _):
                if let image = images.image(url2, height: emoteHeight) {
                    result = result + Text(Image(uiImage: image)).baselineOffset(-6)
                } else {
                    result = result + Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textMuted)
                }
            case .mention(let value, _):
                result = result + Text(verbatim: value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.amber)
            case .link(let value, let href):
                var attributed = AttributedString(value)
                attributed.link = URL(string: href)
                result = result + Text(attributed)
                    .font(.subheadline)
                    .underline()
            }
        }
        return result
    }

    /// Klartext für VoiceOver: Emotes mit Namen.
    static func plain(_ segments: [ChatSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let value): return value
            case .emote(let name, _, _, _): return name
            case .mention(let value, _): return value
            case .link(let value, _): return value
            }
        }
        .joined()
    }
}
