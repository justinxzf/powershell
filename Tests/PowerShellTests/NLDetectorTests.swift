import XCTest
@testable import PowerShell

final class NLDetectorTests: XCTestCase {
    func testKnownCommands() {
        XCTAssertEqual(NLDetector.detect("ls -la"), .command)
        XCTAssertEqual(NLDetector.detect("cd ~/Documents"), .command)
        XCTAssertEqual(NLDetector.detect("git status"), .command)
        XCTAssertEqual(NLDetector.detect("npm install"), .command)
        XCTAssertEqual(NLDetector.detect("make build"), .command)
        XCTAssertEqual(NLDetector.detect("docker ps"), .command)
    }

    func testShellSyntax() {
        XCTAssertEqual(NLDetector.detect("ls | grep foo"), .command)
        XCTAssertEqual(NLDetector.detect("echo $HOME"), .command)
        XCTAssertEqual(NLDetector.detect("cat file > output"), .command)
        XCTAssertEqual(NLDetector.detect("make && make test"), .command)
        XCTAssertEqual(NLDetector.detect("./run.sh"), .command)
    }

    func testChineseInput() {
        XCTAssertEqual(NLDetector.detect("找出所有大于100MB的文件"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("查看当前目录结构"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("删除临时文件"), .naturalLanguage)
    }

    func testEnglishNL() {
        XCTAssertEqual(NLDetector.detect("how to find large files"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("find all pdf files"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("show me running processes"), .naturalLanguage)
    }

    func testDefaultCommand() {
        XCTAssertEqual(NLDetector.detect("hello"), .command)
        XCTAssertEqual(NLDetector.detect(""), .command)
    }
}
