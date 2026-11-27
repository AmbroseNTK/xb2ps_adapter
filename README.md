# Xb2PS

A small macOS menu bar app that lets you play **PS Remote Play** with an **Xbox controller**.

It reads the Xbox controller through Apple's GameController framework and exposes a virtual
**DualShock 4** (USB, `054C:09CC`) through `IOHIDUserDevice`. PS Remote Play sees the virtual
controller as a real one.

## Button mapping

| Xbox | PlayStation |
|---|---|
| A / B / X / Y | ✕ / ○ / □ / △ |
| LB, RB, LT, RT | L1, R1, L2, R2 |
| Left / right stick click | L3 / R3 |
| Menu (≡) | Options |
| View (⧉) | Touchpad click |
| Share | Share / Create |
| Xbox button, or View + Menu held together | PS button |

Rumble sent by the console is forwarded to the Xbox controller's motors.

Not supported: touchpad swipes, gyro / accelerometer, light bar.

## Usage

1. Pair the Xbox controller with your Mac (Bluetooth or USB).
2. Launch **Xb2PS**. A controller icon appears in the menu bar; its menu should say
   `Virtual DualShock 4: active`.
3. Launch PS Remote Play. If it was already running, quit and reopen it.

## Building

Requirements: macOS 13+, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple
Developer account.

```bash
./build.sh
```

The app **must** be signed with the `com.apple.developer.hid.virtual.device` entitlement
(the *HID Virtual Device* capability). macOS refuses to create the virtual controller
otherwise, so an unsigned or ad-hoc signed build will not work. `build.sh` picks your team from
the "Apple Development" certificate in your keychain and lets Xcode register the App ID and
provisioning profile; override with `DEVELOPMENT_TEAM` / `BUNDLE_ID` if needed.

`./build.sh --no-sign` only checks that the code compiles.

## How it works

- `Sources/XboxSource.swift` — finds the Xbox controller, maps its state, drives rumble.
- `Sources/VirtualDS4.swift` — creates the virtual HID device and sends input reports at 250 Hz.
- `Sources/DS4Protocol.swift` — DualShock 4 report descriptor, input and feature reports.

PS Remote Play only accepts controllers whose HID `Transport` is `USB` or `Bluetooth`, while
macOS stamps user-space devices as `Virtual`. Xb2PS overrides the property after creating the
device.

## Disclaimer

Not affiliated with Sony or Microsoft. PlayStation, DualShock and Xbox are trademarks of their
respective owners.
