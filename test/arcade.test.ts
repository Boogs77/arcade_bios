// Tests of the Arcade BIOS on the bo6502-emulator core (emulator sources untouched).
// The Arcade machine is built from the miniVIC profile without the keyboard board; the joystick
// VIA gets all 8 bits of each port (button 3 on bit 6, START on bit 7) and the SD VIA port A
// gets TEST (bit 0), SERVICE (5), COIN 1 (6) and COIN 2 (7), as in the Arcade6502 schematic.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildMachine, defaultConfig } from 'EMU/src/machines/profiles';
import { SdCardBoard, JoystickBoard, SerialBoard } from 'EMU/src/boards/Boards';
import { SCREEN_W, SCREEN_H } from 'EMU/src/devices/TMS9918A';
import { writePngTo } from '../tools/arcade_sd';

declare const __dirname_: string;
const ROOT = join(__dirname_, '..');
const ROM = new Uint8Array(readFileSync(process.env.BIOS_ROM || join(ROOT, 'tmp', 'arcade.bin')));
const SD_ARCADE = new Uint8Array(readFileSync(join(ROOT, 'tmp', 'sd_arcade.img')));
const SD_PLAIN = new Uint8Array(readFileSync(join(ROOT, '..', 'bo6502-SDbuilder', 'sd_full.img')));
const SHOTS = join(ROOT, 'screenshots');

const U = 0x01, D = 0x02, L = 0x04, R = 0x08, B1 = 0x10, B2 = 0x20, B3 = 0x40, ST = 0x80;
const TEST = 0x01, SERVICE = 0x20, COIN1 = 0x40, COIN2 = 0x80;

function assert(c: unknown, msg: string): asserts c { if (!c) throw new Error(msg); }

class Arcade {
  m = buildMachine({ ...defaultConfig('minivic'), boards: defaultConfig('minivic').boards.filter(b => b.type !== 'keyboard') });
  joy = this.m.board<JoystickBoard>('joystick')! as any;
  sd = this.m.board<SdCardBoard>('sdcard')! as any;
  serial: number[] = [];
  sys = 0;
  constructor(img: Uint8Array | null, rom: Uint8Array = ROM) {
    this.m.loadRom(rom);
    if (img) this.sd.card.insert(img.slice());
    const orig = this.sd.via.onPortAChange;
    this.sd.via.onPortAChange = (v: number) => { orig(v); this.sd.via.inputA &= ~this.sys & 0xFF; };
    this.m.board<SerialBoard>('serial')!.acia.onTransmit = (b: number) => this.serial.push(b);
    this.m.powerOn();
    this.setJoy(0, 0);
  }
  frames(n: number) { for (let i = 0; i < n; i++) this.m.runFrame(); }
  setJoy(p1: number, p2: number) { this.joy.via.inputA = ~p1 & 0xFF; this.joy.via.inputB = ~p2 & 0xFF; }
  setSys(bits: number) { this.sys = bits; this.sd.via.inputA = (this.sd.via.inputA | 0xE1) & ~bits & 0xFF; }
  press(p1: number, p2 = 0, frames = 4) { this.setJoy(p1, p2); this.frames(frames); this.setJoy(0, 0); this.frames(frames); }
  send(s: string) { const a = this.m.board<SerialBoard>('serial')!.acia as any; for (const c of s) { a.receive(c.charCodeAt(0)); this.frames(3); } }
  get vdp() { return this.m.vdu!.vdp; }
  get g2() { return (this.vdp.reg[0] & 2) !== 0; }
  /** Graphics II name table as text (32x24); characters of the selection font in lower bits */
  rows(): string[] {
    const nt = (this.vdp.reg[2] & 0x0F) << 10, out: string[] = [];
    for (let r = 0; r < 24; r++) {
      let s = '';
      for (let c = 0; c < 32; c++) { const ch = this.vdp.vram[nt + r * 32 + c] & 0x7F; s += ch >= 0x20 && ch < 0x7F ? String.fromCharCode(ch) : '.'; }
      out.push(s);
    }
    return out;
  }
  text(): string { return this.g2 ? this.rows().join('\n') : this.text40(); }
  text40(): string {
    const nt = (this.vdp.reg[2] & 0x0F) << 10, out: string[] = [];
    for (let r = 0; r < 24; r++) {
      let s = '';
      for (let c = 0; c < 40; c++) { const ch = this.vdp.vram[nt + r * 40 + c]; s += ch >= 0x20 && ch < 0x7F ? String.fromCharCode(ch) : '.'; }
      out.push(s.trimEnd());
    }
    return out.join('\n');
  }
  nameAt(r: number, c: number) { return this.vdp.vram[((this.vdp.reg[2] & 0x0F) << 10) + r * 32 + c]; }
  waitFor(cond: () => boolean, max: number, what: string) {
    for (let i = 0; i < max; i++) { if (cond()) return i; this.m.runFrame(); }
    throw new Error(`timeout: ${what}\n${this.text()}`);
  }
  serialText() { return String.fromCharCode(...this.serial); }
  shot(name: string) { writePngTo(SHOTS, name, this.vdp.frame, SCREEN_W, SCREEN_H); }
  ram(a: number) { return this.m.ram[a]; }
}

