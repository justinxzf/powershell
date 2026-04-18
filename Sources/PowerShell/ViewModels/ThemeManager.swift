import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor
@Observable
class ThemeManager {
    var currentTheme: TerminalTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "terminal_theme")
        }
    }

    init() {
        let savedId = UserDefaults.standard.string(forKey: "terminal_theme")
        self.currentTheme = TerminalTheme.allThemes.first { $0.id == savedId }
            ?? TerminalTheme.defaultTheme
    }
}
