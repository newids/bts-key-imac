import XCTest
@testable import HIDCore

final class HUDPresentationTests: XCTestCase {
    private let context = HUDContext(hostName: "iMac-A", hotkey: "⌥⌘K")

    func testEveryMessageHasATitleAndStaysLongEnoughToRead() {
        let messages: [HUDMessage] = [.connecting(isFirstConnection: false), .connected, .remote, .local, .disconnected(.none), .pairedNewHost("iMac-A")]
        for message in messages {
            let hud = HUDPresentation(message, context: context)
            XCTAssertFalse(hud.title.isEmpty, "\(message)")
            XCTAssertGreaterThanOrEqual(hud.duration, HUDPresentation.minimumDuration, "\(message)")
        }
    }

    func testConnectionChangesStayLongerThanModeSwitches() {
        let modeSwitch = HUDPresentation(.remote, context: context).duration
        XCTAssertGreaterThan(HUDPresentation(.connected, context: context).duration, modeSwitch)
        XCTAssertGreaterThan(HUDPresentation(.disconnected(.waitingForUser), context: context).duration, modeSwitch)
    }

    func testConnectingShowsProgressUntilItIsReplaced() {
        let hud = HUDPresentation(.connecting(isFirstConnection: true), context: context)
        XCTAssertEqual(hud.tone, .progress)
        XCTAssertNil(hud.symbolName, "progress shows a spinner instead of a symbol")
        XCTAssertGreaterThanOrEqual(hud.duration, 20, "covers the transport's connect watchdog")
        XCTAssertTrue(hud.title.contains("iMac-A"))
        XCTAssertEqual(hud.detail, "처음 연결하는 iMac입니다")
    }

    func testDisplayTimes() {
        XCTAssertEqual(HUDPresentation(.remote, context: context).duration, 4)
        XCTAssertEqual(HUDPresentation(.local, context: context).duration, 4)
        XCTAssertEqual(HUDPresentation(.connected, context: context).duration, 6)
        XCTAssertEqual(HUDPresentation(.pairedNewHost("x"), context: context).duration, 6)
        XCTAssertEqual(HUDPresentation(.disconnected(.hostClosed), context: context).duration, 9)
    }

    func testEverythingButProgressCountsDown() {
        XCTAssertFalse(HUDPresentation(.connecting(isFirstConnection: false), context: context).showsCountdown)
        XCTAssertTrue(HUDPresentation(.connected, context: context).showsCountdown)
        XCTAssertTrue(HUDPresentation(.disconnected(.waitingForUser), context: context).showsCountdown)
    }

    func testConnectedTellsHowToSwitchInput() {
        let hud = HUDPresentation(.connected, context: context)
        XCTAssertEqual(hud.tone, .success)
        XCTAssertEqual(hud.detail, "⌥⌘K로 입력을 iMac으로 보냅니다")
    }

    func testDisconnectedSaysWhatHappensNext() {
        XCTAssertEqual(HUDPresentation(.disconnected(.retrying(seconds: 4)), context: context).detail, "4초 뒤 한 번 더 시도합니다")
        XCTAssertEqual(HUDPresentation(.disconnected(.waitingForUser), context: context).detail, "메뉴에서 ‘지금 다시 연결’을 누르세요")
        XCTAssertEqual(HUDPresentation(.disconnected(.hostClosed), context: context).detail, "iMac이 연결을 해제했습니다")
        XCTAssertNil(HUDPresentation(.disconnected(.none), context: context).detail)
        XCTAssertEqual(HUDPresentation(.disconnected(.none), context: context).tone, .warning)
    }

    func testModeSwitchesNameWhereTheKeysGo() {
        XCTAssertEqual(HUDPresentation(.remote, context: context).title, "iMac 입력")
        XCTAssertEqual(HUDPresentation(.remote, context: context).tone, .remote)
        XCTAssertEqual(HUDPresentation(.local, context: context).title, "MacBook 입력")
        XCTAssertEqual(HUDPresentation(.local, context: context).tone, .local)
    }

    func testMissingHostNameFallsBackToAGenericOne() {
        let hud = HUDPresentation(.connecting(isFirstConnection: false), context: HUDContext(hostName: nil, hotkey: "⌥⌘K"))
        XCTAssertTrue(hud.title.contains("iMac"))
    }
}
