import SwiftUI
import UIKit

/// Farben wie in der TESS App (Stagecraft CI: Canvas, Surface, Text, Forest als einziger Akzent), dazu die drei Freigabe Farben
/// von videos.stagecraft.media. Quelle: TESS_APP/TESS/Views/Palette.swift, bei Änderungen dort mitziehen.
enum Palette {
    static let canvas = dynamic(light: 0xF6F6F3, dark: 0x1E1E1C)
    static let surface = dynamic(light: 0xEDEDE8, dark: 0x2B2B2B)
    static let text = dynamic(light: 0x292929, dark: 0xF6F6F3)
    static let forest = Color(UIColor(hex: 0x48514A))
    static let accent = dynamic(light: 0x48514A, dark: 0xB3C1B5)
    static let forestLight = Color(UIColor(hex: 0x7C887E))
    static let warning = dynamic(light: 0xA8641C, dark: 0xE0A15C)
    /// Rot wie überfällige Fristen in der TESS App: Zahlen auf Schaltern, Löschen
    static let overdue = dynamic(light: 0xC92A14, dark: 0xFF7D66)
    /// Weiße Karten und Felder auf dem Canvas
    static let field = dynamic(light: 0xFDFDFC, dark: 0x2A2A28)
    static let line = text.opacity(0.10)
    static let muted = text.opacity(0.55)
    static let faint = text.opacity(0.36)

    /// Bühne des Players, immer dunkel wie auf videos.stagecraft.media
    static let stage = Color(UIColor(hex: 0x0B0B0A))
    static let stagePanel = Color(UIColor(hex: 0x171716))

    /// Freigabe wie auf der Videoseite (projekt.html, STATUS)
    static let pending = Color(UIColor(hex: 0xD9C3A5))
    static let changes = Color(UIColor(hex: 0xC4855A))
    static let approved = Color(UIColor(hex: 0x93AA98))
    /// Auf hellem Grund etwas kräftiger, damit Punkte und Balken lesbar bleiben
    static let approvedInk = dynamic(light: 0x5F8068, dark: 0x93AA98)
    static let changesInk = dynamic(light: 0xA8663C, dark: 0xD9996D)
    static let pendingInk = dynamic(light: 0xB79A73, dark: 0xD9C3A5)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Kleine Labels: Systemschrift halbfett, nie Mono, nie Großbuchstaben (TESS Glas Design)
    static let label = Font.system(size: 13, weight: .semibold)
    static let pageTitle = Font.system(size: 34, weight: .bold)
}

/// Kunden Farben wie im Admin Dashboard (admin.html: KUNDEN_FARBEN, kundeFarbe, kuerzel)
enum CustomerTone {
    private static let tones: [(UInt32, UInt32)] = [(0x48514A, 0xFFFFFF), (0x8F6E4E, 0xFFFFFF), (0x6F8574, 0xFFFFFF),
                                                    (0xC4855A, 0xFFFFFF), (0x5E6B73, 0xFFFFFF)]

    static func colors(for name: String) -> (fill: Color, text: Color) {
        if name.lowercased() == "stagecraft" { return (Color(UIColor(hex: 0xE8DDD0)), Color(UIColor(hex: 0x1E1E1C))) }
        var h: UInt32 = 0
        for scalar in name.unicodeScalars { h = h &* 31 &+ scalar.value }
        let tone = tones[Int(h % UInt32(tones.count))]
        return (Color(UIColor(hex: tone.0)), Color(UIColor(hex: tone.1)))
    }

    static func initials(_ name: String) -> String {
        if name.lowercased() == "stagecraft" { return "SC" }
        let words = name.split(whereSeparator: { $0 == " " }).prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }
}
