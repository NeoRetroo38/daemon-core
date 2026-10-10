#if os(macOS)
import DaemonKit
import XCTest

/// #81: cada respuesta dice de dónde sale (LOCAL · LLM · TOOLS) y el fallback nunca es silencioso.
final class ReplyModeTests: XCTestCase {
    func testLocalVoiceWithoutTools() {
        XCTAssertEqual(ChatMessage(role: .daemon, text: "", engine: "local").modeLabel, "LOCAL")
    }

    func testLLMWithToolsIgnoresInternalLLMTag() {
        let message = ChatMessage(role: .daemon, text: "", tools: ["llm:modelo", "repo.list"], engine: "modelo")
        XCTAssertEqual(message.modeLabel, "LLM · TOOLS")
        XCTAssertEqual(ChatMessage(role: .daemon, text: "", tools: ["llm:modelo"], engine: "modelo").modeLabel, "LLM")
    }

    func testFallbackIsVisibleAndNeverNamesProvider() {
        var message = ChatMessage(role: .daemon, text: "", tools: ["repo.list"], engine: "local")
        message.fallback = true
        XCTAssertEqual(message.modeLabel, "LOCAL · TOOLS · LLM no disponible")
        XCTAssertFalse(message.modeLabel.localizedCaseInsensitiveContains("claude"))
    }
}
#endif
