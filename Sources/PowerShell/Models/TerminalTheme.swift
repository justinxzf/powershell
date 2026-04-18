import AppKit
import SwiftTerm

enum ThemeAppearance: String, CaseIterable {
    case dark
    case light

    var isDark: Bool { self == .dark }
}

struct ThemeColor: Equatable {
    let r: UInt8, g: UInt8, b: UInt8

    var nsColor: NSColor {
        NSColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    var swiftTermColor: SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(r) * 257, green: UInt16(g) * 257, blue: UInt16(b) * 257)
    }
}

struct TerminalTheme: Identifiable, Equatable {
    let id: String
    let displayName: String
    let appearance: ThemeAppearance
    let background: ThemeColor
    let foreground: ThemeColor
    let ansiColors: [ThemeColor]
    let accent: ThemeColor

    var nsBackgroundColor: NSColor { background.nsColor }
    var nsForegroundColor: NSColor { foreground.nsColor }
    var nsAccentColor: NSColor { accent.nsColor }

    var swiftTermAnsiColors: [SwiftTerm.Color] {
        ansiColors.map(\.swiftTermColor)
    }

    static let defaultTheme = allThemes[0]

    static let allThemes: [TerminalTheme] = [
        .defaultDark, .defaultLight, .dracula, .solarizedDark,
        .solarizedLight, .monokai, .oneDark, .nord,
    ]
}

// MARK: - Preset Themes

extension TerminalTheme {
    static let defaultDark = TerminalTheme(
        id: "default_dark",
        displayName: "深色",
        appearance: .dark,
        background: ThemeColor(r: 0x1F, g: 0x1F, b: 0x1F),
        foreground: ThemeColor(r: 0xCC, g: 0xCC, b: 0xCC),
        ansiColors: [
            ThemeColor(r: 0x00, g: 0x00, b: 0x00), ThemeColor(r: 0xC2, g: 0x36, b: 0x21),
            ThemeColor(r: 0x25, g: 0xBC, b: 0x24), ThemeColor(r: 0xAD, g: 0xAD, b: 0x27),
            ThemeColor(r: 0x49, g: 0x2E, b: 0xE1), ThemeColor(r: 0xD3, g: 0x38, b: 0xD3),
            ThemeColor(r: 0x33, g: 0xBB, b: 0xC8), ThemeColor(r: 0xCB, g: 0xCC, b: 0xCD),
            ThemeColor(r: 0x81, g: 0x83, b: 0x83), ThemeColor(r: 0xFC, g: 0x39, b: 0x1F),
            ThemeColor(r: 0x31, g: 0xE7, b: 0x22), ThemeColor(r: 0xEA, g: 0xEC, b: 0x23),
            ThemeColor(r: 0x58, g: 0x33, b: 0xFF), ThemeColor(r: 0xF9, g: 0x35, b: 0xF8),
            ThemeColor(r: 0x14, g: 0xF0, b: 0xF0), ThemeColor(r: 0xE9, g: 0xEB, b: 0xEB),
        ],
        accent: ThemeColor(r: 0x4A, g: 0x9F, b: 0xD9)
    )

    static let defaultLight = TerminalTheme(
        id: "default_light",
        displayName: "浅色",
        appearance: .light,
        background: ThemeColor(r: 0xFF, g: 0xFF, b: 0xFF),
        foreground: ThemeColor(r: 0x33, g: 0x33, b: 0x33),
        ansiColors: [
            ThemeColor(r: 0x00, g: 0x00, b: 0x00), ThemeColor(r: 0x9E, g: 0x18, b: 0x1A),
            ThemeColor(r: 0x00, g: 0x64, b: 0x00), ThemeColor(r: 0x8B, g: 0x6E, b: 0x00),
            ThemeColor(r: 0x00, g: 0x1D, b: 0xB3), ThemeColor(r: 0x8B, g: 0x1A, b: 0x8B),
            ThemeColor(r: 0x00, g: 0x6E, b: 0x6E), ThemeColor(r: 0x66, g: 0x66, b: 0x66),
            ThemeColor(r: 0x80, g: 0x80, b: 0x80), ThemeColor(r: 0xE0, g: 0x2B, b: 0x2B),
            ThemeColor(r: 0x00, g: 0x8B, b: 0x00), ThemeColor(r: 0xB5, g: 0x9A, b: 0x00),
            ThemeColor(r: 0x00, g: 0x3B, b: 0xE6), ThemeColor(r: 0xB2, g: 0x26, b: 0xB2),
            ThemeColor(r: 0x00, g: 0x8B, b: 0x8B), ThemeColor(r: 0x99, g: 0x99, b: 0x99),
        ],
        accent: ThemeColor(r: 0x00, g: 0x65, b: 0xD1)
    )

