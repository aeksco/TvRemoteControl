# BUTTONS.md — observed hardware facts

Everything here comes from `hidspike` against real hardware (2026-08-25, macOS 26.4, Xcode 26.3).
The classifier (`SiriRemoteIdentity`), `ClickpadRemoteProfile` and its unit tests are derived from this
file — nothing is copied from blog posts.

## Status

- [x] Vendor / product ID confirmed — 3rd-generation (USB-C) clickpad remote
- [x] Button map: all 13 bits confirmed by physical press
- [x] Chord behaviour confirmed — bitwise
- [x] Seize-vs-tap decision recorded — **seize**
- [ ] Sleep / wake timing
- [ ] 1st generation (touch-surface) remote — none available

## Identity — 3rd generation Siri Remote (A2854, USB-C)

| Property | Value | Note |
| --- | --- | --- |
| `VendorID` | **`0x004C` (76)** | Apple's **Bluetooth SIG** company ID, `VendorIDSource = 1`. **Not** the USB-IF `0x05AC` the spec assumed; matching on `0x05AC` alone never sees the remote. |
| `ProductID` | **`0x0315` (789)** | |
| `Product` | `C08N44382330` | The product string *is* the serial number — no "Siri Remote" text anywhere. |
| `SerialNumber` | `C08N44382330` | Stable identity for persisted state. |
| `Manufacturer` | `Apple Inc.` | |
| `Transport` | `Bluetooth Low Energy` | |
| `DeviceAddress` | `28-2d-7f-3c-51-aa` | |
| `VersionNumber` | 1 | |
| `ReportInterval` | 8000 µs | |
| Generation | **3rd (A2854)** | USB-C port, confirmed by the owner. 2nd gen (A2540) is expected to share the layout; it may or may not share the PID. |
| Battery | **not exposed** | No `BatteryPercent` or similar key on any sub-device. Dropped, per spec. |

Registry property keys present on the button device: `CountryCode DeviceAddress DeviceUsagePairs
Elements HIDDefaultBehavior HIDVirtualDevice InputReportElements InstanceID LocationID Manufacturer
MaxFeatureReportSize MaxInputReportSize MaxOutputReportSize PhysicalDeviceUniqueID PrimaryUsage
PrimaryUsagePage Privileged Product ProductID ReportDescriptor ReportInterval RequestTimeout SerialNumber
Transport VendorID VendorIDSource VersionNumber bInterfaceNumber kBTFirmwareRevisionKey kBTHardwareRevisionKey`.

## Sub-devices

One physical remote publishes **seven** `IOHIDUserDevice`s, all with the same vendor/product/serial:

| Registry ID | Usage page / usage | Max input report | Role |
| --- | --- | --- | --- |
| `0x10002ca8a` | `0x0C/0x01` Consumer Control | 3 bytes | **Buttons — the only one the app decodes** |
| `0x10002ca88` | `0x0C/0x109` | 2 bytes | Unknown. Report ID 1, one 8-bit field, logical range 0…0 |
| `0x10002caa4` | `0x0C/0x04` | 209 bytes | Unknown vendor blob |
| `0x10002caa5` | `0x20/0x42` Sensor | 209 bytes | Motion sensor (out of scope) |
| `0x10002caa6` | `0x20/0xE0` Sensor | 209 bytes | Sensor (out of scope) |
| `0x10002ca87` | `0x0D/0x01` Digitizer | 209 bytes | Touch surface (out of scope, §8) |
| `0x10002ca89` | `0xFF00/0x0B` Vendor | 209 bytes | Vendor — presumably Siri audio (out of scope, §8) |

Consequence for the app: match/removal callbacks fire seven times per connect/disconnect; the monitor
keys everything by serial and stays "connected" while any sub-device remains.

## Button device report descriptor (71 bytes)

```
05 0c 09 01 a1 01 15 00 25 01 85 fb 75 01 95 0d 05 0c 09 60 09 e9 09 ea 09 80 09 30 09 04 05 01 09 86
05 0c 09 e2 09 cd 09 42 09 45 09 43 09 44 81 03 75 03 95 01 81 03 05 0c 09 01 85 ff 76 80 06 95 01 b2
02 01 c0
```

Decoded: Consumer Control application collection; **input report ID `0xFB` (251)**, thirteen 1-bit
variable fields in the usage order listed below, then 3 bits of padding; plus a 208-byte feature report
`0xFF` (buffered bytes, not used).

