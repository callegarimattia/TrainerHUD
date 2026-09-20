# TrainerHUD

**Ride your smart trainer without Zwift.** A native macOS menu-bar app with a heads-up overlay
that stays on top of everything (full-screen video, games, other training apps), talks Bluetooth
directly to your sensors, and does **virtual shifting** with Zwift Click / Play / Ride controllers
on Zwift Cog trainers.

![TrainerHUD overlay](docs/overlay-expanded.png)

<sub>Minimized:</sub>

![TrainerHUD minimized](docs/overlay-minimized.png)

Watch Netflix, join a Discord call, play a game, or run a workout in a browser tab while the
trainer behaves exactly like it does in Zwift: the gear you pick is simulated by the trainer
firmware, and the HUD shows what matters.

## Features

- **True overlay.** Visible over other apps' full-screen Spaces. Drag it anywhere, minimize it
  to a small pill, or make it click-through.
- **Live metrics.** 3-second power, cadence, heart rate, speed, elapsed time (auto-start/pause),
  distance, gear, grade or ERG target, resistance level, clock, device status and battery.
- **Direct Bluetooth.** FTMS trainers, Cycling Power (power meters and pedals), Cycling Speed &
  Cadence, Heart Rate. First matching device of each kind is adopted automatically and remembered.
- **Virtual shifting.** Speaks Zwift's trainer protocol to Zwift-Cog-capable trainers (Van Rysel
  D100/D500, Wahoo KICKR Core / v6 / Move, Zwift Hub, JetBlack Victory, Elite Direto / Suito /
  Justo, Tacx NEO 2T/3M with recent firmware…). 24 Zwift gears by default, fully editable.
  Trainers without the protocol fall back to FTMS grade steps.
- **Controllers.** Zwift Click v1/v2, Zwift Play (fw 1 and 2), Zwift Ride. Any button can be mapped
  to shift, grade, timer, ERG, or overlay actions. Haptics on Play/Ride.
- **ERG mode.** Target power over FTMS, adjustable in 5 W steps.
- **Remote control.** `trainerhud://` URL scheme for Alfred, Raycast, Shortcuts, Stream Deck, keyboard macros.
- **Small and dependency-free.** ~2 500 lines of Swift, builds with the Command Line Tools only.

Tested daily with a Van Rysel D500 V2, Zwift Click v2 (both pucks), COROS heart-rate strap and
Assioma PRO pedals on macOS 26. Reports from other setups are very welcome.

## Install

```bash
git clone https://github.com/<you>/TrainerHUD.git
cd TrainerHUD
./scripts/install.sh      # builds, copies to /Applications, launches
```

Requirements: macOS 14+, Xcode Command Line Tools (`xcode-select --install`). No Xcode needed.

On first launch macOS asks for Bluetooth permission. The install script signs the app with a
self-signed "TrainerHUD Dev" identity if one exists in your keychain so the permission survives
rebuilds; otherwise it is ad-hoc signed and macOS will ask again after each rebuild
(create one with Keychain Access → Certificate Assistant → Create a Certificate, type Code Signing).

## First ride

1. **Quit Zwift** (and any other app holding the trainer). Most trainers accept a single controlling app.
2. Wake your devices: pedal, press a button on each Click, put the strap on. They connect on their own.
3. Shift with the Clicks. Or use the menu-bar bicycle icon: ⌘↑ / ⌘↓ shift, ⌘= / ⌘- grade, ⌘E ERG,
   ⌘M minimize, ⌘L click-through.
4. Hover the overlay for the minimize button; drag it by its background.

Menu → **Devices** lists everything in range with a role picker if you want to override the
automatic choice (for example trainer power vs. pedal power; pedals win by default).

Menu → **Settings** has rider/bike weight (sent to the trainer for the physics), the gear table,
overlay fields and size, button mapping, and the Click v2 unlock mode.

## Zwift Click v2

Zwift ties the Click v2 **left** puck (−) to its own app: without a Zwift session in the last
~24 hours it stops sending presses about a minute after connecting. The **right** puck (+) is
never locked. Choose in Settings → Controllers:

