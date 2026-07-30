## LaunchpadPro 1.2.3

LaunchpadPro 1.2.3 makes the five-finger pinch work on external trackpads:
a Magic Trackpad that connects after launch — or reconnects after sleep —
is now picked up automatically.

### Highlights

- The five-finger pinch now works on external Magic Trackpads: earlier builds
  enumerated multitouch devices only once at startup, so a Bluetooth trackpad
  that connected later (or came back from sleep with a new device reference)
  never received a gesture callback
- LaunchpadPro now watches for multitouch device attachment through IOKit and
  rebuilds all gesture registrations whenever a device appears, with an extra
  rescan after every wake from sleep
- The built-in trackpad keeps working throughout; rescans rebuild its
  registration together with every external device

### Install

Download `LaunchpadPro.dmg`, open it, and drag `LaunchpadPro.app` into `Applications`.

This release is signed with a Developer ID certificate and notarized by Apple,
so it can be opened normally after installation.
