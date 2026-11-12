# 🕹️ Arcade BIOS

ROM image of the **Arcade6502**, the cabinet version of the miniVIC (BO6502): a 65C02 with TMS9918A video, two
AY-3-8910, an SD card, a serial port and two JAMMA control panels, **without a keyboard**.
It starts the machine on a **game front-end** driven by the joysticks: a scrolling list of the games on the SD,
and a page for every game with a preview of its title screen, the game that inspired it and its description.

- `bin/arcade.bin`: the 32 KB image to program into the EEPROM (`$8000-$FFFF`).
- [ARCADE.md](ARCADE.md): hardware, front-end, SD catalog format, jump table, RAM, tests.
- Games: [miniVIC_games](https://github.com/Boogs77/miniVIC_games). Hardware: [arcade_65c02](https://github.com/Boogs77/arcade_65c02).

---

## 🎮 Controls

| Where | What |
| :--- | :--- |
| List | stick UP / DOWN choose, LEFT / RIGHT page, START or BUTTON 1 open |
| Game page | START or BUTTON 1 play, BUTTON 2 back, UP / DOWN scroll the text |
| In a game | P1 START + P2 START held for 2 s: back to the front-end |
| Power-on | title screen ARCADE 6502, a button skips it |
| Anywhere in the front-end | TEST switch: system test (CPU, ROM, RAM, VRAM, VDP, SD, audio, serial); SERVICE switch: joystick test |
| Serial terminal (19200 8-N-1) | `W` WozMon, `B` BASIC, `I` information, `T` system test, `J` joystick test |

---

## 🛠️ Build

Needs ca65/ld65 from [cc65](https://cc65.github.io/), Node.js, and the
[emulator](https://github.com/Boogs77/BO6502-miniVIC-emulator), [bo6502-SDbuilder](https://github.com/Boogs77/bo6502-SDbuilder)
and [miniVIC_games](https://github.com/Boogs77/miniVIC_games) in folders next to this one.

```
sh make.sh                          # -> tmp/arcade.bin
node tools/make_arcade_sd.mjs       # sd_full.img of bo6502-SDbuilder + arcade catalog -> tmp/sd_arcade.img
node test/run.mjs                   # prints ALL OK
cp tmp/arcade.bin bin/              # publish a new version
```

---

## 📜 Credits

Based on the miniVIC BIOS ([miniVIC_bios](https://github.com/Boogs77/miniVIC_bios)). The Microsoft BASIC comes from
[mist64/msbasic](https://github.com/mist64/msbasic) (2-clause BSD), WozMon from the Apple I monitor by Steve Wozniak.

---

*Created by Boogs77 - 2026*
