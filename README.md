| 0 | `hidspike` CLI: dump product IDs, button maps, seize-vs-tap answer | Done — 3rd-gen remote fully mapped, seize works (BUTTONS.md) |# Siri Remote Hotkeys (`TvRemoteControl`)

A macOS menu-bar utility that pairs with Apple TV Siri Remotes over Bluetooth, shows their connection
status, and (eventually) binds each button to a custom action.

**Status: Phases 0–4 built (multi-remote copy pending). Each gesture can send a keystroke or media key, hold a key for the length of a long press, run a Shortcut, or open an app.**

| Phase | What | State |
| --- | --- | --- |
| 0 | `hidspike` CLI: dump product IDs, button maps, seize-vs-tap answer | Tool ready — **needs you + a remote** |
| 1 | Menu-bar app: remotes appear/disappear live, permission onboarding | Verified on hardware |
| 2 | Report decoding, press / long-press / double-press state machine, unit tests | Verified on hardware (29 tests green) |
| 3 | Bindings editor, keystroke + media-key actions, hold-until-release, persistence | Verified on hardware |
| 4 | Run Shortcut + Open App actions | Built — **needs a quick check**; "copy bindings from…" deferred |
| 5–6 | Launch at login, reconnect resilience, signing + notarization | Not started |

## Layout

```
Packages/RemoteCore/             Pure decoding + gesture state machine, no IOKit — `make test`
  Sources/RemoteCore/RemoteProfile.swift      RemoteProfile protocol, ClickpadRemoteProfile (gen 2/3, from BUTTONS.md)
  Sources/RemoteCore/GestureRecognizer.swift  press / long-press / double-press, clock-agnostic
  Sources/RemoteCore/Bindings.swift           KeyCombo, MediaKey, ActionSpec, BindingSet (Codable, pure)
  Tests/RemoteCoreTests/                      replays the captured hex and timestamps
TvRemoteControl/                 SwiftUI menu-bar app (Xcode project, target "TvRemoteControl")
  AppSettings.swift              enabled / exclusive mode / thresholds (UserDefaults)
  Bindings/Actions.swift         Action protocol; Keystroke (CGEvent), MediaKey (NX event), RunShortcut (shortcuts CLI), LaunchApp (NSWorkspace)
  Bindings/HoldController.swift  key-down / auto-repeat / key-up for "hold until release"
  Bindings/Pickers.swift         shortcuts catalog (`shortcuts list`) and app chooser
  UI/BindingsWindow.swift        Remote Bindings window: toolbar, gesture cards, Assign menu, hold card, recorder
  UI/RemoteFigureView.swift      the drawn clickpad remote used as the button selector
  HID/HIDRemoteMonitor.swift     IOHIDManager wrapper — match/removal callbacks are the connection state; decodes + seizes
  HID/GestureDriver.swift        runs a GestureRecognizer against the monotonic clock with a deadline timer
  HID/RemoteGeneration.swift     the classifier (known product IDs + vendor IDs live here) and SF Symbol names
  HID/HIDDeviceInfo.swift        property snapshot of an IOHIDDevice
  HID/RemoteDevice.swift         UI model for one remote
  Permissions/                   Input Monitoring + Accessibility: check / request / deep link
  Persistence/RemoteStore.swift  ~/Library/Application Support/aeksco.TvRemoteControl/remotes.json (schema v2, bindings inline)
  UI/                            MenuBarExtra (.window style), device rows, permission banner
Tools/hidspike/                  Phase 0 throwaway CLI (Swift package)
BUTTONS.md                       observed product IDs + button maps — fill in from the spike
```

## Phase 0 — run the spike (do this first)

