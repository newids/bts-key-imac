import XCTest
@testable import HIDCore

final class PairingChangeTests: XCTestCase {
    func testDetectsAddedAndRemovedHostsByNormalizedAddress() {
        let before: Set<String> = ["aa-aa-aa-aa-aa-01", "bb-bb-bb-bb-bb-02"]
        let after: Set<String> = ["AA:AA:AA:AA:AA:01", "cc-cc-cc-cc-cc-03"]
        let change = PairingChange(before: before, after: after)
        XCTAssertEqual(change.added, ["cc-cc-cc-cc-cc-03"])
        XCTAssertEqual(change.removed, ["bb-bb-bb-bb-bb-02"])
        XCTAssertFalse(change.isEmpty)
    }

    func testNoChangeIsEmpty() {
        XCTAssertTrue(PairingChange(before: ["a"], after: ["A"]).isEmpty)
    }

    func testFirstSnapshotIsNotReportedAsAdditions() {
        // Before the first snapshot nothing is "new"; the watcher must seed silently.
        let change = PairingChange(before: nil, after: ["aa-aa-aa-aa-aa-01"])
        XCTAssertTrue(change.isEmpty)
    }
}

final class PairingRemovalDebounceTests: XCTestCase {
    func testRemovalNeedsTwoConsecutiveObservations() {
        var debounce = PairingRemovalDebounce()
        XCTAssertEqual(debounce.confirmedRemovals(candidates: ["a"]), [])
        XCTAssertEqual(debounce.confirmedRemovals(candidates: ["a"]), ["a"])
        XCTAssertEqual(debounce.confirmedRemovals(candidates: []), [])
    }

    func testADeviceThatComesBackIsNotRemoved() {
        var debounce = PairingRemovalDebounce()
        _ = debounce.confirmedRemovals(candidates: ["a"])
        XCTAssertEqual(debounce.confirmedRemovals(candidates: []), [])
        XCTAssertEqual(debounce.confirmedRemovals(candidates: ["a"]), [])
    }

    func testAnEmptySnapshotAfterANonEmptyOneIsIgnored() {
        let change = PairingChange(before: ["a", "b"], after: [])
        XCTAssertTrue(change.isEmpty, "an empty list means bluetoothd is unavailable, not that everything was unpaired")
    }
}