    static let dracula = TerminalTheme(
        id: "dracula",
        displayName: "Dracula",
        appearance: .dark,
        background: ThemeColor(r: 0x28, g: 0x2A, b: 0x36),
        foreground: ThemeColor(r: 0xF8, g: 0xF8, b: 0xF2),
        ansiColors: [
            ThemeColor(r: 0x21, g: 0x22, b: 0x2C), ThemeColor(r: 0xFF, g: 0x55, b: 0x55),
            ThemeColor(r: 0x50, g: 0xFA, b: 0x7B), ThemeColor(r: 0xF1, g: 0xFA, b: 0x8C),
            ThemeColor(r: 0xBD, g: 0x93, b: 0xF9), ThemeColor(r: 0xFF, g: 0x79, b: 0xC6),
            ThemeColor(r: 0x8B, g: 0xE9, b: 0xFD), ThemeColor(r: 0xF8, g: 0xF8, b: 0xF2),
            ThemeColor(r: 0x62, g: 0x72, b: 0xA4), ThemeColor(r: 0xFF, g: 0x6E, b: 0x6E),
            ThemeColor(r: 0x69, g: 0xFF, b: 0x94), ThemeColor(r: 0xFF, g: 0xFF, b: 0xA5),
            ThemeColor(r: 0xD6, g: 0xAC, b: 0xFF), ThemeColor(r: 0xFF, g: 0x92, b: 0xDF),
            ThemeColor(r: 0xA4, g: 0xFF, b: 0xFF), ThemeColor(r: 0xFF, g: 0xFF, b: 0xFF),
        ],
        accent: ThemeColor(r: 0xBD, g: 0x93, b: 0xF9)
    )

    static let solarizedDark = TerminalTheme(
        id: "solarized_dark",
        displayName: "Solarized Dark",
        appearance: .dark,
        background: ThemeColor(r: 0x00, g: 0x2B, b: 0x36),
        foreground: ThemeColor(r: 0x83, g: 0x94, b: 0x96),
        ansiColors: [
            ThemeColor(r: 0x07, g: 0x36, b: 0x42), ThemeColor(r: 0xDC, g: 0x32, b: 0x2F),
            ThemeColor(r: 0x85, g: 0x99, b: 0x00), ThemeColor(r: 0xB5, g: 0x89, b: 0x00),
            ThemeColor(r: 0x26, g: 0x8B, b: 0xD2), ThemeColor(r: 0xD3, g: 0x36, b: 0x82),
            ThemeColor(r: 0x2A, g: 0xA1, b: 0x98), ThemeColor(r: 0xEE, g: 0xE8, b: 0xD5),
            ThemeColor(r: 0x00, g: 0x2B, b: 0x36), ThemeColor(r: 0xCB, g: 0x4B, b: 0x16),
            ThemeColor(r: 0x58, g: 0x6E, b: 0x75), ThemeColor(r: 0x65, g: 0x7B, b: 0x83),
            ThemeColor(r: 0x83, g: 0x94, b: 0x96), ThemeColor(r: 0x6C, g: 0x71, b: 0xC4),
            ThemeColor(r: 0x93, g: 0xA1, b: 0xA1), ThemeColor(r: 0xFD, g: 0xF6, b: 0xE3),
        ],
        accent: ThemeColor(r: 0x26, g: 0x8B, b: 0xD2)
    )

    static let solarizedLight = TerminalTheme(
        id: "solarized_light",
        displayName: "Solarized Light",
        appearance: .light,
        background: ThemeColor(r: 0xFD, g: 0xF6, b: 0xE3),
        foreground: ThemeColor(r: 0x65, g: 0x7B, b: 0x83),
        ansiColors: [
            ThemeColor(r: 0xEE, g: 0xE8, b: 0xD5), ThemeColor(r: 0xDC, g: 0x32, b: 0x2F),
            ThemeColor(r: 0x85, g: 0x99, b: 0x00), ThemeColor(r: 0xB5, g: 0x89, b: 0x00),
            ThemeColor(r: 0x26, g: 0x8B, b: 0xD2), ThemeColor(r: 0xD3, g: 0x36, b: 0x82),
            ThemeColor(r: 0x2A, g: 0xA1, b: 0x98), ThemeColor(r: 0x07, g: 0x36, b: 0x42),
            ThemeColor(r: 0xFD, g: 0xF6, b: 0xE3), ThemeColor(r: 0xCB, g: 0x4B, b: 0x16),
            ThemeColor(r: 0x93, g: 0xA1, b: 0xA1), ThemeColor(r: 0x83, g: 0x94, b: 0x96),
            ThemeColor(r: 0x65, g: 0x7B, b: 0x83), ThemeColor(r: 0x6C, g: 0x71, b: 0xC4),
            ThemeColor(r: 0x58, g: 0x6E, b: 0x75), ThemeColor(r: 0x00, g: 0x2B, b: 0x36),
        ],
        accent: ThemeColor(r: 0x26, g: 0x8B, b: 0xD2)
    )