## Button map — report `fb <byte1> <byte2>`

Bits are LSB-first in descriptor order. Every press produces one report with the bit set and a second
report with it cleared on release (`fb 00 00` when everything is up), ~90–270 ms apart for a tap.

| Bit | Byte | Mask | HID usage | Button | Press report |
| --- | --- | --- | --- | --- | --- |
| 0 | 1 | `0x01` | Consumer `0x60` | TV / Control Center | `fb 01 00` |
| 1 | 1 | `0x02` | Consumer `0xE9` Volume Increment | Volume Up | `fb 02 00` |
| 2 | 1 | `0x04` | Consumer `0xEA` Volume Decrement | Volume Down | `fb 04 00` |
| 3 | 1 | `0x08` | Consumer `0x80` Selection | Clickpad centre (Select) | `fb 08 00` |
| 4 | 1 | `0x10` | Consumer `0x30` Power | Power | `fb 10 00` |
| 5 | 1 | `0x20` | Consumer `0x04` Microphone | Siri | `fb 20 00` |
| 6 | 1 | `0x40` | Generic Desktop `0x86` System App Menu | Back (‹) | `fb 40 00` |
| 7 | 1 | `0x80` | Consumer `0xE2` Mute | Mute | `fb 80 00` |
| 8 | 2 | `0x01` | Consumer `0xCD` Play/Pause | Play/Pause | `fb 00 01` |
| 9 | 2 | `0x02` | Consumer `0x42` Menu Up | Clickpad Up | `fb 00 02` |
| 10 | 2 | `0x04` | Consumer `0x45` Menu Right | Clickpad Right | `fb 00 04` |
| 11 | 2 | `0x08` | Consumer `0x43` Menu Down | Clickpad Down | `fb 00 08` |
| 12 | 2 | `0x10` | Consumer `0x44` Menu Left | Clickpad Left | `fb 00 10` |
| 13–15 | 2 | `0xE0` | padding | — | |

Back / TV / Select were attributed by pressing them in a known order (Back, TV, centre); the other ten
match their standard HID usage names.

## Chords

Bitwise, with independent release. Captured (TV held, Back tapped on top, TV released):

```
24388.5 ms  fb 01 00   TV down
24403.4 ms  fb 41 00   Back down  (both bits set in one report)
24688.7 ms  fb 01 00   Back up
24703.3 ms  fb 00 00   TV up
```

## Native macOS handling (the §1 overlap)

With nothing but the Bluetooth pairing, **Volume Up / Volume Down change the Mac's system volume**
(confirmed). Mute and Play/Pause use the standard consumer usages and are expected to be handled too.

## Seize vs. tap — architectural decision

| Attempt | Result | Evidence |
| --- | --- | --- |
| 1. `IOHIDDeviceOpen(kIOHIDOptionsTypeSeizeDevice)` (`make spike-seize`) | **works** | `open(SEIZE)` returned success on all seven sub-devices; while seized, Volume Up/Down no longer moved the system volume (owner-confirmed). |
| 2. `CGEventTap` swallowing the media-key event | not needed | |
| 3. Mark Volume / Mute / Play-Pause unbindable | not needed | |

**Decision: seize.** The app opens every sub-device of a recognised remote with
`kIOHIDOptionsTypeSeizeDevice` when *Exclusive mode* is on (Settings; off by default until bindings
exist, because seized media buttons do nothing unless bound). Seize failures fall back to a shared open
and are logged. Follow-up for Phase 3: a "system default" action that replays the native behaviour
(volume up/down, mute, play/pause via `NSEvent` system-defined events) so an unbound media button keeps
working in exclusive mode.

## Sleep / wake behaviour

- Time from last press to `REMOVED`: _pending_
- Is the first press after sleep delivered, or consumed by the wake-up? _pending_

## 1st generation (touch surface, A1513 / A1962)

No hardware available. SiriRemote-Linux's gen-1 claim (unverified): byte 1 bitwise — `0x01` AirPlay/TV,
`0x02` Vol Up, `0x04` Vol Down, `0x08` Play/Pause, `0x10` Siri, `0x20` Menu, `0x80` touchpad click.
`RemoteProfiles.profile(for: .gen1)` returns nil until a capture exists.
