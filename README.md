# Skytech 3301-PF Fireplace → ESPHome

Goal: control a Skytech 3301-PF gas fireplace receiver (on/off, flame, fan) from
an ESP board by emulating the handheld remote over RF, integrated with Home Assistant.

Approach: **RF emulation**, not wiring into the receiver. The receiver keeps
all of its factory safety logic; the ESP just looks like (a copy of) the remote.

## Status

- [x] Identified hardware (FCC filings)
- [x] Receiving remote packets — now on **ESP32** (`fireplace-esp32.yaml`)
- [x] Decoded frame format (32-bit PWM, see below)
- [x] **Measured real frequency: ~304.0 MHz** (not the 303.2 in the FCC filing)
- [~] Map command bits — ID, on/off, fan, manual/auto flag done; thermostat
      codes need clean captures; add frame validation (bit errors seen)
- [x] **Transmit works (2026-11-20 19:13):** ESP32 + CC1101 at 304.05 MHz sent
      `F7FF158F` (ON) and `F7FF1588` (OFF), 10 frames each; the receiver obeyed.
      Synthesized waveform: per bit, gap then pulse (1 = 510 µs + 950 µs,
      0 = 990 µs + 480 µs), 3.5 ms between frames.
- [x] HA `switch.fireplace` (fan follows flame: ON=`59F`, OFF=`588`; boots OFF)
- [x] Keep-alive every 30 min with no-beep codes (`597` on / `580` off)
- [x] Remote sync: validated frames (ID `F7FF1` + 2 identical); remote button
      presses update HA; remote *auto* sends that disagree get overridden
- [ ] HA thermostat (`generic_thermostat`, Zigbee sensor for now)
- [ ] Intake-air temp/humidity sensor — SHT41 ordered; wiring + config in "SHT41" section
- [ ] 3D-printed case — draft in `case/` (not yet rendered/printed)
- [x] Remote parked in Off sends `580` (flame off, no-beep) **every 15 min**,
      9 frames per burst (observed 08:19–11:04 on 2026-11-21). Not 60 min as the
      manual implies. The sync logic treats it as "agrees with HA OFF"; nothing to do.

## Findings, 2026-11-20 session (supersedes older notes below)

**Frequency:** sweep with the CC1101 tuned at runtime (web_server number entities):

| RX window | Result |
|---|---|
| 302.8–303.6 MHz | nothing |
| 303.14–303.46 / 303.39–303.71 / 303.64–303.96 | nothing |
| 303.2–304.0 (303.6 MHz, 812 kHz) | works, but fragments + bit errors (signal at filter edge) |
| 303.6–304.4 (304.0 MHz, 812 kHz) | 19 clean frames, 0 broken |
| 303.84–304.16 (304.0 MHz, 325 kHz) | 18 clean frames |

