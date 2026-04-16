import XCTest
@testable import PowerShell

final class KeychainServiceTests: XCTestCase {
    private let testKey = "test-api-key-\(UUID().uuidString)"

    override func tearDown() {
        KeychainService.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        let value = "sk-test-1234567890"
        try KeychainService.save(key: testKey, value: value)
        let loaded = try KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, value)
    }

    func testLoadNonexistentKeyThrows() {
        XCTAssertThrowsError(try KeychainService.load(key: "nonexistent-key-\(UUID().uuidString)"))
    }

    func testDeleteRemovesKey() throws {
        try KeychainService.save(key: testKey, value: "temp")
        KeychainService.delete(key: testKey)
        XCTAssertThrowsError(try KeychainService.load(key: testKey))
    }

    func testSaveOverwrites() throws {
        try KeychainService.save(key: testKey, value: "old-value")
        try KeychainService.save(key: testKey, value: "new-value")
        let loaded = try KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, "new-value")
    }
}