The remote is a Bluetooth LE HID-over-GATT peripheral. macOS's own HOGP stack bonds it and publishes an
`IOHIDDevice`; we never touch CoreBluetooth. The spike prints every Apple HID device it sees (vendor `0x05AC` *and* `0x004C` — the remote uses the
latter, Apple's Bluetooth SIG ID),
and for Bluetooth ones dumps the full identity, IORegistry properties, report descriptor, element tree,
then hex-dumps every input report and every parsed element value.

1. Pair the remote: System Settings → Bluetooth. It bonds to **one host at a time**, so unpair it from the
   Apple TV first. Gen 1: hold Menu + Volume Up. Gen 2/3: hold Back + Volume Up for ~5 s. It shows up as a
   MAC address first and gets its serial-number name later.
2. Grant **Input Monitoring** to your terminal app (System Settings → Privacy & Security → Input Monitoring).
   The spike prompts for it on first run.
3. Run it and press every button one at a time, then two together:

   ```sh
   make spike                 # = cd Tools/hidspike && swift run hidspike
   make spike 2>&1 | tee spike.log
   ```

4. Repeat with `--seize` and report whether the **system volume HUD still appears** on Volume Up/Down:

   ```sh
   cd Tools/hidspike && swift run hidspike --seize
   ```

   Seize is only ever applied to Bluetooth-transport devices, never to the built-in keyboard.

5. Paste the dump into BUTTONS.md (or hand it back to whoever is implementing Phase 2).

Flags: `--all` also opens non-Bluetooth Apple devices (noisy internal sensors — useful only to prove the
tool works without a remote); `--vendor 0xNNNN` matches a different vendor for the same reason.

## Phase 1 — run the app

```sh
make app     # xcodebuild, Debug, ad-hoc signed → build/DerivedData/Build/Products/Debug/TvRemoteControl.app
make run     # build + open
```

Or open `TvRemoteControl.xcodeproj` in Xcode and run. The app is a menu-bar item only (no Dock icon):
an outlined remote when nothing is connected, filled when at least one remote is.

What to verify:

- Remote shows up in the list as soon as it's paired, with product name, PID, serial, transport.
- It goes **Offline** (grey dot) when it disconnects/sleeps and **Connected** (green) when it wakes on a
  button press, without a restart. Disconnected remotes stay in the list (persisted by serial).
- With Input Monitoring granted, pressing any button flashes the row and updates the hex readout + count.
  Without it, the row says "Can't read input — not permitted" and the orange banner explains.
- If the remote lands under **Other Apple HID devices** instead, note its transport + PID: the classifier in
  `RemoteGeneration.swift` needs adjusting.

The clickpad remote (PID `0x0315`) is recognised outright. Any other Apple Bluetooth HID device that isn't
a Magic Keyboard/Mouse/Trackpad is treated as a candidate remote ("Generation unknown") so a gen 1 remote
still shows up before its PID is recorded.

## Phase 2 — decoding and gestures

`RemoteCore` turns the button report (`fb <b1> <b2>`, see BUTTONS.md) into a `ButtonMask`, diffs it against
the previous mask, and runs a per-button state machine:

- **Press** fires on release (unless a long press already fired).
- **Long press** fires at the threshold while still held (default 500 ms).
- **Double press** is two presses within the interval (default 300 ms). For buttons with a double-press
  binding the single press is deferred until the window closes so it does not fire twice; for the rest
  the single press fires immediately and a quick second tap adds a double press.

Thresholds live under *Settings* in the menu. Everything in the package is pure and clock-agnostic;
`make test` replays the hex and timestamps captured from the real remote.

**Exclusive mode** (Settings, off by default) opens the remote with `kIOHIDOptionsTypeSeizeDevice` — the
Phase 0 decision — so macOS stops changing the volume itself. Until bindings exist that just makes the
media buttons dead, hence the default.

What to verify: open the menu and press buttons — the row shows held buttons as chips and the last five
gestures (`Back · Press`, `Select · Long press`, `Up · Double press`). Then turn on Exclusive mode and check
the volume HUD no longer appears; turn it off and check it comes back without relaunching.

## Phase 3 — bindings

Menu → **Bindings…** (⌘B) opens the *Remote Bindings* window, built from the Claude Design mockup
(`Remote Bindings.dc.html`): a drawn Siri Remote on the left is the button selector — click a button, or
press it on the physical remote — and the right pane shows that button's three gestures (Press / Long
press / Double press) as cards. Each card shows the assigned action as a keycap with its kind, an ×
to clear, and an **Assign ▾** menu: *Record Keystroke…*, *Media Key ▸*, *Run Shortcut ▸*, *Open App ▸*,
*Remove Binding*. Below the cards a *Hold until release* switch applies to the long-press binding. The
toolbar carries the remote picker and an "N of 13 buttons bound" counter. Bindings are per remote, keyed
by serial, and survive disconnects. `open TvRemoteControl.app --args --open-bindings` opens the window at
launch (handy during development).

- **Keystroke** posts a key-down/up pair via `CGEvent` to the HID event tap with the recorded modifier
  flags (and the fn flag for arrows/F-keys, like real hardware).
