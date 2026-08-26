import XCTest
@testable import RemoteCore

final class ClickpadRemoteProfileTests: XCTestCase {
    private let profile = ClickpadRemoteProfile(generation: .gen3)

    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func decode(_ hex: String) -> ButtonMask? {
        profile.decode(reportID: 0xFB, bytes: bytes(hex))
    }

    /// Every single-button report captured from remote C08N44382330 (PID 0x0315) on 2026-08-25.
    func testCapturedSinglePresses() {
        let captured: [(hex: String, button: RemoteButton)] = [
            ("fb 01 00", .tv),
            ("fb 02 00", .volumeUp),
            ("fb 04 00", .volumeDown),
            ("fb 08 00", .select),
            ("fb 10 00", .power),
            ("fb 20 00", .siri),
            ("fb 40 00", .back),
            ("fb 80 00", .mute),
            ("fb 00 01", .playPause),
            ("fb 00 02", .up),
            ("fb 00 04", .right),
            ("fb 00 08", .down),
            ("fb 00 10", .left),
        ]
        for (hex, button) in captured {
            XCTAssertEqual(decode(hex), button.mask, "\(hex) should decode to \(button)")
        }
    }

    func testAllReleased() {
        XCTAssertEqual(decode("fb 00 00"), [])
    }

    /// Captured chord: TV held, then Back pressed on top → both bits in one report.
    func testChordIsBitwise() {
        XCTAssertEqual(decode("fb 41 00"), ButtonMask([.tv, .back]))
        XCTAssertEqual(decode("fb 41 00")?.buttons, [.back, .tv])
    }

    func testPaddingBitsAreIgnored() {
        XCTAssertEqual(decode("fb 00 e0"), [])
    }

    func testAcceptsPayloadWithoutReportIDByte() {
        XCTAssertEqual(profile.decode(reportID: 0xFB, bytes: [0x02, 0x00]), RemoteButton.volumeUp.mask)
    }

    func testRejectsOtherReports() {
        XCTAssertNil(profile.decode(reportID: 0x01, bytes: [0x01, 0x00]), "the 2-byte 0x0C/0x109 device's report")
        XCTAssertNil(profile.decode(reportID: 0xFB, bytes: [0xFB]), "truncated")
        XCTAssertNil(profile.decode(reportID: 0xFB, bytes: []), "empty")
    }

    func testEveryButtonHasExactlyOneBit() {
        XCTAssertEqual(ClickpadRemoteProfile.bitOrder.count, 13)
        XCTAssertEqual(Set(ClickpadRemoteProfile.bitOrder).count, 13)
        XCTAssertEqual(Set(ClickpadRemoteProfile.bitOrder), Set(profile.buttons))
        XCTAssertEqual(Set(profile.buttons), Set(RemoteButton.allCases))
    }

    func testButtonMasksAreDistinct() {
        let masks = RemoteButton.allCases.map(\.mask.rawValue)
        XCTAssertEqual(Set(masks).count, RemoteButton.allCases.count)
        XCTAssertEqual(ButtonMask(RemoteButton.allCases).buttons, RemoteButton.allCases)
    }

    func testProfileSelection() {
        XCTAssertNotNil(RemoteProfiles.profile(for: .gen2))
        XCTAssertNotNil(RemoteProfiles.profile(for: .gen3))
        XCTAssertNil(RemoteProfiles.profile(for: .gen1), "gen 1 layout has not been captured on real hardware")
        XCTAssertNil(RemoteProfiles.profile(for: .unknown))
        XCTAssertEqual(profile.buttonUsagePage, 0x0C)
        XCTAssertEqual(profile.buttonUsage, 0x01)
    }
}
