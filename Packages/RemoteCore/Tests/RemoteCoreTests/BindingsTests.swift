import XCTest
@testable import RemoteCore

final class BindingsTests: XCTestCase {
    func testKeyComboDisplayUsesAppleModifierOrder() {
        let combo = KeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control], keyName: "A")
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘A")
        XCTAssertEqual(KeyCombo(keyCode: 49, keyName: "Space").displayString, "Space")
        XCTAssertEqual(KeyCombo.specialKeyNames[53], "Esc")
        XCTAssertTrue(KeyCombo(keyCode: 123, keyName: "←").isFunctionKeyGroup)
        XCTAssertFalse(KeyCombo(keyCode: 0, keyName: "A").isFunctionKeyGroup)
    }

    func testModifiersEncodeAsPlainInteger() throws {
        let data = try JSONEncoder().encode(KeyCombo(keyCode: 49, modifiers: [.command], keyName: "Space"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["modifiers"] as? Int, 8)
        XCTAssertEqual(json["keyCode"] as? Int, 49)
        XCTAssertEqual(json["keyName"] as? String, "Space")
    }

    func testBindingSetRoundTripsThroughJSON() throws {
        var set = BindingSet()
        set[.select, .press] = GestureBinding(action: .keystroke(combo: KeyCombo(keyCode: 49, modifiers: [.command], keyName: "Space")))
        set[.back, .longPress] = GestureBinding(action: .keystroke(combo: KeyCombo(keyCode: 53, keyName: "Esc")))
        set[.volumeUp, .press] = GestureBinding(action: .mediaKey(key: .volumeUp))
        set[.up, .doublePress] = GestureBinding(action: .mediaKey(key: .next))
        set[.right, .longPress] = GestureBinding(action: .keystroke(combo: KeyCombo(keyCode: 124, keyName: "→")), holdUntilRelease: true)

        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(BindingSet.self, from: data)
        XCTAssertEqual(decoded, set)
        XCTAssertEqual(decoded[.select, .press]?.action.displayString, "⌘Space")
        XCTAssertEqual(decoded[.right, .longPress]?.holdUntilRelease, true)
        XCTAssertEqual(decoded[.back, .longPress]?.holdUntilRelease, false)
        XCTAssertEqual(decoded.count, 5)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.map { $0["button"] as? String }, ["back", "right", "select", "up", "volumeUp"], "encoded sorted for stable diffs")
        XCTAssertNil(json[0]["holdUntilRelease"], "flag omitted when false")
        XCTAssertEqual(json[1]["holdUntilRelease"] as? Bool, true)
    }

    func testSubscriptSetsAndRemoves() {
        var set = BindingSet()
        XCTAssertTrue(set.isEmpty)
        set[.tv, .press] = GestureBinding(action: .mediaKey(key: .playPause))
        XCTAssertEqual(set[.tv, .press]?.action, .mediaKey(key: .playPause))
        set[.tv, .press] = nil
        XCTAssertNil(set[.tv, .press])
        XCTAssertTrue(set.isEmpty)
    }

    func testButtonsWithDoublePressDriveDeferral() {
        var set = BindingSet()
        set[.select, .press] = GestureBinding(action: .mediaKey(key: .playPause))
        XCTAssertEqual(set.buttonsWithDoublePress, [])
        set[.select, .doublePress] = GestureBinding(action: .mediaKey(key: .next))
        set[.back, .doublePress] = GestureBinding(action: .mediaKey(key: .previous))
        XCTAssertEqual(set.buttonsWithDoublePress, [.select, .back])
    }

    func testDefaultsReplayNativeMediaKeysOnly() {
        let defaults = BindingSet.defaults(for: ClickpadRemoteProfile().buttons)
        XCTAssertEqual(defaults.count, 6)
        XCTAssertEqual(defaults[.volumeUp, .press], GestureBinding(action: .mediaKey(key: .volumeUp)))
        XCTAssertEqual(defaults[.volumeDown, .press], GestureBinding(action: .mediaKey(key: .volumeDown)))
        XCTAssertEqual(defaults[.mute, .press], GestureBinding(action: .mediaKey(key: .mute)))
        XCTAssertEqual(defaults[.playPause, .press], GestureBinding(action: .mediaKey(key: .playPause)))
        XCTAssertEqual(defaults[.volumeUp, .longPress], GestureBinding(action: .mediaKey(key: .volumeUp), holdUntilRelease: true), "holding volume ramps")
        XCTAssertEqual(defaults[.volumeDown, .longPress]?.holdUntilRelease, true)
        XCTAssertNil(defaults[.mute, .longPress])
        XCTAssertNil(defaults[.select, .press])
        XCTAssertEqual(BindingSet.defaults(for: []).count, 0)
    }

    func testNativeMediaKeys() {
        XCTAssertEqual(RemoteButton.volumeUp.nativeMediaKey, .volumeUp)
        XCTAssertNil(RemoteButton.back.nativeMediaKey)
        XCTAssertEqual(MediaKey.playPause.nxKeyType, 16)
        XCTAssertEqual(MediaKey.mute.nxKeyType, 7)
    }
}

