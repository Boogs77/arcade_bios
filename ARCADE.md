# 🕹️ Arcade BIOS: how it works

The Arcade BIOS is the ROM of the **Arcade6502**, the cabinet version of the miniVIC: same CPU, memory and boards,
but **no keyboard**, two JAMMA control panels and a game front-end instead of the text menu.
It starts from the miniVIC BIOS **03.11.26 KEYB/SD** ([miniVIC_bios](https://github.com/Boogs77/miniVIC_bios)).

---

## 🔌 Hardware (schematic `Arcade6502.sch`)

| Board | Chip | Address | Notes |
| :--- | :--- | :--- | :--- |
| VDU | TMS9918A | `$B000` | INT → **NMI**, as on the miniVIC |
| Serial | W65C51 | `$C000` | DB9, kept: BASIC and WozMon from a terminal |
| Audio | 2x AY-3-8910 | `$D380` | right `$D380/1`, left `$D384/5` |
| Joysticks | W65C22 | `$D580` | port A `$D581` = P1, port B `$D580` = P2 |
| SD card | W65C22 | `$DD80` | PA1-PA4 SPI; PA0, PA5-PA7 = system switches |
| Keyboard | — | — | **not present** |

Joystick bits (both ports, active low on the pins): 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT, 4 BUTTON 1, 5 BUTTON 2,
**6 BUTTON 3, 7 START**. Bits 0-5 are those of the miniVIC joystick board, so the miniVIC games run unchanged.

System switches on port A of the SD board (`$DD81`, active low): bit 0 **TEST**, bit 5 **SERVICE**,
bit 6 **P1 COIN**, bit 7 **P2 COIN**.

---

## 📺 The front-end

At power-on (RESET) the **title screen** shows **ARCADE 6502** in big letters and **DEVELOPED BY BOOGS**
for at least 2.5 seconds (a button or START skips it); the SD card is read meanwhile. `JT_SHOW_MENU` and the
exit from a game go straight to the list.

| Screen | Controls |
| :--- | :--- |
| **List** of the games | UP / DOWN one game (with auto-repeat, wraps around), LEFT / RIGHT one page of 16, START or BUTTON 1 opens the game page, BUTTON 2 the gallery |
| **Gallery**: one game at a time, gameplay picture (a quarter of the screen), name in the selection bar, inspiring game, maker and players | LEFT / UP previous, RIGHT / DOWN next (wraps around), START or BUTTON 1 play, BUTTON 3 game page, BUTTON 2 back to the list (same game selected) |
| **Game page**: gameplay picture, inspiring game, players, description | START or BUTTON 1 play, BUTTON 2 back (to the list or the gallery), UP / DOWN scroll the description |
| **System test** (SERVICE switch, `T` on the serial port) | everything but the joysticks, see below; exit with SERVICE again, START or a byte on the serial port |
| **Joystick test** (TEST switch, `J` on the serial port) | the map of the 18 inputs, see below; exit with TEST again or a byte on the serial port |

A switch held at power-on opens its test before the list. Both joysticks drive the menus. The MiniVIC Jukebox is
the last entry of the list: the songs are played only through it.

### System test
| Line | How |
| :--- | :--- |
| CPU 65C02 | `INC A` (a NOP on the NMOS 6502) |
| ROM checksum | 16-bit sum of `$8000-$AFFF` and `$E000-$FFFF` compared with the sum written by `make.sh` at `$FDFE` |
| RAM `$0200-$7FFF` | two address-dependent patterns written and read back (shows the failing address) |
| VRAM 16 KB | the same, with the display off (shows the failing address) |
| VDP frame | the F flag of the status comes back within a frame |
| SD card | type of the card (SDSC V1, SDSC V2, SDHC) or NONE |
| Games on SD | entries of the list, from the CATALOG or from the DIR(ectory) |
| Audio right / left | a 440 Hz tone for half a second on each AY-3-8910: listen |
| Serial 6551 | sends `ARCADE6502 SYSTEM TEST: SERIAL OK` |

### Joystick test
Every input of the two control panels: UP, DOWN, LEFT, RIGHT, BUTTON 1-3, START and COIN for P1 and P2.
`--` not pressed yet, `ON` pressed now, `OK` pressed at least once; `TESTED n/18`, then `ALL 18 INPUTS OK`.

The coins are not used by the front-end yet; the games use buttons 1 and 2 (they will be adapted later).

**Leaving a game**: hold **P1 START and P2 START together for 2 seconds**. The NMI handler of the BIOS (called at
every frame by the VDP) counts the frames and goes back to the front-end. The counter is kept in the T1 latch of
the joystick VIA (`$D586`), so no RAM byte of the game is touched; the VIA timer is never started.

A game starts exactly as from the SD menu of the miniVIC: text mode with the BIOS font, `[GAME] Name` on the
serial port, `JMP` to its entry point.

### Serial port

At every start the BIOS sends `MINIVIC ARCADE BIOS <version>` and the commands:
`W` WozMon, `B` Microsoft BASIC, `I` system information, `T` system test, `J` joystick test (any other byte repeats the help).
In WozMon, `FD0FR` goes back to the front-end.

---

## 💾 The arcade catalog on the SD

`tools/make_arcade_sd.mjs` adds the catalog to an SD image of
[bo6502-SDbuilder](https://github.com/Boogs77/bo6502-SDbuilder) (`sd_full.img` by default). It lives in the free
space of the full SD, after the stories of the miniVIC Z-Machine and before the save area:

| Sector | Contents |
| :--- | :--- |
| `24576` (`$00C00000`) | header: `"ARCD"`, version `1`, number of entries N (1-255); cabinet title at `+16` (31 chars + `$00`) |
| `24577` ... | index, 32 bytes per entry (16 per sector): `+0` SD slot, `+1` kind (1 game, 2 music), `+2` flags (bit 0 preview, bit 1 text), `+8` name (23 chars + `$00`) |
| `24576 + 64 + i*8` | page of entry i, sector 0: 16 text lines of 32 bytes: line 0 inspiring game, line 1 maker / players, lines 2-15 description (30 columns, an empty line ends it) |
| `... + 1` to `+ 3` | preview patterns: 192 tiles (16 x 12, by rows) of 8 bytes |
| `... + 4` to `+ 6` | preview colours: 192 x 8 bytes (foreground << 4 \| background) |

- The list: the GAME programs of the SD directory without the keyboard versions of Zork, in alphabetical order,
  then the **MiniVIC Jukebox**. The slot is the real SD slot: loading does not change.
- The pictures: the gameplay screenshot of every game (`screenshots/<file>_game.png` of miniVIC_games, 512 x 384;
  `screenshots/jukebox_play.png` of miniVIC_apps for the Jukebox) at half resolution, 128 x 96 pixels with 2 colours
  per 8-pixel row. A program without a screenshot is run for 450 frames on the core of the
  [emulator](https://github.com/Boogs77/BO6502-miniVIC-emulator) (miniVIC, KEYB/SD BIOS) and its screen is used.
  PNG copies go to `tmp/previews/`. A picture takes about one second to read from the SD.
- The texts: title, players and description from the games table of the
  [miniVIC_games](https://github.com/Boogs77/miniVIC_games) README; the inspiring game from the description
  (`Atari 1979: ...`), from `gameslist.md` (`original game in place of ...`), or from the `INSPIRED` table of
  `tools/arcade_sd.ts`.

**Without the catalog** (an SD made only by `make_sd.py`) the list is built from the SD directory (GAME
programs, not the keyboard versions, and `JUKEBOX`), with the directory names and without pages.

---

## 🧭 Jump table

`$FD00-$FD21` are the same entries as the miniVIC BIOS, at the same addresses. `$FD24-$FD7F` stay free for the
entries the miniVIC BIOS adds later; the Arcade entries start at `$FD80`.

| Address | Name | Arcade BIOS |
| :--- | :--- | :--- |
| `$FD00` | `JT_CHROUT` | CRT (text mode) and serial |
| `$FD03` | `JT_CHRIN_NOECHO` | serial port, then **joystick keys**: START / B1 `$0D`, B2 `$1B`, B3 `' '`, UP `$80`, DOWN `$81`, LEFT `$82`, RIGHT `$83` (one per new press, either player) |
| `$FD06` | `JT_RESET_TERM` | ANSI clear of the serial terminal |
| `$FD09` | `JT_INIT_CRT` | text mode with the BIOS font |
| `$FD0C` | `JT_LOAD_RUN_SLOT` | as the miniVIC; error → front-end |
| `$FD0F` | `JT_SHOW_MENU` | the front-end |
| `$FD12` | `JT_INIT_SDCARD` | as the miniVIC |
| `$FD15` | `JT_FLUSH_KB` | ~0.5 s, drops the serial input, the buttons held now are not new presses |
| `$FD18`-`$FD1E` | SD sector read / write / init | as the KEYB/SD BIOS (`SD_LBA` `$0316-$0319`) |
| `$FD21` | `JT_KB_SET_MODE` | no keyboard: does nothing |
| `$FD80` | `JT_ARC_INPUTS` | A = P1, X = P2 (bits as above), Y = bit 0 COIN 1, 1 COIN 2, 2 TEST, 3 SERVICE; **1 = pressed** |
| `$FD83` | `JT_ARC_SILENCE` | both AY-3-8910 silent |
| `$FDFE` | `ROM_SUM` | data: ROM checksum (not a jump) |

---

## 🧠 RAM used

- `$0306` last joystick state of `JT_CHRIN_NOECHO`; the SD driver as in the KEYB/SD BIOS (`$0300-$033A`, zero page `$44-$4E`).
- Front-end only (free again once a program is loaded): zero page `$50-$5D` (tests `$60-$69`), `$1000-$11FF` sector buffer,
  `$1200-$123F` state, `$2000-$3FDF` catalog index, `$4000-$4BFF` preview.
- VRAM in the front-end: patterns `$0000`, colours `$2000`, names `$3800`, sprites off.

---

## ✅ Tests

`node test/run.mjs` runs `tmp/arcade.bin` on the emulator core with an Arcade machine (miniVIC boards without the
keyboard, 8-bit joystick ports, coins and switches on the SD VIA): list, paging, auto-repeat, game page with
preview and scrolling, gallery (browse, game page and back, play), launch with `[GAME] BUBBLES`, exit with both START, Jukebox, title screen, joystick test and
system test (also at power-on, and a bad ROM byte), serial commands, SD without the catalog, no card, jump table and
`JT_ARC_INPUTS`. Screenshots in `screenshots/`.

---

## ❓ Open points

- Coins (credits) and the games with button 3 / START: later.
- The emulator does not have the Arcade machine yet (`docs/TODO.md` of the emulator).
- bo6502-SDbuilder could call `tools/make_arcade_sd.mjs` after `update_sd.py --mode full`.

---

*Created by Boogs77 - 2026*