const inList = (a: Arcade) => { if (!a.g2) return false; const r = a.rows()[2]; return r.startsWith(' SELECT A GAME') && /\d+\/\d+\s*$/.test(r); };

function bootList(img: Uint8Array) {
  const a = new Arcade(img);
  a.waitFor(() => inList(a), 1500, 'game list');
  a.frames(10);
  if (process.env.DUMP) console.log(a.rows().join(String.fromCharCode(10)), a.ram(0x1200), a.ram(0x1206));
  return a;
}

function listAndPage() {
  const a = bootList(SD_ARCADE);
  const rows = a.rows();
  assert(rows[0].includes('MINIVIC ARCADE'), 'title bar');
  assert(rows[4].includes('1 vs 1 Basketball'), 'first game: ' + rows[4]);
  assert(a.nameAt(4, 2) >= 0x80, 'selection bar on the first row');
  assert(rows[2].trimEnd().endsWith('1/48'), 'counter: ' + rows[2]);
  assert(!/KEYBOARD|keyboard/.test(rows.join('')), 'no keyboard versions');
  assert(a.serialText().includes('W = WOZMON'), 'serial help');
  a.shot('list');
  // three down: Bubbles
  a.press(D); a.press(D); a.press(0, D);              // the second player moves the list too
  assert(a.rows()[7].includes('Bubbles') && a.nameAt(7, 2) >= 0x80 && a.nameAt(4, 2) < 0x80, 'selection moved');
  assert(a.rows()[2].trimEnd().endsWith('4/48'), 'counter 4/48');
  // RIGHT: one page (16) down, the window scrolls
  a.press(R);
  assert(a.rows()[2].trimEnd().endsWith('20/48'), 'page right: ' + a.rows()[2]);
  a.press(L);
  assert(a.rows()[2].trimEnd().endsWith('4/48'), 'page left');
  // auto-repeat: DOWN held 60 frames moves more than once
  a.setJoy(D, 0); a.frames(60); a.setJoy(0, 0); a.frames(4);
  const n = parseInt(a.rows()[2].trimEnd().split(' ').pop()!.split('/')[0]);
  assert(n > 8, 'auto-repeat: ' + n);
  for (let i = n; i > 4; i--) a.press(U);
  // the game page
  a.press(B1);
  a.waitFor(() => a.rows()[15].includes('Inspired by: Bubbles'), 300, 'game page text');
  a.waitFor(() => a.nameAt(2, 8) === 128 && a.nameAt(13, 23) === 128 + 95, 300, 'preview names');
  const r = a.rows();
  assert(r[0].includes('Bubbles'), 'name in the title bar');
  assert(r[16].includes('Williams 1982 - Players: 1-2'), 'players line: ' + r[16]);
  assert(r[18].startsWith(' Williams 1982: a soap bubble'), 'description: ' + r[18]);
  assert(r[22][31] === 'v', 'more text marker');
  a.shot('game_page');
  a.press(D);
  assert(a.ram(0x1209) === 1 && a.rows()[18][31] === '^', 'description scrolled');
  a.press(B2);
  a.waitFor(() => inList(a), 120, 'back to the list');
  const selRow = [...Array(16).keys()].map(i => i + 4).find(r => a.nameAt(r, 2) >= 0x80)!;
  assert(a.rows()[selRow].includes('Bubbles'), 'same selection after BACK');
  // font of the selection bar restored in the first two thirds (preview patterns overwritten)
  const vr = a.vdp.vram;
  assert(vr[0x0400 + ('A'.charCodeAt(0)) * 8 + 1] === vr[('A'.charCodeAt(0)) * 8 + 1] && vr[0x2400 + 65 * 8] === 0x1B, 'font restored');
  console.log('      list, game page, preview, scrolling: ok');
  return a;
}

