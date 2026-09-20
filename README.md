# TrainerHUD

A native macOS menu-bar app for indoor cycling **without the Zwift app**:

- A true always-on-top overlay (visible over full-screen apps and games) showing
  power, cadence, heart rate, speed, elapsed time, virtual gear, grade and device status.
- Connects directly over Bluetooth to your smart trainer (FTMS / Cycling Power / CSC),
  heart-rate strap, power-meter pedals and Zwift Click / Play / Ride controllers.
- **Virtual shifting** on trainers that speak Zwift's proprietary trainer protocol
  (Zwift Cog trainers: Van Rysel D500, Wahoo KICKR Core / v6, Zwift Hub, JetBlack Victory,
  Elite Direto/Suito/Justo, Tacx NEO…). Falls back to FTMS grade steps on other trainers.
- ERG mode (FTMS target power) as a bonus.

No Xcode required: it builds with the Command Line Tools' Swift toolchain.

## Build & run

```bash
./scripts/build-app.sh          # → build/TrainerHUD.app
open build/TrainerHUD.app        # or ./scripts/install.sh to install into /Applications and relaunch
```

`swift build && .build/debug/TrainerHUD --selftest` runs the protocol test vectors
(captured from real Zwift ↔ trainer / controller traffic).

The app is ad-hoc signed, so macOS asks for Bluetooth permission again after each rebuild.

## First ride

1. Quit Zwift (most trainers accept a single app at a time).
2. Wake everything: pedal the trainer, press a button on each Click, put on the HR strap.
3. Menu bar bicycle icon → **Devices** → pick a role for each device
   (Trainer, Heart rate, Power meter, Shifter). Choices are remembered and auto-reconnected.
4. Shift with the Clicks, or ⌘↑ / ⌘↓ from the menu, ⌘= / ⌘- for grade, ⌘E for ERG.
5. **Unlock Overlay** (⌘L) to drag it where you want, then lock it again so it is click-through.

## Zwift Click v2 caveat

The Click v2 **left** puck (−) is locked to the Zwift app: it stops sending button events
about a minute after connecting unless Zwift "blessed" it within the last ~24 h.
The **right** puck (+) is never locked. Options (Settings → Controllers):

- **Unlocked via Zwift** — pair the Clicks in Zwift for ~30 s once a day, then click
  "I just used it in Zwift". The app sends the `FF 04 00` unlock after the handshake.
- **Restart loop** — the left puck is rebooted every ~50 s so it never reaches the cutoff.
- **Right puck only** — `+` shifts up and `B` shifts down (the default mapping already does this).

## Architecture

```
Sources/TrainerHUD
├── App/        main, AppDelegate, Session (state machine + button→action mapping), status menu, windows
├── Overlay/    NSPanel (.screenSaver level, .fullScreenAuxiliary) hosting the SwiftUI HUD
├── BLE/        CBCentralManager, device handlers (trainer, HRM, power meter, Zwift controllers), GATT parsers
├── Zwift/      Zwift protocol: UUIDs, opcodes, protobuf message builders/parsers
├── Model/      Settings (UserDefaults) and RideState
└── Util/       minimal protobuf codec, logging, self-test vectors
```

Logs: `~/Library/Logs/TrainerHUD/TrainerHUD.log` (also Menu → Log…). Every byte written to or
received from the Zwift service is logged in hex, which is what you want when reverse-engineering.

## Protocol notes (reverse-engineered, community sources)

Zwift service `00000001-19CA-4651-86E5-FA29DCDD09D1` (controllers on newer firmware: `FC82`),
characteristics `…0002` notify, `…0003` write, `…0004` indicate. Handshake = write `RideOn`
(`52 69 64 65 4F 6E`, trainers get `+ 02 01`); device answers `RideOn xx xx`.
Messages are `opcode + protobuf`:

| Bytes | Meaning |
|---|---|
| `04 2A 04 10 <varint ratio×10000>` | set virtual gear ratio (2.40 → `C0 BB 01`) |
| `04 2A 0A 10 <ratio> 20 <bike kg×100> 28 <rider kg×100>` | gear + weights |
| `04 22 0B 08 00 10 <zigzag grade×100> 18 EC 27 20 90 03` | simulation (wind 0, grade, CwA 0.51, Crr 0.004) |
| `00 08 88 04` | request current gear ratio (data id 520) |
| `03 …` (notify) | trainer data: power, cadence, speed×100, HR |
| `23 08 <bitmap varint> …` | Ride / Click v2 / Play fw2 buttons, active-low bitmap |
| `37 08 <plus> 10 <minus>` | Click v1 buttons, 0 = pressed |
| `07 …` | Play fw1 buttons |
| `18` | reset controller |
| `FF 04 00` | Click v2 unlock nudge |

Sources: Makinolo's blog (Play, Ride and trainer protocol posts), ajchellew/zwiftplay,
cagnulein/qdomyos-zwift, JuergenLeber/SHIFTR, OpenBikeControl/bikecontrol.
Nothing here is copied from GPL / non-commercial code; it is a fresh implementation of the
documented byte formats.
