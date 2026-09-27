import XCTest
@testable import HIDCore

final class SessionStateMachineTests: XCTestCase {
    func testConnectFlowEndsInLocalMode() {
        var machine = SessionStateMachine()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.connectRequested), [])
        XCTAssertEqual(machine.state, .connecting)
        XCTAssertEqual(machine.handle(.transportConnected), [.showHUD(.connected)])
        XCTAssertEqual(machine.state, .connectedLocal)
    }

    func testToggleSwitchesToRemoteAndBack() {
        var machine = SessionStateMachine(state: .connectedLocal)
        XCTAssertEqual(machine.handle(.toggleRequested), [.lockCursor, .showHUD(.remote)])
        XCTAssertEqual(machine.state, .connectedRemote)
        XCTAssertEqual(machine.handle(.toggleRequested), [.sendAllUp, .unlockCursor, .showHUD(.local)])
        XCTAssertEqual(machine.state, .connectedLocal)
    }

    func testToggleWhileNotConnectedDoesNothing() {
        var machine = SessionStateMachine(state: .idle)
        XCTAssertEqual(machine.handle(.toggleRequested), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testDisconnectInRemoteModeReleasesLocalControl() {
        var machine = SessionStateMachine(state: .connectedRemote)
        XCTAssertEqual(machine.handle(.transportDisconnected), [.unlockCursor, .showHUD(.disconnected)])
        XCTAssertEqual(machine.state, .disconnected)
    }

    func testEscapeHatchEventsForceLocal() {
        for event in [SessionEvent.screenLocked, .appWillTerminate] {
            var machine = SessionStateMachine(state: .connectedRemote)
            let effects = machine.handle(event)
            XCTAssertTrue(effects.contains(.unlockCursor), "\(event)")
            XCTAssertTrue(effects.contains(.sendAllUp), "\(event)")
            XCTAssertEqual(machine.state, .connectedLocal)
        }
    }

    func testStopFromAnyStateReturnsToIdle() {
        var machine = SessionStateMachine(state: .connectedRemote)
        let effects = machine.handle(.stopRequested)
        XCTAssertTrue(effects.contains(.unlockCursor))
        XCTAssertEqual(machine.state, .idle)
    }
}

final class SessionStateMachineInboundTests: XCTestCase {
    func testHostInitiatedConnectionFromIdleGoesToLocal() {
        var machine = SessionStateMachine(state: .idle)
        XCTAssertEqual(machine.handle(.transportConnected), [.showHUD(.connected)])
        XCTAssertEqual(machine.state, .connectedLocal)
    }

    func testConnectRequestWhileAlreadyConnectingIsIgnored() {
        var machine = SessionStateMachine(state: .connecting)
        XCTAssertEqual(machine.handle(.connectRequested), [])
        XCTAssertEqual(machine.state, .connecting)
    }

    func testRetryFromDisconnectedReturnsToConnecting() {
        var machine = SessionStateMachine(state: .disconnected)
        XCTAssertEqual(machine.handle(.connectRequested), [])
        XCTAssertEqual(machine.state, .connecting)
    }

    func testDisconnectedWhileIdleStaysIdle() {
        var machine = SessionStateMachine(state: .idle)
        XCTAssertEqual(machine.handle(.transportDisconnected), [])
        XCTAssertEqual(machine.state, .idle)
    }
}

final class RemoteResumePolicyTests: XCTestCase {
    func testResumesWhenLinkDroppedWhileRemoteAndReconnectedSoon() {
        var policy = RemoteResumePolicy(window: 600)
        policy.linkDropped(wasCapturing: true, at: 1_000)
        XCTAssertTrue(policy.shouldResume(at: 1_100))
    }

    func testDoesNotResumeAfterTheWindowOrWhenUserWasLocal() {
        var policy = RemoteResumePolicy(window: 600)
        policy.linkDropped(wasCapturing: true, at: 1_000)
        XCTAssertFalse(policy.shouldResume(at: 1_700))
        policy.linkDropped(wasCapturing: false, at: 2_000)
        XCTAssertFalse(policy.shouldResume(at: 2_001))
    }

    func testUserActionClearsThePendingResume() {
        var policy = RemoteResumePolicy(window: 600)
        policy.linkDropped(wasCapturing: true, at: 1_000)
        policy.clear()
        XCTAssertFalse(policy.shouldResume(at: 1_001))
    }

    func testResumeIsConsumedOnce() {
        var policy = RemoteResumePolicy(window: 600)
        policy.linkDropped(wasCapturing: true, at: 1_000)
        XCTAssertTrue(policy.shouldResume(at: 1_001))
        XCTAssertFalse(policy.shouldResume(at: 1_002))
    }
}
