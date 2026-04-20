import XCTest

final class BuildDMGScriptTests: XCTestCase {
    func testBuildDMGScriptPackagesSwiftPMResourceBundle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("Scripts/build_dmg.sh")
        let appBundleURL = repositoryRoot.appendingPathComponent("dist/PowerShell.app")
        let resourceBundleURL = appBundleURL.appendingPathComponent("Contents/Resources/PowerShell_PowerShell.bundle")

        try? FileManager.default.removeItem(at: appBundleURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0, "build_dmg.sh failed:\n\(output)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resourceBundleURL.path),
            "Expected packaged app to include SwiftPM resource bundle at \(resourceBundleURL.path). Output:\n\(output)"
        )
    }
}