final class BindingsCompatibilityTests: XCTestCase {
    /// Files written before `holdUntilRelease` existed have no such key; they must still load.
    func testDecodesEntriesWithoutHoldFlag() throws {
        let legacy = """
        [{"button":"back","gesture":"longPress","action":{"keystroke":{"combo":{"keyCode":53,"modifiers":0,"keyName":"Esc"}}}},
         {"button":"volumeUp","gesture":"press","action":{"mediaKey":{"key":"volumeUp"}}}]
        """
        let set = try JSONDecoder().decode(BindingSet.self, from: Data(legacy.utf8))
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(set[.back, .longPress], GestureBinding(action: .keystroke(combo: KeyCombo(keyCode: 53, keyName: "Esc")), holdUntilRelease: false))
        XCTAssertEqual(set[.volumeUp, .press]?.action, .mediaKey(key: .volumeUp))
    }
}

final class ActionSpecTests: XCTestCase {
    func testShortcutAndAppActionsRoundTrip() throws {
        var set = BindingSet()
        set[.tv, .press] = GestureBinding(action: .runShortcut(name: "Start Pomodoro"))
        set[.siri, .doublePress] = GestureBinding(action: .launchApp(bundleID: "com.apple.Safari", name: "Safari"))
        let data = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(BindingSet.self, from: data)
        XCTAssertEqual(decoded, set)
        XCTAssertEqual(decoded[.tv, .press]?.action.displayString, "Shortcut: Start Pomodoro")
        XCTAssertEqual(decoded[.siri, .doublePress]?.action.displayString, "Open Safari")
        XCTAssertEqual(decoded[.siri, .doublePress]?.action.kindName, "App")
    }

    func testAccessibilityIsOnlyNeededForSyntheticInput() {
        XCTAssertTrue(ActionSpec.keystroke(combo: KeyCombo(keyCode: 0, keyName: "A")).requiresAccessibility)
        XCTAssertTrue(ActionSpec.mediaKey(key: .mute).requiresAccessibility)
        XCTAssertFalse(ActionSpec.runShortcut(name: "x").requiresAccessibility)
        XCTAssertFalse(ActionSpec.launchApp(bundleID: "a.b", name: "B").requiresAccessibility)

        var set = BindingSet()
        XCTAssertFalse(set.requiresAccessibility)
        set[.tv, .press] = GestureBinding(action: .launchApp(bundleID: "a.b", name: "B"))
        XCTAssertFalse(set.requiresAccessibility)
        set[.back, .press] = GestureBinding(action: .keystroke(combo: KeyCombo(keyCode: 53, keyName: "Esc")))
        XCTAssertTrue(set.requiresAccessibility)
    }

    func testOnlyInputActionsAreHoldable() {
        XCTAssertTrue(ActionSpec.keystroke(combo: KeyCombo(keyCode: 0, keyName: "A")).isHoldable)
        XCTAssertTrue(ActionSpec.mediaKey(key: .volumeUp).isHoldable)
        XCTAssertFalse(ActionSpec.runShortcut(name: "x").isHoldable)
        XCTAssertFalse(ActionSpec.launchApp(bundleID: "a.b", name: "B").isHoldable)
    }
}