function launchAndExit(a: Arcade) {
  a.serial.length = 0;
  a.press(ST);                                        // START in the list: the game page
  a.waitFor(() => a.rows()[15].includes('Inspired by: Bubbles'), 300, 'game page');
  a.waitFor(() => a.nameAt(13, 23) === 128 + 95, 300, 'preview');
  a.frames(5);
  a.press(ST);                                        // START in the page: play
  a.waitFor(() => a.serialText().includes('[GAME] BUBBLES\r\n'), 1500, 'serial line of the game');
  a.waitFor(() => a.m.cpu.pc < 0x8000, 50, 'game running');
  a.frames(450);
  assert(a.m.cpu.pc < 0x8000 || a.m.cpu.pc >= 0xA000, 'still in the game');
  a.shot('game_bubbles');
  // a short press of both START does nothing
  a.setJoy(ST, ST); a.frames(60); a.setJoy(0, 0); a.frames(30);
  assert(!inList(a), 'both START for 1 s: still in the game');
  a.setJoy(ST, ST); a.frames(130); a.setJoy(0, 0);
  const back = a.waitFor(() => inList(a), 900, 'front-end after both START held');
  assert(!a.rows().join('').includes('DEVELOPED BY') && back < 100, 'no title screen when leaving a game: ' + back);
  console.log('      launch [GAME] BUBBLES, back with both START held: ok');
}

function jukebox() {
  const a = bootList(SD_ARCADE);
  a.press(U);                                         // from the first to the last entry
  assert(a.rows()[2].trimEnd().endsWith('48/48'), 'wrap to the last');
  a.press(B1);
  a.waitFor(() => a.rows()[15].includes('MiniVIC Sound'), 300, 'jukebox page');
  a.waitFor(() => a.nameAt(13, 23) === 128 + 95, 300, 'jukebox preview');
  a.frames(5);
  assert(a.rows().slice(18).join(' ').includes('Jukebox'), 'jukebox text');
  a.serial.length = 0;
  a.press(B1);
  a.waitFor(() => a.serialText().includes('[APP] JUKEBOX\r\n'), 2000, 'jukebox started');
  a.frames(200);
  a.shot('jukebox');
  console.log('      MiniVIC Jukebox from the list: ok');
}

function titleScreen() {
  const a = new Arcade(SD_ARCADE);
  a.waitFor(() => a.g2 && a.rows()[20].includes('DEVELOPED BY BOOGS'), 120, 'title screen');
  a.frames(5);
  // big letters: patterns 28-31 in rows 2-8 (ARCADE) and 11-17 (6502)
  let big = 0;
  for (let r = 2; r <= 17; r++) for (let c = 0; c < 32; c++) { const n = a.nameAt(r, c); if (n >= 29 && n <= 31) big++; }
  assert(big > 100, 'big letters: ' + big);
  assert(a.nameAt(20, 0) >= 0x80, 'DEVELOPED BY bar');
  a.shot('title');
  const shown = a.waitFor(() => inList(a), 900, 'list after the title screen');
  assert(shown > 100, 'title screen shown at least 2 s: ' + shown);
  // a button skips it
  const b = new Arcade(SD_ARCADE);
  b.waitFor(() => b.g2 && b.rows()[20].includes('DEVELOPED BY BOOGS'), 120, 'title screen');
  b.frames(80);                                       // the SD is read while the title is shown
  b.press(B1);
  b.waitFor(() => inList(b), 40, 'title skipped with button 1');
  // JT_SHOW_MENU (and the exit from a game) do not show it again: checked in launchAndExit
  console.log('      title screen ARCADE 6502 / DEVELOPED BY BOOGS: ok');
}

