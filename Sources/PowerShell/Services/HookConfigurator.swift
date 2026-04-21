import Foundation

@MainActor
final class HookConfigurator {
    static let shared = HookConfigurator()

    private static let hookEvents = ["SessionStart", "SessionEnd", "Notification", "Stop"]
    private static let hookMarker = "powershell-hook"
    private static let hookScriptVersion = 2
    static let autoConfigEnabledKey = "powershell_hook_autoconfig_enabled"

    private var hookScriptURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".powershell/hooks/powershell-hook.sh")
    }

    private var hookScriptDirURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".powershell/hooks")
    }

    private var versionFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".powershell/hooks/.script-version")
    }

    private var settingsJSONURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }

    private var hookCommandPath: String {
        "~/.powershell/hooks/powershell-hook.sh"
    }

    private var hookScriptContent: String {
        """
        #!/bin/bash
        # PowerShell notification hook (v\(Self.hookScriptVersion))
        # Auto-managed by PowerShell app - do not edit manually
        if [ -z "$POWERSHELL_SESSION_ID" ]; then
            exit 0
        fi
        INPUT=$(cat)
        PORT=$(cat ~/.powershell/hook-port 2>/dev/null || echo "9786")
        if command -v python3 &>/dev/null; then
            MODIFIED=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); d['powershell_session_id']='$POWERSHELL_SESSION_ID'; print(json.dumps(d))")
        else
            MODIFIED=$(echo "$INPUT" | sed "s/}$/,\\"powershell_session_id\\":\\"$POWERSHELL_SESSION_ID\\"}/")
        fi
        curl -s -X POST "http://127.0.0.1:$PORT" \\
          -H 'Content-Type: application/json' \\
          -d "$MODIFIED" > /dev/null 2>&1
        """
    }

    var isAutoConfigEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.autoConfigEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: Self.autoConfigEnabledKey)
    }

    func setAutoConfigEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.autoConfigEnabledKey)
        if enabled {
            configureIfNeeded()
        } else {
            cleanup()
        }
    }

    func configureIfNeeded() {
        guard isAutoConfigEnabled else {
            DebugLog.write("[HookConfigurator] auto-config disabled, skipping")
            return
        }

        do {
            try ensureHookScript()
            try ensureHooksInSettings()
            DebugLog.write("[HookConfigurator] configuration complete, scriptVersion=\(Self.hookScriptVersion)")
        } catch {
            DebugLog.write("[HookConfigurator] configuration failed: \(error)")
        }
    }

    // MARK: - Hook Script

    private func ensureHookScript() throws {
        try FileManager.default.createDirectory(
            at: hookScriptDirURL,
            withIntermediateDirectories: true
        )

        let needsWrite: Bool
        if let currentVersion = try? String(contentsOf: versionFileURL, encoding: .utf8),
           Int(currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)) == Self.hookScriptVersion,
           FileManager.default.fileExists(atPath: hookScriptURL.path) {
            needsWrite = false
        } else {
            needsWrite = true
        }

        if needsWrite {
            try hookScriptContent.write(to: hookScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: hookScriptURL.path
            )
            try "\(Self.hookScriptVersion)".write(to: versionFileURL, atomically: true, encoding: .utf8)
            DebugLog.write("[HookConfigurator] hook script written (v\(Self.hookScriptVersion))")
        } else {
            DebugLog.write("[HookConfigurator] hook script up to date")
        }
    }

    // MARK: - Settings JSON

    private func ensureHooksInSettings() throws {
        var settings = try readSettingsJSON()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for eventName in Self.hookEvents {
            var eventEntries = hooks[eventName] as? [[String: Any]] ?? []
            var found = false

            for entryIndex in eventEntries.indices {
                var entry = eventEntries[entryIndex]
                var hookList = entry["hooks"] as? [[String: Any]] ?? []

                for hookIndex in hookList.indices {
                    if isPowerShellHook(hookList[hookIndex]) {
                        hookList[hookIndex] = [
                            "type": "command",
                            "command": hookCommandPath
                        ]
                        found = true
                        break
                    }
                }

                entry["hooks"] = hookList
                eventEntries[entryIndex] = entry
                if found { break }
            }

            if !found {
                let newEntry: [String: Any] = [
                    "hooks": [
                        ["type": "command", "command": hookCommandPath]
                    ]
                ]
                eventEntries.append(newEntry)
            }

            hooks[eventName] = eventEntries
            changed = true
        }

        if changed {
            settings["hooks"] = hooks
            try writeSettingsJSON(settings)
            DebugLog.write("[HookConfigurator] hooks configured in settings.json")
        } else {
            DebugLog.write("[HookConfigurator] hooks already up to date in settings.json")
        }
    }

    private func removeHooksFromSettings() throws {
        var settings = try readSettingsJSON()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for eventName in Self.hookEvents {
            let eventEntries = hooks[eventName] as? [[String: Any]] ?? []
            var cleanedEntries: [[String: Any]] = []
            for entry in eventEntries {
                var hookList = entry["hooks"] as? [[String: Any]] ?? []
                hookList.removeAll { isPowerShellHook($0) }
                if !hookList.isEmpty {
                    var cleanedEntry = entry
                    cleanedEntry["hooks"] = hookList
                    cleanedEntries.append(cleanedEntry)
                }
            }

            if cleanedEntries.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = cleanedEntries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettingsJSON(settings)
        DebugLog.write("[HookConfigurator] PowerShell hooks removed from settings.json")
    }

    private func isPowerShellHook(_ hookDict: [String: Any]) -> Bool {
        guard let command = hookDict["command"] as? String else { return false }
        return command.contains(Self.hookMarker)
    }

    // MARK: - JSON I/O

    private func readSettingsJSON() throws -> [String: Any] {
        let url = settingsJSONURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw HookConfigError.invalidSettingsFormat
        }
        return obj
    }

    private func writeSettingsJSON(_ settings: [String: Any]) throws {
        let url = settingsJSONURL
        let claudeDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.sortedKeys, .prettyPrinted]
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Cleanup

    func cleanup() {
        do {
            try removeHooksFromSettings()
        } catch {
            DebugLog.write("[HookConfigurator] cleanup hooks failed: \(error)")
        }
        try? FileManager.default.removeItem(at: hookScriptURL)
        try? FileManager.default.removeItem(at: versionFileURL)
        DebugLog.write("[HookConfigurator] cleanup complete")
    }
}

enum HookConfigError: LocalizedError {
    case invalidSettingsFormat

    var errorDescription: String? {
        switch self {
        case .invalidSettingsFormat:
            return "~/.claude/settings.json 格式无效，无法自动配置 Hook"
        }
    }
}