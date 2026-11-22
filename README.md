# 🕹️ Arcade BIOS

ROM image of the **Arcade6502**, the cabinet version of the miniVIC (BO6502): a 65C02 with TMS9918A video, two
AY-3-8910, an SD card, a serial port and the JAMMA interface of the cabinet (a single connector, with the controls of both players), **without a keyboard**.
It starts the machine on a **game front-end** driven by the joysticks: a scrolling list of the games on the SD,
a gallery with a gameplay picture of every game and the game that inspired it, and a page with its description.

- `bin/arcade.bin`: the 32 KB image to program into the EEPROM (`$8000-$FFFF`).
- [ARCADE.md](ARCADE.md): hardware, front-end, SD catalog format, jump table, RAM, tests.
- The cabinet SD (games adapted to coins and START, catalog): `update_sd.py --mode arcade` of
  [bo6502-SDbuilder](https://github.com/Boogs77/bo6502-SDbuilder).
- Games: [miniVIC_games](https://github.com/Boogs77/miniVIC_games). Hardware: [arcade_65c02](https://github.com/Boogs77/arcade_65c02).

---

## 🎮 Controls

| Where | What |
| :--- | :--- |
| List | stick UP / DOWN choose, LEFT / RIGHT page, START or BUTTON 1 open, BUTTON 2 gallery |
| Gallery | stick previous / next game, START or BUTTON 1 play, BUTTON 3 description, BUTTON 2 list |
| Game page | START or BUTTON 1 play, BUTTON 2 back, UP / DOWN scroll the text |
| In a game | P1 START + P2 START held for 2 s: back to the front-end |
| COIN P1 / P2 | one coin = one credit, at most 9, counted by the BIOS (also during a game); shown at the bottom right of the front-end |
| System test | BUTTON 1: GAME SETTINGS, FREE PLAY or COIN for every game or for all of them, saved on the SD |
| Power-on | title screen ARCADE 6502, a button skips it |
| Anywhere in the front-end | SERVICE switch: system test (CPU, ROM, RAM, VRAM, VDP, SD, audio, serial); TEST switch: joystick test |
| Serial terminal (19200 8-N-1) | `W` WozMon, `B` BASIC, `I` information, `T` system test, `J` joystick test |

---

## 🎬 Videos

Five-minute explanatory videos, in Italian and English, with subtitles:

* **The Arcade6502 cabinet: front-end, credits and catalog**: [Italiano](https://youtu.be/8jpY8511fZo)
* **The whole project: from the modular BO6502 to miniPET, miniVIC and Arcade6502**: [Italiano](https://youtu.be/3ln8cZt3MQk) · [English](https://youtu.be/d8nvmrTR-eE)

## 🛠️ Build

Needs ca65/ld65 from [cc65](https://cc65.github.io/), Node.js, and the
[emulator](https://github.com/Boogs77/BO6502-miniVIC-emulator), [bo6502-SDbuilder](https://github.com/Boogs77/bo6502-SDbuilder)
and [miniVIC_games](https://github.com/Boogs77/miniVIC_games) in folders next to this one.

```
sh make.sh                          # -> tmp/arcade.bin
node tools/make_arcade_sd.mjs       # sd_full.img of bo6502-SDbuilder + arcade catalog (version 1) -> tmp/sd_arcade.img
node test/run.mjs                   # prints ALL OK (also uses sd_arcade.img of bo6502-SDbuilder: update_sd.py --mode arcade)
cp tmp/arcade.bin bin/              # publish a new version
```

---

## 📜 Credits

Based on the miniVIC BIOS ([miniVIC_bios](https://github.com/Boogs77/miniVIC_bios)). The Microsoft BASIC comes from
[mist64/msbasic](https://github.com/mist64/msbasic) (2-clause BSD), WozMon from the Apple I monitor by Steve Wozniak.

---

*Created by Boogs77 - 2026*
