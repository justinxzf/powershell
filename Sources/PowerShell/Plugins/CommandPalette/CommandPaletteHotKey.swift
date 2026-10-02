import AppKit
import Carbon.HIToolbox

/// In a non-fullscreen window macOS turns ⌘H into an app-hide event outside the normal
/// keyDown path, so swallowing the keyDown is not enough — the key must be claimed as a
/// Carbon hot key. Hot keys are system-wide, so it is only held while this app is active.
@MainActor
final class CommandPaletteHotKey {
    static let shared = CommandPaletteHotKey()

    private final class WeakPlugin {
        weak var plugin: CommandPalettePlugin?
        init(_ plugin: CommandPalettePlugin) { self.plugin = plugin }
    }

    private var plugins: [WeakPlugin] = []
    private var hotKeyRef: EventHotKeyRef?
    private var started = false

    func add(_ plugin: CommandPalettePlugin) {
        plugins.append(WeakPlugin(plugin))
        start()
    }

    private func start() {
        guard !started else { return }
        started = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { CommandPaletteHotKey.shared.handlePress() }
            return noErr
        }, 1, &spec, nil, nil)

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CommandPaletteHotKey.shared.register() }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CommandPaletteHotKey.shared.unregister() }
        }
        // NSApp is still nil when the Settings plugin host is built during App init.
        if NSApp?.isActive == true { register() }
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: OSType(0x5053_4350), id: 1) // 'PSCP'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            DebugLog.write("[CommandPalette] RegisterEventHotKey(⌘H) failed: \(status)")
        }
    }

    private func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    private func handlePress() {
        plugins.removeAll { $0.plugin == nil }
        for entry in plugins where entry.plugin?.handleHotKey() == true {
            return
        }
        NSApp.hide(nil)
    }
}