- **Media key** replays the `NX_KEYTYPE_*` system-defined event a keyboard would send. New remotes start
  with Volume Up/Down, Mute and Play/Pause bound to their own media key, so exclusive mode keeps them
  working. While the remote is *not* seized those four are skipped (macOS already acted) to avoid
  double-stepping — the menu row says so.
- Buttons with a double-press binding get a deferred single press (see Phase 2) automatically.
- **Hold until release** (long-press cells only, in the cell's pull-down): instead of tapping the action
  once at the long-press threshold, the key goes down when the long press begins, auto-repeats at the
  system key-repeat delay/interval like a physical key, and comes up when the button is released. Works
  for media keys too — new remotes get Volume Up/Down long-press-hold as a volume ramp. Held keys are
  released on disconnect, disable, rebinding and quit so nothing is left stuck down.

- **Run Shortcut** runs a Shortcuts.app shortcut by name through `/usr/bin/shortcuts run`, in the
  background (the `shortcuts://` URL scheme would bring the Shortcuts app forward). The pull-down lists
  your shortcuts from `shortcuts list`; a failing shortcut reports its error on the menu row.
- **Open App** launches the app by bundle identifier via `NSWorkspace`, or brings it to the front if it is
  already running. Pick from the currently running apps or choose any `.app`.

**Accessibility** is required to post keystrokes and media keys; the menu and the editor show a banner
with the prompt and the Settings deep link while such a binding exists and the grant is missing.
Shortcut and app bindings need no permission. Bindings are saved regardless.

**Why not KeyboardShortcuts.** The spec asked for sindresorhus/KeyboardShortcuts as the recorder. Reading
its source: recording calls `registerIfNeeded` → `RegisterEventHotKey`, i.e. it claims the combo as a
system-wide hotkey (bind Select → ⌘Space and Spotlight stops working), its recorder blocks or warns on
system shortcuts, and it has no media keys. It is built for *receiving* hotkeys. The recorder here is a
~40-line local `NSEvent` monitor that accepts any combination (Esc included — click ✕ to cancel).

## Permissions

Two TCC-gated permissions, both required eventually:

- **Input Monitoring** (`ListenEvent`) — needed to read HID input reports. Phase 1 needs this.
- **Accessibility** — needed to post synthetic keystrokes and media keys (Phase 3).

TCC keys grants off the code signature. Resetting between runs:

```sh
make reset-tcc     # tccutil reset ListenEvent + Accessibility for aeksco.TvRemoteControl
```

### Signing

The target uses automatic signing with team `S53J2L8J5V` (Apple Development). A revoked copy of the same
certificate is still in the login keychain alongside the valid one; if Xcode ever complains that the
certificate is invalid, delete the revoked one in Keychain Access (its SHA-1 starts `3D2D912E`) — the
valid one starts `B28AF35A`. Because the signature is stable across builds, TCC grants persist between
rebuilds; `make reset-tcc` clears them deliberately.

App Sandbox is off and Hardened Runtime is on — HID access and synthetic events don't survive the sandbox,
so this will ship Developer-ID-signed and notarized, never through the Mac App Store.

## Known limitations

- Buttons only. Trackpad/clickpad multitouch and the microphone are out of scope (private APIs / protected
  HID service respectively). The remote cannot wake the Mac.
- Gen 1 remotes need macOS 10.13–14 or 15.4+; gen 2 needs 11.3.1+; gen 3 needs 13+. This app targets 14+.
- macOS natively maps some remote buttons to system volume / play-pause. Whether we can suppress that
  (seize the device vs. swallow the event vs. leave those buttons unbindable) is what the `--seize` spike
  run decides; the answer gets recorded in BUTTONS.md.
- **Prior art:** BetterTouchTool already supports the Siri Remote (including the 2021 model) as a generic HID
  trigger source. If you just want the capability rather than a small single-purpose app, that's the
  cheaper route.

## References

- SiriRemote-Linux — GATT layout, gen-1 button encoding: https://github.com/Yanndroid/SiriRemote-Linux
- Remote Buddy compatibility matrix: https://www.iospirit.com/products/remotebuddy/hardware/apple-siri-remote/
- SiriMote — minimal buttons-to-media-keys reference: https://eternalstorms.at/sirimote/
- KeyboardShortcuts (recorder UI, Phase 3): https://github.com/sindresorhus/KeyboardShortcuts
