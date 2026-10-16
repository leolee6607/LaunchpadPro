## LaunchpadPro 1.2.4

LaunchpadPro 1.2.4 rebuilds horizontal paging for 120Hz ProMotion displays:
swipes now track your fingers one-to-one with no trailing lag.

### Highlights

- Page swipes are driven directly by AppKit and Core Animation instead of
  re-rendering the SwiftUI grid every frame, so paging stays smooth at 120Hz
- Removed the two layers of smoothing that made the grid trail behind your
  fingers; scroll deltas are accumulated without loss
- Releasing a swipe carries your finger's velocity into the snap animation,
  and a snap in progress can be caught and dragged again
- Only the current page and its neighbours are rendered while paging
- App scanning on wake and on folder changes moved off the main thread

### Known issue

- While dragging an icon to reorder, neighbouring icons move to their new
  slots without the sliding animation

### Install

Download `LaunchpadPro.dmg`, open it, and drag `LaunchpadPro.app` into `Applications`.

This release is signed with a Developer ID certificate and notarized by Apple,
so it can be opened normally after installation.

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