    static let monokai = TerminalTheme(
        id: "monokai",
        displayName: "Monokai",
        appearance: .dark,
        background: ThemeColor(r: 0x27, g: 0x28, b: 0x22),
        foreground: ThemeColor(r: 0xF8, g: 0xF8, b: 0xF2),
        ansiColors: [
            ThemeColor(r: 0x27, g: 0x28, b: 0x22), ThemeColor(r: 0xF9, g: 0x26, b: 0x72),
            ThemeColor(r: 0xA6, g: 0xE2, b: 0x2E), ThemeColor(r: 0xF4, g: 0xBF, b: 0x75),
            ThemeColor(r: 0x66, g: 0xD9, b: 0xEF), ThemeColor(r: 0xAE, g: 0x81, b: 0xFF),
            ThemeColor(r: 0xA1, g: 0xEF, b: 0xE4), ThemeColor(r: 0xF8, g: 0xF8, b: 0xF2),
            ThemeColor(r: 0x75, g: 0x71, b: 0x5E), ThemeColor(r: 0xFD, g: 0x97, b: 0x1F),
            ThemeColor(r: 0xA6, g: 0xE2, b: 0x2E), ThemeColor(r: 0xE6, g: 0xDB, b: 0x74),
            ThemeColor(r: 0x66, g: 0xD9, b: 0xEF), ThemeColor(r: 0xAE, g: 0x81, b: 0xFF),
            ThemeColor(r: 0xA1, g: 0xEF, b: 0xE4), ThemeColor(r: 0xF9, g: 0xF8, b: 0xF5),
        ],
        accent: ThemeColor(r: 0xA6, g: 0xE2, b: 0x2E)
    )

    static let oneDark = TerminalTheme(
        id: "one_dark",
        displayName: "One Dark",
        appearance: .dark,
        background: ThemeColor(r: 0x28, g: 0x2C, b: 0x34),
        foreground: ThemeColor(r: 0xAB, g: 0xB2, b: 0xBF),
        ansiColors: [
            ThemeColor(r: 0x28, g: 0x2C, b: 0x34), ThemeColor(r: 0xE0, g: 0x6C, b: 0x75),
            ThemeColor(r: 0x98, g: 0xC3, b: 0x79), ThemeColor(r: 0xE5, g: 0xC0, b: 0x7B),
            ThemeColor(r: 0x61, g: 0xAF, b: 0xEF), ThemeColor(r: 0xC6, g: 0x78, b: 0xDD),
            ThemeColor(r: 0x56, g: 0xB6, b: 0xC2), ThemeColor(r: 0xAB, g: 0xB2, b: 0xBF),
            ThemeColor(r: 0x5C, g: 0x63, b: 0x70), ThemeColor(r: 0xE0, g: 0x6C, b: 0x75),
            ThemeColor(r: 0x98, g: 0xC3, b: 0x79), ThemeColor(r: 0xE5, g: 0xC0, b: 0x7B),
            ThemeColor(r: 0x61, g: 0xAF, b: 0xEF), ThemeColor(r: 0xC6, g: 0x78, b: 0xDD),
            ThemeColor(r: 0x56, g: 0xB6, b: 0xC2), ThemeColor(r: 0xFF, g: 0xFF, b: 0xFF),
        ],
        accent: ThemeColor(r: 0x61, g: 0xAF, b: 0xEF)
    )

    static let nord = TerminalTheme(
        id: "nord",
        displayName: "Nord",
        appearance: .dark,
        background: ThemeColor(r: 0x2E, g: 0x34, b: 0x40),
        foreground: ThemeColor(r: 0xD8, g: 0xDE, b: 0xE9),
        ansiColors: [
            ThemeColor(r: 0x3B, g: 0x42, b: 0x52), ThemeColor(r: 0xBF, g: 0x61, b: 0x6A),
            ThemeColor(r: 0xA3, g: 0xBE, b: 0x8C), ThemeColor(r: 0xEB, g: 0xCB, b: 0x8B),
            ThemeColor(r: 0x81, g: 0xA1, b: 0xC1), ThemeColor(r: 0xB4, g: 0x8E, b: 0xAD),
            ThemeColor(r: 0x88, g: 0xC0, b: 0xD0), ThemeColor(r: 0xE5, g: 0xE9, b: 0xF0),
            ThemeColor(r: 0x4C, g: 0x56, b: 0x6A), ThemeColor(r: 0xBF, g: 0x61, b: 0x6A),
            ThemeColor(r: 0xA3, g: 0xBE, b: 0x8C), ThemeColor(r: 0xEB, g: 0xCB, b: 0x8B),
            ThemeColor(r: 0x81, g: 0xA1, b: 0xC1), ThemeColor(r: 0xB4, g: 0x8E, b: 0xAD),
            ThemeColor(r: 0x8F, g: 0xBC, b: 0xBB), ThemeColor(r: 0xEC, g: 0xEF, b: 0xF4),
        ],
        accent: ThemeColor(r: 0x88, g: 0xC0, b: 0xD0)
    )
}
