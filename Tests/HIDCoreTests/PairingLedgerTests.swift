import XCTest
@testable import HIDCore

final class PairingLedgerTests: XCTestCase {
    private let imacA = "aa-aa-aa-aa-aa-01"
    private let imacB = "bb-bb-bb-bb-bb-02"

    func testFirstObservationSeedsWithoutReportingAdditions() {
        var ledger = PairingLedger()
        let change = ledger.observe(paired: [imacA], at: 100)
        XCTAssertTrue(change.isEmpty)
        XCTAssertTrue(ledger.isSeeded)
        XCTAssertEqual(ledger.pairedSince(imacA), 0, "age of a pairing that predates tracking is unknown")
    }

    func testPairingThatAppearsLaterIsReportedWithItsTime() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA], at: 100)
        let change = ledger.observe(paired: ["AA:AA:AA:AA:AA:01", "BB:BB:BB:BB:BB:02"], at: 200)
        XCTAssertEqual(change.added, [imacB])
        XCTAssertTrue(change.removed.isEmpty)
        XCTAssertEqual(ledger.pairedSince(imacB), 200)
    }

    func testPairingMadeWhileTheAppWasNotRunningIsReportedAfterRelaunch() throws {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA], at: 100)
        var relaunched = try JSONDecoder().decode(PairingLedger.self, from: JSONEncoder().encode(ledger))
        let change = relaunched.observe(paired: [imacA, imacB], at: 300)
        XCTAssertEqual(change.added, [imacB])
    }

    func testRemovalNeedsTwoConsecutiveObservations() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA, imacB], at: 100)
        XCTAssertTrue(ledger.observe(paired: [imacA], at: 105).isEmpty)
        XCTAssertEqual(ledger.observe(paired: [imacA], at: 110).removed, [imacB])
        XCTAssertNil(ledger.pairedSince(imacB))
    }

    func testHostThatFlickersOutOfOnePartialListIsNotReportedAsNewlyPaired() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA, imacB], at: 100)
        _ = ledger.observe(paired: [imacA], at: 105)
        let change = ledger.observe(paired: [imacA, imacB], at: 110)
        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(ledger.pairedSince(imacB), 0)
    }

    func testEmptyListMeansTheDaemonIsUnavailable() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA], at: 100)
        XCTAssertTrue(ledger.observe(paired: [], at: 105).isEmpty)
        XCTAssertTrue(ledger.observe(paired: [], at: 110).isEmpty)
        XCTAssertEqual(ledger.pairedSince(imacA), 0)
    }

    func testAnEmptyFirstObservationDoesNotSeed() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [], at: 100)
        XCTAssertFalse(ledger.isSeeded)
        XCTAssertTrue(ledger.observe(paired: [imacA], at: 105).isEmpty, "the first real list seeds")
    }

    func testRePairingAfterRemovalCountsAsANewPairing() {
        var ledger = PairingLedger()
        _ = ledger.observe(paired: [imacA, imacB], at: 100)
        _ = ledger.observe(paired: [imacA], at: 105)
        _ = ledger.observe(paired: [imacA], at: 110)
        let change = ledger.observe(paired: [imacA, imacB], at: 200)
        XCTAssertEqual(change.added, [imacB])
        XCTAssertEqual(ledger.pairedSince(imacB), 200)
    }
}

final class HostFamiliarityTests: XCTestCase {
    func testPairedAfterTrackingBeganAndNeverServedIsNew() {
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 200, lastServed: nil), .new)
    }

    func testServedUnderTheCurrentPairingIsReturning() {
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 200, lastServed: 300), .returning)
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 0, lastServed: 300), .returning)
    }

    func testPairedAgainAfterTheLastSessionIsRepaired() {
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 400, lastServed: 300), .repaired)
    }

    func testPairedBeforeTrackingAndNeverServedIsUntried() {
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 0, lastServed: nil), .untried)
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: nil, lastServed: nil), .untried)
    }

    func testMissingPairingWinsOverHistory() {
        XCTAssertEqual(HostFamiliarity(isPaired: false, pairedSince: 200, lastServed: 300), .unpaired)
    }

    func testZeroLastServedMeansNeverServed() {
        XCTAssertEqual(HostFamiliarity(isPaired: true, pairedSince: 200, lastServed: 0), .new)
    }

    func testOnlyFreshPairingsNeedTheFirstConnectionFlow() {
        XCTAssertTrue(HostFamiliarity.new.isFirstConnection)
        XCTAssertTrue(HostFamiliarity.repaired.isFirstConnection)
        XCTAssertTrue(HostFamiliarity.untried.isFirstConnection)
        XCTAssertFalse(HostFamiliarity.returning.isFirstConnection)
        XCTAssertFalse(HostFamiliarity.unpaired.isFirstConnection)
    }
}