| Mode | What it does |
|---|---|
| Unlocked via Zwift (default) | Ride in Zwift for 30 s once a day. TrainerHUD sends the unlock nudge after connecting. Both pucks work. |
| Restart loop | Left puck is rebooted every ~50 s so it never hits the cutoff. |
| Right puck only | `+` shifts up, `B` shifts down (the default mapping already does this). |

The left puck also relays the right puck's buttons, as it does in Zwift; TrainerHUD de-duplicates
that when both pucks are connected.

## Remote control

```
open trainerhud://shift-up            open trainerhud://grade/+0.5
open trainerhud://shift-down          open trainerhud://grade/0
open trainerhud://gear/12             open trainerhud://erg/220     (erg/on, erg/off)
open trainerhud://timer/toggle        open trainerhud://ride/reset
open trainerhud://overlay/toggle      overlay/minimize · expand · show · hide · lock · unlock
```

## Protocol notes

Everything below is reverse-engineered by the community (Makinolo's blog, ajchellew/zwiftplay,
cagnulein/qdomyos-zwift, JuergenLeber/SHIFTR, OpenBikeControl/bikecontrol). TrainerHUD is a
fresh MIT implementation of the documented byte formats, with test vectors from real captures
(`swift build && .build/debug/TrainerHUD --selftest`).

Zwift service `00000001-19CA-4651-86E5-FA29DCDD09D1` (controllers on newer firmware: `FC82`),
characteristics `…0002` notify, `…0003` write, `…0004` indicate. Handshake: write `RideOn`
(`52 69 64 65 4F 6E`, trainers `+ 02 01`); the device answers `RideOn xx xx`. Then
`opcode + protobuf`:

| Bytes | Meaning |
|---|---|
| `04 2A 04 10 <varint ratio×10000>` | set virtual gear ratio (2.40 → `C0 BB 01`) |
| `04 2A 0A 10 <ratio> 20 <bike kg×100> 28 <rider kg×100>` | gear + weights |
| `04 22 0B 08 00 10 <zigzag grade×100> 18 EC 27 20 90 03` | simulation: wind, grade, CwA 0.51, Crr 0.004 |
| `00 08 88 04` → `3C 08 88 04 …` | request / reply with the trainer's current gear & sim state |
| `03 …` (notify) | trainer data: power, cadence, speed×100, HR |
| `23 08 <bitmap varint> [1A …analog]` | Ride / Click v2 / Play fw2 buttons, active-low bitmap |
| `37 08 <plus> 10 <minus>` | Click v1 buttons, 0 = pressed |
| `07 …` | Play fw1 buttons and paddles |
| `19 10 <pct>` | battery |
| `FF 04 00` | Click v2 unlock nudge · `FF 03 …` server challenge · `FF 05 …` 10-min status heartbeat |
| `18` | reset controller |

Every byte on the Zwift service is logged in hex to `~/Library/Logs/TrainerHUD/TrainerHUD.log`
(also Menu → Log…). If your trainer or controller misbehaves, that log is what to attach to an issue.

## Project layout

```
Sources/TrainerHUD
├── App/       main, AppDelegate (URL scheme), Session (state + button→action), status menu, windows
├── Overlay/   NSPanel at .screenSaver level with .fullScreenAuxiliary, SwiftUI HUD
├── BLE/       CBCentralManager, trainer / HRM / power-meter / Zwift-controller handlers, GATT parsers
├── Zwift/     Zwift protocol UUIDs, opcodes, protobuf message builders and parsers
├── Model/     Settings (UserDefaults) and RideState
└── Util/      minimal protobuf codec, logging, self-test vectors
```

## Roadmap ideas

FIT file export · workout (.zwo) player on top of ERG · Wahoo-specific gear feel via wheel
circumference · encrypted handshake for 2023 Play firmware · ANT+ via USB stick.

## License

MIT. Not affiliated with Zwift Inc. Zwift, Zwift Cog, Zwift Click, Zwift Play and Zwift Ride are
trademarks of Zwift Inc.
