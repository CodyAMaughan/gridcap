import XCTest
import CoreMedia
@testable import gridcap

/// `ReferenceTime` is the shared clock that keeps multiple per-window recorders
/// frame-synced: whichever recorder sees its first frame first sets the origin,
/// and every other recorder offsets against it. These tests pin that contract.
final class ReferenceTimeTests: XCTestCase {

    func testStartsNil() {
        XCTAssertNil(ReferenceTime().value)
    }

    func testFirstWriterWins() {
        let ref = ReferenceTime()
        let first = CMTime(seconds: 1.0, preferredTimescale: 600)
        let second = CMTime(seconds: 2.0, preferredTimescale: 600)

        ref.setIfFirst(first)
        ref.setIfFirst(second) // ignored — already set

        XCTAssertEqual(ref.value, first)
    }

    func testConcurrentSettersYieldSingleWinner() {
        let ref = ReferenceTime()
        let group = DispatchGroup()
        for i in 0..<100 {
            DispatchQueue.global().async(group: group) {
                ref.setIfFirst(CMTime(seconds: Double(i), preferredTimescale: 600))
            }
        }
        group.wait()

        // Exactly one value won, and it stays fixed afterwards.
        let winner = ref.value
        XCTAssertNotNil(winner)
        ref.setIfFirst(CMTime(seconds: 999, preferredTimescale: 600))
        XCTAssertEqual(ref.value, winner)
    }
}