function joystickTest() {
  const a = bootList(SD_ARCADE);
  a.setSys(SERVICE); a.frames(4); a.setSys(0);
  a.waitFor(() => a.rows()[0].includes('JOYSTICK TEST'), 30, 'joystick test');
  a.frames(2);
  assert(a.rows()[14].includes('TESTED 0/18'), 'nothing tested: ' + a.rows()[14]);
  a.setJoy(B3, ST); a.setSys(COIN1); a.frames(3);
  let r = a.rows();
  assert(r[10].slice(13, 15) === 'ON' && r[10].slice(20, 22) === '--', 'P1 button 3: ' + r[10]);
  assert(r[11].slice(20, 22) === 'ON' && r[11].slice(13, 15) === '--', 'P2 start: ' + r[11]);
  assert(r[12].slice(13, 15) === 'ON' && r[12].slice(20, 22) === '--', 'coin 1: ' + r[12]);
  a.shot('joystick_test');
  a.setJoy(0, 0); a.setSys(0); a.frames(3);
  r = a.rows();
  assert(r[10].slice(13, 15) === 'OK' && r[11].slice(20, 22) === 'OK' && r[12].slice(13, 15) === 'OK', 'tested: OK');
  assert(r[14].includes('TESTED 3/18'), 'count: ' + r[14]);
  // TEST does not leave the joystick test
  for (const bit of [U, D, L, R, B1, B2, B3, ST]) { a.setJoy(bit, bit); a.frames(2); }
  a.setJoy(0, 0); a.setSys(COIN2); a.frames(2); a.setSys(0); a.frames(3);
  assert(a.rows()[14].includes('ALL 18 INPUTS OK'), 'all tested: ' + a.rows()[14]);
  a.shot('joystick_test_all');
  a.setSys(SERVICE); a.frames(3); a.setSys(0);
  a.waitFor(() => inList(a), 30, 'back from the joystick test');
  // SERVICE held at power-on
  const b = new Arcade(SD_ARCADE);
  b.setSys(SERVICE);
  b.waitFor(() => b.g2 && b.rows()[0].includes('JOYSTICK TEST'), 300, 'joystick test at power-on');
  b.setSys(0); b.frames(3);
  b.send('x');
  b.waitFor(() => inList(b) || b.rows().join('').includes('NO GAMES'), 900, 'out of the joystick test with the serial port');
  console.log('      joystick test (SERVICE switch, every input mapped, coins): ok');
}

function systemTest() {
  const a = bootList(SD_ARCADE);
  a.serial.length = 0;
  a.setSys(TEST); a.frames(4); a.setSys(0);
  a.waitFor(() => a.rows()[11].includes('LINE SENT'), 1500, 'system test results');
  const r = a.rows();
  assert(r[0].includes('SYSTEM TEST'), 'title');
  for (const [row, what] of [[2, 'CPU'], [3, 'ROM'], [4, 'RAM'], [5, 'VRAM'], [6, 'VDP']] as [number, string][])
    assert(r[row].slice(21).trim() === 'OK', `${what}: ${r[row]}`);
  assert(r[7].slice(21).trim() === 'SDSC V1', 'SD card: ' + r[7]);
  assert(r[8].slice(21).trim() === '48 CATALOG', 'games: ' + r[8]);
  assert(a.serialText().includes('SERIAL OK'), 'serial line');
  a.frames(2);
  a.shot('system_test');
  a.press(ST);
  a.waitFor(() => inList(a), 60, 'back from the system test with START');
  assert(a.rows()[4].includes('1 vs 1 Basketball'), 'list read again');
  // a bad ROM byte is found
  const bad = ROM.slice(); bad[0x1234] ^= 0xFF;
  const c = new Arcade(SD_ARCADE, bad);
  c.setSys(TEST);
  c.waitFor(() => c.g2 && c.rows()[11].includes('LINE SENT'), 2500, 'system test at power-on');
  assert(c.rows()[3].slice(21).trim() === 'FAIL', 'bad ROM checksum: ' + c.rows()[3]);
  console.log('      system test (TEST switch: CPU, ROM, RAM, VRAM, VDP, SD, audio, serial): ok');
}