→ Remote transmits at **~304.0–304.1 MHz** (matches the *receiver's* FCC grant).
Config now uses **304.05 MHz, 325 kHz filter**. Use this for TX too.

**Board:** ESP8266 (Lolin) missed edges under Wi-Fi load → frames chopped by
fake ≥2 ms gaps. **ESP32-WROOM** (RMT hardware capture) fixed it.
ESP32 wiring: SCK P18, MISO P19, MOSI P23, CSN P5, GDO0 P4, GDO2 P16, VCC 3V3.

**Antenna:** keep the antenna wire **away from the USB cable/port** — next to
it, reception died almost completely (USB noise / detuning).

**Codes (ID `F7FF1` + 12-bit command), confirmed on ESP32:**

| Cmd | Bits | Meaning |
|---|---|---|
| `58F` | `0101 1000 1111` | ON, fan off (button press) |
| `59F` | `0101 1001 1111` | ON, fan on (button press) |
| `588` | `0101 1000 1000` | OFF (button press) |
| `587` | `0101 1000 0111` | ON, fan off, bit 3 clear (auto/no-beep resend?) |
| `597` | `0101 1001 0111` | flame on, fan on, bit 3 clear (seen entering THERMO with heat on) |
| `580` | `0101 1000 0000` | flame off, bit 3 clear (THERMO, no heat) |

- Bit 4 (`0x10`) = **fan on/off** (no speed levels).
- Low 3 bits = **flame on (`111`) / off (`000`)** — no flame levels on this unit
  (Up/Down in ON mode transmit nothing).
- Bit 3 (`0x8`) = probably **"button press → receiver beeps"**; clear on
  thermostat/automatic sends (manual: no beep when THERMO cycles).
- Bits 11–8 (`0101`) constant so far.
- THERMO: remote re-evaluates and transmits **every ~2 min**, plus ~10 s after
  a SET change. Fan appears to switch off with the flame in THERMO (unconfirmed).
- Occasional single-bit errors (`77FF1`, `F73F1`, `F4BF1`) → require ID match
  and ≥2 identical frames before trusting a code.

**Tooling (scratchpad, not in repo):** a stdlib-only client for the ESPHome
dashboard websocket (`/ws`: `devices/logs`, `devices/update_config`,
`firmware/install`, `firmware/get_job`) is used to stream logs and OTA-flash.

## Home Assistant

1. **Adopt the device:** Settings → Devices & services → the discovered
   **ESPHome** device `fireplace-esp32` → Configure. It exposes:
   - `switch.fireplace_esp32_fireplace`: fireplace on/off (fan follows flame)
   - `text_sensor` "Last RF code", radio tuning numbers, restart button
2. **Thermostat:** [`homeassistant/fireplace_thermostat.yaml`](homeassistant/fireplace_thermostat.yaml)
   is a `generic_thermostat` package. Set `target_sensor` to a room temperature
   sensor somewhere in the room (e.g. Zigbee). Not the SHT41: it lives in the
   ESP32 case under the fireplace and reads intake air. Check the
   `heater` entity ID, and restart HA.
   - `min_cycle_duration: 5 min` protects the gas valve and ignition from rapid cycling.
   - `initial_hvac_mode: off` stops an HA restart from lighting the fireplace.
   - No `keep_alive`: that would make the receiver beep every few minutes; the
     ESP32 sends its own silent keep-alive every 30 min.
3. **Take the batteries out of the physical remote** while HA runs the
   fireplace. The remote re-sends its own state in every mode (`580` every
   15 min in Off, on/off every 2 min in THERMO), and the receiver obeys it.
   With HA ON and the remote parked in Off, the receiver would put the flame
   out every 15 min until the ESP32 re-sent ON. Keep the remote (with
   batteries stored next to it) as a backup; if you use it, the ESP32 adopts
   its button presses. The receiver's slide switch ON position also works
   without any radio at all.

## Using this with your own fireplace

- Set `remote_id` at the top of `fireplace-esp32.yaml` to your remote's
  20-bit code: flash, press a button on your remote near the ESP32, and read
  `id=XXXXX` from the log. (The ID in this repo is the author's remote; it
  only matters within radio range of their fireplace.)
- Check the frequency: units vary (this one is ~304.05 MHz although the FCC
  filing says 303.2). Use the `RX frequency kHz` / `RX filter kHz` numbers on
  the device's web page to sweep while pressing buttons, as in the Findings.
- The command bits were mapped on a **3301-PF** with on/off flame and fan.
  Other Skytech models may use the low 3 bits for flame levels.
- The receiver's slide switch must be on **REMOTE**.
- **Safety:** this controls a gas appliance. The receiver keeps all its own
  safety features (signal-loss shutdown, overheat shutdown), and the ESP32
  defaults to OFF on reboot. Don't leave the fireplace running unattended
  in ways you wouldn't with the original remote.

## SHT41 intake-air temperature/humidity sensor (ordered, not yet installed)

### Wiring (SHT41 breakout → ESP32-WROOM)

All on the same header side as the CC1101 signal pins except 3V3.

| SHT41 pin | ESP32 pin | Notes |
|---|---|---|
| VIN / VCC | **3V3** | shared with the CC1101's VCC (other header side, antenna end) |
| GND | **GND** | any GND |
| SDA | **P21** | GPIO21 (CLK side, 14th pin from the USB end) |
| SCL | **P22** | GPIO22 (CLK side, 17th pin from the USB end) |

- Use **3V3, not 5V**. Most SHT41 breakouts (Adafruit, SparkFun) accept
  either, but 3V3 keeps the I2C levels matched to the ESP32.
- Breakouts usually include I2C pull-up resistors; no extra parts needed.
- A cable of up to ~1–2 m between ESP32 and sensor is fine for I2C at the
  default speed. Twisted pair or a short ribbon helps.

### Placement and purpose

The ESP32 lives in its case **under the fireplace, about 1 ft from the
receiver**, and the SHT41 sits in a vented pocket of that case. So it measures
**intake air under the fireplace**, not the room. That makes it a diagnostic
(how warm the area around the receiver/valve gets, whether the fan is moving
air), **not** a thermostat input. The HA thermostat uses a separate room sensor.

The case keeps the SHT41 in its own walled-off pocket so the ESP32's own heat
doesn't skew it.

### ESPHome config to add (to `fireplace-esp32.yaml`)

```yaml
i2c:
  sda: GPIO21
  scl: GPIO22
  scan: true          # logs found devices at boot; SHT41 is at 0x44

sensor:
  - platform: sht4x
    temperature:
      name: "Intake temperature"
      id: intake_temp
    humidity:
      name: "Intake humidity"
    update_interval: 30s
```

Check after first boot: the log should show `Found i2c device at address 0x44`.
If it doesn't, SDA/SCL are probably swapped.

## Hardware

| Part | Notes |
|---|---|
| **ESP32-WROOM DevKit** (38-pin, USB-C, "FEIYANG") | Current board. RMT hardware captures pulses cleanly. Labels on the back use a `P` prefix (`P4` = GPIO4). |
| CC1101 module, **433 MHz-labelled** | Chip covers 300–348 MHz; the 433 matching network costs range at 304 MHz. Fine with the ESP32 placed near the fireplace receiver. A 315 MHz board is the upgrade if range is ever a problem. |
| Antenna | 10 cm SMA antenna tuned for 315 MHz (ordered; tested so far with a 2" stub and a 9" whip, both similar). 315 is close enough to 304. Keep it **upright and away from the USB cable**. |
| ~~Lolin NodeMCU v3 (ESP8266)~~ | Retired: missed edges under Wi-Fi load. Config kept as `fireplace.yaml`. |

### Wiring (CC1101 → ESP32-WROOM)

Count pins from the **USB-C end**. All signal pins are on the side labelled
`CLK SD0 SD1 P15 P2 P0 P4 …`; only 3V3 is on the other side.

| CC1101 | ESP32 label | GPIO | Position |
|---|---|---|---|
| GDO0 (TX data) | **P4** | 4 | CLK side, 7th from USB |
| GDO2 (RX data) | **P16** | 16 | CLK side, 8th from USB |
| CSN | **P5** | 5 | CLK side, 10th from USB (strapping pin; fine as CS) |
| SCK | **P18** | 18 | CLK side, 11th from USB |
| MISO | **P19** | 19 | CLK side, 12th from USB |
| GND | **GND** | — | CLK side, 13th from USB |
| MOSI | **P23** | 23 | CLK side, 18th from USB |
| VCC | **3V3** | — | other side, last pin at the antenna end (**not** 5V) |

The SHT41 (when installed) adds SDA → P21 and SCL → P22; see the SHT41 section.

## Firmware

**`fireplace-esp32.yaml`** — the live config (ESPHome 2026.11.0, dashboard
device `fireplace-esp32`, IP 192.168.2.204). Contents:

- `cc1101` at **304.05 MHz**, ASK/OOK, 325 kHz filter.
- `remote_receiver` (GDO2) with an `on_raw` decoder for Skytech frames; logs
  `code=F7FF158F id=F7FF1 cmd=58F …` and drives remote sync.
- `remote_transmitter` (GDO0) + `send_skytech` script that synthesizes frames
  (ID `F7FF1` + 12-bit command, 10 repeats).
- `switch.fireplace` (ON `59F` / OFF `588`, boots OFF), 30-min keep-alive,
  remote sync with validation.
- Diagnostics: 60 s radio heartbeat, `Last RF code` text sensor, restart
  button, and `web_server` (http://192.168.2.204) with runtime
  `RX frequency kHz` / `RX filter kHz` numbers for tuning.

`fireplace.yaml` — the old ESP8266/Lolin capture config (dashboard name
`fireplace-control.yaml`), kept for reference.

Both need `wifi_ssid` / `wifi_password` in ESPHome secrets.

## FCC / device facts

| | Remote (transmitter) | Receiver |
|---|---|---|
| FCC ID | [K9L3301TX](https://fccid.io/K9L3301TX) (2002) | [K9L3001RX](https://fccid.io/K9L3001RX) (1997) |
| Frequency | 303.2 MHz on the grant; **measured ~304.0–304.1 MHz** | 304 MHz (superregenerative — wide acceptance) |
| Other | Part 15.231 | IC 2439-102-760A |

Note: not 433 MHz, and not the 303.2 MHz on the remote's grant either. Firmware uses **304.05 MHz** (see Findings).

Exhibits on the remote's filing (schematic, operational descriptions, test report)
returned 403 to automated fetches. Still worth downloading by hand into `fcc/`,
especially *"CRN 5565 technical information to address 15.231(a)(3)"*.

## RF protocol (decoded from captures)

- **Modulation:** OOK, ~304.05 MHz (measured)
- **Bit encoding:** PWM, ~1.47 ms per bit, bit value is the mark length
  - long mark ≈ 950 µs + short space ≈ 500 µs → **1**
  - short mark ≈ 480 µs + long space ≈ 1000 µs → **0**
  - (polarity is a convention; could be inverted)
- **Frame:** 32 bits, MSB first, no visible preamble
- **Inter-frame gap:** ≈ 3.5 ms (sometimes up to ~5.4 ms)
- **Repeats:** many identical frames per button press
- **Rolling code:** none observed — repeated frames are identical
- **Checksum:** none obvious yet

### Frame layout (hypothesis)

The manual says each transmitter has one of **1,048,576 (2²⁰)** security codes, so:

```
| 20-bit ID (F7FF1) | 12-bit command/state |
```

### Captured codes

| Button press | Code | Last 12 bits |
|---|---|---|
| Mode (1st) | `F7FF1588` | `0101 1000 1000` |
| Mode (2nd) | `F7FF158F` | `0101 1000 1111` |
| Fan | `F7FF159F` | `0101 1001 1111` |

Observations: Fan set bit 4 (`8F` → `9F`); the low nibble changed between Mode
presses. Up/Down captures were lost to buffer overflow (fixed via `idle: 2ms`)
and need redoing.

One Mode frame decoded as 33 bits (an extra `1`) — treated as an ESP8266
reception glitch since all other frames were 32 bits.

## Remote buttons (3301-PF)

Down, Up, Mode, Timer/Time, Set, Fan, Ahead, Back, Prog

Expected (to be confirmed by capture):

| Button | Likely function | Transmits? |
|---|---|---|
| Mode | ON / THERMO / OFF / program mode | Yes |
| Up / Down | Set temp (THERMO); flame height (ON) | Flame: yes |
| Fan | Fan speed | Yes |
| Prog / Ahead / Back | Edit schedule (stored in remote) | Probably not |
| Timer/Time, Set | Clock, countdown timer, confirm | Probably not |

## Behavior from the manual (plain 3301; PF adds flame/fan)

Manual: <https://fccid.io/K9L3301TX/User-Manual/Updated-user-manual-327753>

- **The thermostat lives in the remote.** In THERMO mode the remote reads room
  temperature every 2 minutes and sends ON/OFF. The receiver only obeys
  commands, so the ESP/HA can run its own thermostat logic.
- Set temp range 45–99 °F (6–32 °C). Swing 1/2/3 °F (default 2).
- Countdown timer 15 min to 9 h (runs in the remote).
- **Communication safety:** the remote transmits **every 60 minutes** in all
  modes. If the receiver hears nothing for 60 min it starts a **2-hour
  countdown**, then shuts the appliance off and beeps every 4 s until MODE
  (→ ON) is pressed. **The ESP must transmit at least hourly.**
  (Observed: in Off this remote actually sends `580` every 15 min.)
- **Thermo safety:** receiver shuts down if its case reaches 130 °F.
- Receiver **beeps once** on a manual ON/OFF command (no beep for THERMO
  cycling) — handy confirmation that transmissions are accepted.
- Receiver slide switch: ON / REMOTE / OFF. Must be on **REMOTE** for RF control.
- **LEARN pairing:** slide switch on REMOTE, press LEARN on the receiver, then
  MODE on the transmitter. The receiver stores **one** code; a new pairing
  replaces the old one. If it fails, wait 1–2 minutes and retry.
- Receiver has an **ADJ** frequency-tuning screw (under the slide cover). If
  range is poor, turn ~5° counter-clockwise (max 1/8 turn).

## Design decisions / open questions

- **ID strategy:** clone the remote's ID (`F7FF1`) so both the ESP and the
  physical remote keep working (preferred), vs. a new ID + LEARN (disables the
  physical remote).
- **Remote conflict:** the physical remote re-sends its own state hourly (and
  every 2 min in THERMO), which will override the ESP. Options: ESP listens and
  syncs to remote presses; or pull the remote's batteries and let HA be the
  sole controller. Resolved: OFF does beacon (`580` every 15 min), so pull
  the batteries.
- Is the polarity (long = 1) right, and is there a checksum in the 12 bits?

## Next captures

With the decoder flashed, ~2 s between presses, note the screen after each:

1. **Mode:** cycle through all modes back to the start
2. **Flame:** in ON, Up to max, then Down to min
3. **Fan:** every speed back to off
4. **Fan while OFF:** does it transmit?
5. **Prog, Ahead, Back, Timer/Time, Set:** one press each (expect nothing)
6. **THERMO:** set temp above room, then below room
7. **Idle in THERMO ~15 min:** check for periodic transmissions

## Troubleshooting notes

- **WebSerial "Failed to open serial port" on Ubuntu:** snap Chromium can't
  access serial ports → use Google Chrome `.deb`. Also add the user to `dialout`
  (`sudo usermod -aG dialout $USER`, then re-login) and remove `brltty`, which
  grabs CH340 (1a86:7523) adapters.
- **CC1101 SPI failure:** a `FF0F` / `0000` / `FFFF` log at setup means
  check MISO/MOSI/CS wiring.
- **Buffer overflow / long-operation warnings:** caused by `idle: 10ms`
  bundling whole repeat bursts + `dump: all`. Fixed with `idle: 2ms`, `filter:
  200us`, and the custom decoder.

## License

MIT. See [LICENSE](LICENSE). Provided as-is, with no warranty. You are responsible for
safe operation of your gas appliance.
