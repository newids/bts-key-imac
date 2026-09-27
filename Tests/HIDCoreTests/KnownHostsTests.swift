import XCTest
@testable import HIDCore

final class KnownHostsTests: XCTestCase {
    func testRecordingUpsertsByNormalizedAddressAndSortsMostRecentFirst() {
        var hosts = KnownHosts()
        hosts.record(address: "AA:AA:AA:AA:AA:01", name: "iMac-A", kind: .desktop, at: 100)
        hosts.record(address: "bb-bb-bb-bb-bb-02", name: "iMac-B", kind: .desktop, at: 200)
        hosts.record(address: "aa-aa-aa-aa-aa-01", name: "iMac-A renamed", kind: .desktop, at: 300)
        XCTAssertEqual(hosts.entries.map(\.name), ["iMac-A renamed", "iMac-B"])
        XCTAssertEqual(hosts.entries.first?.address, "aa-aa-aa-aa-aa-01")
        XCTAssertEqual(hosts.entries.count, 2)
    }

    func testKeepsOnlyTheMostRecentEntriesUpToTheLimit() {
        var hosts = KnownHosts(limit: 2)
        for i in 0..<5 {
            hosts.record(address: "00-00-00-00-00-0\(i)", name: "h\(i)", kind: .desktop, at: Double(i))
        }
        XCTAssertEqual(hosts.entries.map(\.name), ["h4", "h3"])
    }

    func testForgetRemovesAnEntry() {
        var hosts = KnownHosts()
        hosts.record(address: "00-00-00-00-00-01", name: "h1", kind: .laptop, at: 1)
        hosts.forget(address: "00:00:00:00:00:01")
        XCTAssertTrue(hosts.entries.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var hosts = KnownHosts()
        hosts.record(address: "00-00-00-00-00-01", name: "h1", kind: .laptop, at: 1)
        let data = try hosts.encoded()
        let decoded = try KnownHosts(encoded: data)
        XCTAssertEqual(decoded.entries, hosts.entries)
    }

    func testCorruptDataYieldsEmptyStoreInsteadOfCrashing() {
        XCTAssertTrue(KnownHosts(encoded: Data("garbage".utf8), fallbackToEmpty: true).entries.isEmpty)
    }
}
