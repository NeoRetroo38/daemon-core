import DaemonKit
import XCTest

final class TailnetPingTests: XCTestCase {
    func testParsesDirectAndRelayedPongs() {
        XCTAssertEqual(TailnetParser.pingMilliseconds("pong from desktop (100.1.2.3) via 192.168.1.5:41641 in 3ms"), 3)
        XCTAssertEqual(TailnetParser.pingMilliseconds("pong from iphone (100.1.2.4) via DERP(mad) in 27.6ms"), 28)
    }

    func testTimeoutHasNoLatency() {
        XCTAssertNil(TailnetParser.pingMilliseconds("ping \"100.1.2.3\" timed out"))
    }
}