function serialCommands() {
  const a = bootList(SD_ARCADE);
  a.send('i');
  a.waitFor(() => !a.g2 && a.text40().includes('Press a key or button'), 300, 'info page');
  a.frames(40);
  a.press(B1);
  a.waitFor(() => inList(a), 900, 'back from info with button 1');
  a.send('W');
  a.waitFor(() => !a.g2 && a.m.cpu.pc >= 0xFE00, 100, 'WozMon (no prompt at start, like on the miniVIC)');
  a.send('FD0FR\r');
  a.waitFor(() => inList(a), 900, 'WozMon FD0FR back to the front-end');
  a.serial.length = 0;
  a.send('B');
  a.waitFor(() => a.serialText().includes('MEMORY SIZE'), 300, 'BASIC');
  console.log('      serial: I info, W WozMon (FD0FR back), B BASIC: ok');
}

function plainSd() {
  const a = bootList(SD_PLAIN);
  const rows = a.rows().join('\n');
  assert(a.rows()[4].includes('1VS1') && a.ram(0x1206) === 0, 'list from the directory');
  assert(!rows.includes('KEYBOARD'), 'no keyboard versions');
  assert(a.ram(0x1200) === 48, 'entries from the directory: ' + a.ram(0x1200));
  a.press(U);
  assert(a.rows()[19].includes('JUKEBOX') && !a.rows()[19].includes('APP'), 'jukebox last: ' + a.rows()[19]);
  a.press(D);
  a.press(ST);
  a.waitFor(() => a.rows()[15].includes('NO DESCRIPTION'), 100, 'page without catalog');
  assert(a.rows()[7].includes('NO PREVIEW'), 'no preview');
  a.shot('plain_page');
  a.press(B1);
  a.waitFor(() => a.serialText().includes('[GAME] 1VS1'), 1500, 'game from the directory list');
  console.log('      SD without the catalog: list from the directory: ok');
}

function noCard() {
  const a = new Arcade(null);
  a.waitFor(() => a.g2 && a.rows().join('').includes('NO GAMES FOUND'), 1500, 'no card message');
  a.shot('no_card');
  a.sd.card.insert(SD_ARCADE.slice());
  a.press(ST);
  a.waitFor(() => inList(a), 900, 'list after inserting the card');
  console.log('      no card, then card inserted: ok');
}

function jumpTable() {
  const a = bootList(SD_ARCADE);
  const rom = (x: number) => ROM[x - 0x8000];
  for (let x = 0xFD00; x <= 0xFD21; x += 3) assert(rom(x) === 0x4C, `JMP at $${x.toString(16)}`);
  for (const x of [0xFD80, 0xFD83]) assert(rom(x) === 0x4C, `JMP at $${x.toString(16)}`);
  // JT_ARC_INPUTS and JT_CHRIN_NOECHO from a program in RAM
  const prog = [0x20, 0x80, 0xFD, 0x8D, 0x00, 0x0F, 0x8E, 0x01, 0x0F, 0x8C, 0x02, 0x0F,  // JSR $FD80, STA/STX/STY $0F00..
    0x20, 0x03, 0xFD, 0x90, 0xFB, 0x8D, 0x03, 0x0F, 0x80, 0xFE];                        // wait JT_CHRIN_NOECHO, STA $0F03, BRA *
  a.m.poke(0x0E00, prog);
  a.setJoy(U | B3, ST | R); a.setSys(COIN2 | TEST);
  a.m.cpu.pc = 0x0E00; a.frames(2);
  assert(a.ram(0x0F00) === (U | B3) && a.ram(0x0F01) === (ST | R) && a.ram(0x0F02) === 0x06,
    `JT_ARC_INPUTS ${a.ram(0x0F00).toString(16)} ${a.ram(0x0F01).toString(16)} ${a.ram(0x0F02).toString(16)}`);
  a.setSys(0);
  // the buttons held at the call give a key (vk_prev was 0 in the list): START has the highest priority
  a.frames(2);
  assert(a.ram(0x0F03) === 0x0D, 'joystick key: ' + a.ram(0x0F03).toString(16));
  console.log('      jump table, JT_ARC_INPUTS, joystick keys: ok');
}

export default async function () {
  const a = listAndPage();
  launchAndExit(a);
  jukebox();
  titleScreen();
  joystickTest();
  systemTest();
  serialCommands();
  plainSd();
  noCard();
  jumpTable();
}
