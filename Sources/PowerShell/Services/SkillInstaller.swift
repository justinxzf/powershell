import Foundation

struct SkillInstaller {
    private static let claudeSkillsDir = NSString(string: "~/.claude/skills").expandingTildeInPath

    private static var bundleSkillsPath: String? {
        // SPM copies resources into <executable>_<target>.bundle
        let resourcePath = Bundle.main.resourcePath ?? ""
        let directPath = "\(resourcePath)/Skills"
        if FileManager.default.fileExists(atPath: directPath) {
            return directPath
        }
        // SPM resource bundle: PowerShell_PowerShell.bundle/Skills/
        if let bundleUrl = Bundle.main.url(forResource: "Skills", withExtension: nil, subdirectory: "PowerShell_PowerShell.bundle") {
            return bundleUrl.path
        }
        // Fallback: scan for .bundle directories
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
            for item in contents where item.hasSuffix(".bundle") {
                let candidate = "\(resourcePath)/\(item)/Skills"
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    static func installIfNeeded() {
        guard let skillsPath = bundleSkillsPath else {
            DebugLog.write("[SkillInstaller] Skills directory not found in bundle")
            return
        }
        installSkills(fromDirectory: skillsPath)
    }

    static func installIfNeeded(skillsDirectoryPath: String) {
        installSkills(fromDirectory: skillsDirectoryPath)
    }

    private static func installSkills(fromDirectory skillsPath: String) {
        let fm = FileManager.default
        guard let skillDirs = try? fm.contentsOfDirectory(atPath: skillsPath) else {
            DebugLog.write("[SkillInstaller] Cannot read Skills directory at \(skillsPath)")
            return
        }

        for skillName in skillDirs {
            let sourceDir = "\(skillsPath)/\(skillName)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourceDir, isDirectory: &isDir), isDir.boolValue else { continue }

            let sourceSkillFile = "\(sourceDir)/SKILL.md"
            guard fm.fileExists(atPath: sourceSkillFile) else { continue }

            let destDir = "\(claudeSkillsDir)/\(skillName)"
            let destSkillFile = "\(destDir)/SKILL.md"
            let destVersionFile = "\(destDir)/.version"

            let sourceVersion = versionOf(file: sourceSkillFile)

            if let installedVersion = try? String(contentsOfFile: destVersionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               installedVersion == sourceVersion {
                continue
            }

            do {
                if fm.fileExists(atPath: destDir) {
                    try fm.removeItem(atPath: destDir)
                }
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                try fm.copyItem(atPath: sourceSkillFile, toPath: destSkillFile)
                try sourceVersion.write(toFile: destVersionFile, atomically: true, encoding: .utf8)
                DebugLog.write("[SkillInstaller] Installed \(skillName) v\(sourceVersion)")
            } catch {
                DebugLog.write("[SkillInstaller] Failed to install \(skillName): \(error)")
            }
        }
    }

    static func uninstall() {
        let fm = FileManager.default
        guard let skillsPath = bundleSkillsPath,
              let skillDirs = try? fm.contentsOfDirectory(atPath: skillsPath) else { return }

        for skillName in skillDirs {
            let destDir = "\(claudeSkillsDir)/\(skillName)"
            try? fm.removeItem(atPath: destDir)
        }
        DebugLog.write("[SkillInstaller] Uninstalled all PowerShell skills")
    }

    private static func versionOf(file path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return "0"
        }
        return String(Int(modDate.timeIntervalSince1970))
    }
}
