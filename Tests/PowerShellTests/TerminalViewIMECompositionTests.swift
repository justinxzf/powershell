import XCTest
import AppKit
import SwiftTerm
@testable import PowerShell

@MainActor
final class TerminalViewIMECompositionTests: XCTestCase {
    func testSetMarkedTextLongerReplacementPreservesTrailingCharactersWithinLine() {
        let (view, terminal) = makeTerminalView()

        terminal.feed(text: "abcdef")
        terminal.feed(text: "\u{1b}[3G")
        applyMarkedTextUpdate(to: view, finalText: "1234567890")

        XCTAssertEqual(renderedText(from: terminal, rows: 0...0), "ab1234567890cdef")
    }

    func testSetMarkedTextThatWouldReflowWrappedLineDoesNotMutateDisplayBuffer() {
        let (view, terminal) = makeWrappedTerminalView()

        applyMarkedTextUpdate(to: view, finalText: "1234567890")

        XCTAssertEqual(renderedText(from: terminal, rows: 0...2), "abcdefghijKLMNOP")
        XCTAssertTrue(view.hasMarkedText())
    }

    func testInsertTextAfterWrappedMarkedTextClearsCompositionWithoutMutatingDisplayBuffer() {
        let (view, terminal) = makeWrappedTerminalView()

        applyMarkedTextUpdate(to: view, finalText: "1234567890")
        view.insertText("1234567890", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(renderedText(from: terminal, rows: 0...2), "abcdefghijKLMNOP")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testInsertTextWithoutMarkedTextSendsBytesToShellInsteadOfMutatingDisplayBuffer() {
        let (view, terminal) = makeWrappedTerminalView()

        view.insertText("1234567890", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(renderedText(from: terminal, rows: 0...2), "abcdefghijKLMNOP")
        XCTAssertEqual(terminal.buffer.x, 5)
        XCTAssertEqual(terminal.buffer.y, 1)
    }

    private func makeTerminalView() -> (view: InterceptingTerminalView, terminal: Terminal) {
        let view = InterceptingTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        return (view, view.terminal!)
    }

    private func makeWrappedTerminalView() -> (view: InterceptingTerminalView, terminal: Terminal) {
        let (view, terminal) = makeTerminalView()
        terminal.resize(cols: 10, rows: 5)
        terminal.feed(text: "abcdefghijKLMNOP")
        terminal.feed(text: "\u{1b}[6G")
        return (view, terminal)
    }

    private func applyMarkedTextUpdate(to view: InterceptingTerminalView, finalText: String) {
        view.setMarkedText("12", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 0))
        view.setMarkedText(finalText, selectedRange: NSRange(location: finalText.count, length: 0), replacementRange: NSRange(location: 0, length: 2))
    }

    private func renderedText(from terminal: Terminal, rows: ClosedRange<Int>) -> String {
        rows.map {
            terminal.getLine(row: $0)!.translateToString(trimRight: true, characterProvider: { terminal.getCharacter(for: $0) })
        }.joined()
    }
}
