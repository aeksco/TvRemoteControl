import XCTest
@testable import RemoteCore

final class GestureRecognizerTests: XCTestCase {
    private var recognizer = GestureRecognizer(config: GestureConfig(longPressThreshold: 0.5, doublePressInterval: 0.3))

    private func event(_ button: RemoteButton, _ gesture: ButtonGesture, _ time: TimeInterval) -> ButtonEvent {
        ButtonEvent(button: button, gesture: gesture, time: time)
    }

    private func released(_ button: RemoteButton, _ time: TimeInterval) -> ButtonEvent {
        ButtonEvent(button: button, gesture: .longPress, phase: .ended, time: time)
    }

    func testTapFiresPressOnRelease() {
        XCTAssertEqual(recognizer.handle(mask: [.volumeUp], at: 0), [])
        XCTAssertEqual(recognizer.held, RemoteButton.volumeUp.mask)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.15), [event(.volumeUp, .press, 0.15)])
        XCTAssertEqual(recognizer.held, [])
        XCTAssertNil(recognizer.nextDeadline())
    }

    func testHoldFiresLongPressAtThresholdAndSuppressesPress() {
        XCTAssertEqual(recognizer.handle(mask: [.select], at: 1.0), [])
        XCTAssertEqual(recognizer.nextDeadline(), 1.5)
        XCTAssertEqual(recognizer.tick(at: 1.3), [])
        XCTAssertEqual(recognizer.tick(at: 1.5), [event(.select, .longPress, 1.5)])
        XCTAssertNil(recognizer.nextDeadline(), "long press already fired; nothing left to wait for")
        XCTAssertEqual(recognizer.tick(at: 2.0), [], "long press fires once")
        XCTAssertEqual(recognizer.handle(mask: [], at: 2.2), [released(.select, 2.2)], "release ends the long press; no press")
    }

    func testLongPressEndedCarriesTheReleaseTime() {
        _ = recognizer.handle(mask: [.right], at: 10)
        XCTAssertEqual(recognizer.tick(at: 10.5), [event(.right, .longPress, 10.5)])
        let ended = recognizer.handle(mask: [], at: 13.25)
        XCTAssertEqual(ended, [released(.right, 13.25)])
        XCTAssertEqual(ended.first?.phase, .ended)
        XCTAssertEqual(recognizer.handle(mask: [.right], at: 14), [], "next press starts clean")
        XCTAssertEqual(recognizer.handle(mask: [], at: 14.1), [event(.right, .press, 14.1)])
    }

    func testLateReleaseReportStillYieldsLongPressWithoutATick() {
        _ = recognizer.handle(mask: [.back], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.7), [event(.back, .longPress, 0.5), released(.back, 0.7)])
    }

    func testDoubleTapWithoutDeferralFiresPressThenDoublePress() {
        _ = recognizer.handle(mask: [.playPause], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.1), [event(.playPause, .press, 0.1)])
        _ = recognizer.handle(mask: [.playPause], at: 0.25)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.35), [event(.playPause, .doublePress, 0.35)])
    }

    func testDoubleTapWithDeferralFiresOnlyDoublePress() {
        recognizer.config.deferredPressButtons = [.select]
        _ = recognizer.handle(mask: [.select], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.1), [], "single press is held back")
        XCTAssertEqual(recognizer.nextDeadline(), 0.4)
        _ = recognizer.handle(mask: [.select], at: 0.2)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.3), [event(.select, .doublePress, 0.3)])
        XCTAssertEqual(recognizer.tick(at: 0.5), [], "the deferred single press was consumed by the double press")
        XCTAssertNil(recognizer.nextDeadline())
    }

    func testDeferredSinglePressFiresWhenTheWindowExpires() {
        recognizer.config.deferredPressButtons = [.select]
        _ = recognizer.handle(mask: [.select], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.1), [])
        XCTAssertEqual(recognizer.tick(at: 0.39), [])
        XCTAssertEqual(recognizer.tick(at: 0.4), [event(.select, .press, 0.1)], "reported with the release time")
        XCTAssertNil(recognizer.nextDeadline())
    }

    func testSlowSecondTapIsTwoSinglePresses() {
        _ = recognizer.handle(mask: [.up], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.1), [event(.up, .press, 0.1)])
        _ = recognizer.handle(mask: [.up], at: 0.5)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.6), [event(.up, .press, 0.6)])
    }

    func testTripleTapIsDoublePressThenPress() {
        _ = recognizer.handle(mask: [.up], at: 0)
        _ = recognizer.handle(mask: [], at: 0.1)
        _ = recognizer.handle(mask: [.up], at: 0.2)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.3), [event(.up, .doublePress, 0.3)])
        _ = recognizer.handle(mask: [.up], at: 0.4)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.5), [event(.up, .press, 0.5)], "a double press resets the tap chain")
    }

    func testHoldingTheSecondTapIsALongPressNotADouble() {
        _ = recognizer.handle(mask: [.tv], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.1), [event(.tv, .press, 0.1)])
        _ = recognizer.handle(mask: [.tv], at: 0.2)
        XCTAssertEqual(recognizer.tick(at: 0.7), [event(.tv, .longPress, 0.2 + 0.5)])
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.8), [released(.tv, 0.8)])
    }

    /// Replays the chord captured on 2026-08-25 (times in seconds from the spike's clock):
    /// TV down, Back down 15 ms later, Back up, TV up 15 ms later.
    func testCapturedChordYieldsIndependentPresses() {
        XCTAssertEqual(recognizer.handle(mask: [.tv], at: 24.3885), [])
        XCTAssertEqual(recognizer.handle(mask: [.tv, .back], at: 24.4034), [])
        XCTAssertEqual(recognizer.held, ButtonMask([.tv, .back]))
        XCTAssertEqual(recognizer.handle(mask: [.tv], at: 24.6887), [event(.back, .press, 24.6887)])
        XCTAssertEqual(recognizer.handle(mask: [], at: 24.7033), [event(.tv, .press, 24.7033)])
    }

    func testChordWithOneButtonHeldLongFiresBothGestures() {
        _ = recognizer.handle(mask: [.volumeUp, .volumeDown], at: 0)
        XCTAssertEqual(recognizer.handle(mask: [.volumeDown], at: 0.1), [event(.volumeUp, .press, 0.1)])
        XCTAssertEqual(recognizer.nextDeadline(), 0.5)
        XCTAssertEqual(recognizer.tick(at: 0.5), [event(.volumeDown, .longPress, 0.5)])
        XCTAssertEqual(recognizer.handle(mask: [], at: 0.9), [released(.volumeDown, 0.9)])
    }

    func testNextDeadlinePicksTheEarliestPendingEvent() {
        recognizer.config.deferredPressButtons = [.select]
        _ = recognizer.handle(mask: [.select], at: 0)
        _ = recognizer.handle(mask: [], at: 0.1)            // deferred press due at 0.4
        _ = recognizer.handle(mask: [.back], at: 0.2)       // long press due at 0.7
        XCTAssertEqual(recognizer.nextDeadline(), 0.4)
        XCTAssertEqual(recognizer.tick(at: 0.4), [event(.select, .press, 0.1)])
        XCTAssertEqual(recognizer.nextDeadline(), 0.7)
    }

    func testRepeatedIdenticalMasksProduceNothing() {
        XCTAssertEqual(recognizer.handle(mask: [], at: 0), [])
        XCTAssertEqual(recognizer.handle(mask: [.mute], at: 1), [])
        XCTAssertEqual(recognizer.handle(mask: [.mute], at: 1.1), [])
        XCTAssertEqual(recognizer.handle(mask: [], at: 1.2), [event(.mute, .press, 1.2)])
        XCTAssertEqual(recognizer.handle(mask: [], at: 1.3), [])
    }
}
