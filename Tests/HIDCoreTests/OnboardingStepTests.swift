import XCTest
@testable import HIDCore

final class OnboardingStepTests: XCTestCase {
    func testStepsRunFromWelcomeToFinishInOrder() {
        XCTAssertEqual(OnboardingStep.allCases.first, .welcome)
        XCTAssertEqual(OnboardingStep.allCases.last, .finish)
        XCTAssertEqual(OnboardingStep.welcome.next, .permissions)
        XCTAssertNil(OnboardingStep.finish.next)
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertEqual(OnboardingStep.finish.previous, .inputSource)
    }

    func testInputSourceSetupComesRightAfterConnecting() {
        // The host lists this Mac under Modifier Keys only while it is connected.
        XCTAssertEqual(OnboardingStep.connect.next, .inputSource)
        XCTAssertEqual(OnboardingStep.inputSource.next, .finish)
    }

    func testEveryStepHasCopy() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step)")
            XCTAssertFalse(step.summary.isEmpty, "\(step)")
            XCTAssertFalse(step.symbolName.isEmpty, "\(step)")
        }
    }

    func testProgressIsAFractionOfTheWholeFlow() {
        XCTAssertEqual(OnboardingStep.welcome.progress, 0, accuracy: 0.001)
        XCTAssertEqual(OnboardingStep.finish.progress, 1, accuracy: 0.001)
    }
}
