import XCTest
@testable import PowerShell

final class ShellHistoryParserTests: XCTestCase {
    func testZshExtendedFormatNewestFirst() {
        let data = Data(": 1700000000:0;ls -la\n: 1700000001:0;git status\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .zsh), ["git status", "ls -la"])
    }

    func testZshPlainFormat() {
        let data = Data("ls\npwd\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .zsh), ["pwd", "ls"])
    }

    func testZshMultilineCommandIsExcluded() {
        let data = Data(": 1:0;echo a \\\n  b\n: 2:0;pwd\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .zsh), ["pwd"])
    }

    func testZshUnmetafiesNonASCII() {
        // zsh stores bytes in 0x83...0xA2 as 0x83 followed by (byte ^ 0x20).
        // "文" is E6 96 87, so its last two bytes get metafied.
        var bytes = Array(": 1:0;echo ".utf8)
        for b in Array("文".utf8) {
            if (0x83...0xA2).contains(b) {
                bytes.append(0x83)
                bytes.append(b ^ 0x20)
            } else {
                bytes.append(b)
            }
        }
        bytes.append(0x0A)
        XCTAssertEqual(ShellHistoryParser.parse(Data(bytes), shell: .zsh), ["echo 文"])
    }

    func testBashSkipsTimestampLines() {
        let data = Data("#1700000000\nmake\n#1700000001\nmake test\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .bash), ["make test", "make"])
    }

    func testDeduplicatesKeepingMostRecent() {
        let data = Data("a\nb\na\n  \nc\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .bash), ["c", "a", "b"])
    }

    func testRespectsLimit() {
        let data = Data((1...10).map { "cmd\($0)" }.joined(separator: "\n").utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .bash, limit: 3), ["cmd10", "cmd9", "cmd8"])
    }

    func testDropsPartialFirstLineWhenTruncated() {
        let data = Data("tial-garbage\nls\n".utf8)
        XCTAssertEqual(ShellHistoryParser.parse(data, shell: .bash, isTruncated: true), ["ls"])
    }
}
