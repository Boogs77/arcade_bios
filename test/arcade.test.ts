// Tests of the Arcade BIOS on the bo6502-emulator core (emulator sources untouched).
// The Arcade machine is built from the miniVIC profile without the keyboard board; the joystick
// VIA gets all 8 bits of each port (button 3 on bit 6, START on bit 7) and the SD VIA port A
// gets TEST (bit 0), SERVICE (5), COIN 1 (6) and COIN 2 (7), as in the Arcade6502 schematic.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildMachine, defaultConfig } from 'EMU/src/machines/profiles';
import { SdCardBoard, JoystickBoard, SerialBoard } from 'EMU/src/boards/Boards';
import { SaveArea } from 'EMU/src/devices/SaveArea';
import { SCREEN_W, SCREEN_H } from 'EMU/src/devices/TMS9918A';
import { writePngTo } from '../tools/arcade_sd';

declare const __dirname_: string;
const ROOT = join(__dirname_, '..');
const ROM = new Uint8Array(readFileSync(process.env.BIOS_ROM || join(ROOT, 'tmp', 'arcade.bin')));
const SD_ARCADE = new Uint8Array(readFileSync(join(ROOT, 'tmp', 'sd_arcade.img')));
const N = SD_ARCADE[24576 * 512 + 5];                 // entries of its catalog (the Jukebox is the last)
const SD_PLAIN = new Uint8Array(readFileSync(join(ROOT, '..', 'bo6502-SDbuilder', 'sd_full.img')));
// the cabinet SD of bo6502-SDbuilder (update_sd.py --mode arcade): catalog version 2, games adapted to the credits
const SD_CAB = new Uint8Array(readFileSync(join(ROOT, '..', 'bo6502-SDbuilder', 'sd_arcade.img')));
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
  constructor(img: Uint8Array | null, rom: Uint8Array = ROM, save: SaveArea | null = null) {
    this.m.loadRom(rom);
    if (img) this.sd.card.insert(img.slice());
    this.sd.card.saveArea = save;
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
  /** the credit byte of the BIOS: T1 latch high of the joystick VIA ($D587) */
  get cred() { return this.joy.via.t1Latch >> 8; }
  set cred(v: number) { this.joy.via.t1Latch = (this.joy.via.t1Latch & 0xFF) | (v << 8); }
  coin(bit: number, frames = 4) { this.setSys(bit); this.frames(frames); this.setSys(0); this.frames(4); }
  /** credit field of row 23 */
  field() { return this.rows()[23].slice(21).trim(); }
  /** index of a catalog entry by name */
  entry(name: string) {
    for (let i = 0; i < this.ram(0x1200); i++) {
      let n = '';
      for (let k = 8; k < 31 && this.ram(0x2000 + i * 32 + k); k++) n += String.fromCharCode(this.ram(0x2000 + i * 32 + k));
      if (n === name) return i;
    }
    throw new Error('no entry ' + name);
  }
  select(name: string) { const i = this.entry(name); while (this.ram(0x1201) !== i) this.press(D); }
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
  assert(rows[2].trimEnd().endsWith('1/' + N), 'counter: ' + rows[2]);
  assert(rows[23].includes('BIOS 16.11.26') && a.field() === 'FREE PLAY', 'catalog version 1: free play: ' + rows[23]);
  assert(!/KEYBOARD|keyboard/.test(rows.join('')), 'no keyboard versions');
  assert(a.serialText().includes('W = WOZMON'), 'serial help');
  a.shot('list');
  // four down: Bubbles (after Breakout and Brick Drop)
  a.press(D); a.press(D); a.press(D); a.press(0, D);  // the second player moves the list too
  assert(a.rows()[8].includes('Bubbles') && a.nameAt(8, 2) >= 0x80 && a.nameAt(4, 2) < 0x80, 'selection moved');
  assert(a.rows()[2].trimEnd().endsWith('5/' + N), 'counter 5/N');
  // RIGHT: one page (16) down, the window scrolls
  a.press(R);
  assert(a.rows()[2].trimEnd().endsWith('21/' + N), 'page right: ' + a.rows()[2]);
  a.press(L);
  assert(a.rows()[2].trimEnd().endsWith('5/' + N), 'page left');
  // auto-repeat: DOWN held 60 frames moves more than once
  a.setJoy(D, 0); a.frames(60); a.setJoy(0, 0); a.frames(4);
  const n = parseInt(a.rows()[2].trimEnd().split(' ').pop()!.split('/')[0]);
  assert(n > 9, 'auto-repeat: ' + n);
  for (let i = n; i > 5; i--) a.press(U);
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
  assert(a.rows()[2].trimEnd().endsWith(N + '/' + N), 'wrap to the last');
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

function gallery() {
  const a = bootList(SD_ARCADE);
  const galleryOf = (name: string, n: string) => {
    a.waitFor(() => a.rows()[16].includes(name) && a.rows()[14].includes(n), 120, 'gallery ' + name + ' sel ' + a.ram(0x1201));
    a.waitFor(() => a.nameAt(13, 23) === 128 + 95, 300, 'gallery picture ' + name);
    a.frames(3);
  };
  a.press(D); a.press(D); a.press(D); a.press(D);     // Bubbles
  a.press(B2);
  galleryOf('Bubbles', '5/' + N);
  let r = a.rows();
  assert(a.nameAt(16, 0) >= 0x80, 'name in the selection bar');
  assert(r[18].includes('Inspired by: Bubbles') && r[19].includes('Williams 1982'), 'inspired by: ' + r[18]);
  assert(r[7][5] === '<' && r[7][26] === '>', 'arrows');
  a.shot('gallery');
  a.press(R);
  galleryOf('Centipede', '6/' + N);
  assert(a.rows()[18].includes('Inspired by: Centipede'), 'next game');
  a.press(0, L);                                      // either player
  galleryOf('Bubbles', '5/' + N);
  a.press(U);                                         // LEFT or UP
  galleryOf('Brick Drop', '4/' + N);
  a.press(L);
  galleryOf('Breakout', '3/' + N);
  a.press(L);
  galleryOf('Asteroids', '2/' + N);
  a.press(L);
  galleryOf('1 vs 1 Basketball', ' 1/' + N);
  a.press(L);
  galleryOf('MiniVIC Jukebox', N + '/' + N);          // wraps to the last
  a.press(R);
  galleryOf('1 vs 1 Basketball', ' 1/' + N);
  a.press(R);
  galleryOf('Asteroids', '2/' + N);
  a.press(B3);                                        // the description
  a.waitFor(() => a.rows()[15].includes('Inspired by: Asteroids'), 300, 'game page from the gallery');
  a.waitFor(() => a.nameAt(13, 23) === 128 + 95, 300, 'page picture');
  a.frames(3);
  a.press(B2);                                        // back to the gallery
  galleryOf('Asteroids', '2/' + N);
  a.press(B2);                                        // back to the list, same game selected
  a.waitFor(() => inList(a), 120, 'list from the gallery');
  assert(a.rows()[2].trimEnd().endsWith('2/' + N) && a.nameAt(5, 2) >= 0x80 && a.rows()[5].includes('Asteroids'), 'selection kept');
  const vr = a.vdp.vram;
  assert(vr[0x2400 + 65 * 8] === 0x1B, 'selection font restored');
  a.press(B2);
  galleryOf('Asteroids', '2/' + N);
  a.serial.length = 0;
  a.press(ST);
  a.waitFor(() => a.serialText().includes('[GAME] ASTEROIDS\r\n'), 1500, 'play from the gallery');
  console.log('      gallery (BUTTON 2): name, inspired by, gameplay picture, browse, play: ok');
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
  a.setSys(TEST); a.frames(4); a.setSys(0);
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
  // every input once
  for (const bit of [U, D, L, R, B1, B2, B3, ST]) { a.setJoy(bit, bit); a.frames(2); }
  a.setJoy(0, 0); a.setSys(COIN2); a.frames(2); a.setSys(0); a.frames(3);
  assert(a.rows()[14].includes('ALL 18 INPUTS OK'), 'all tested: ' + a.rows()[14]);
  a.shot('joystick_test_all');
  a.setSys(TEST); a.frames(3); a.setSys(0);
  a.waitFor(() => inList(a), 30, 'back from the joystick test');
  // TEST held at power-on
  const b = new Arcade(SD_ARCADE);
  b.setSys(TEST);
  b.waitFor(() => b.g2 && b.rows()[0].includes('JOYSTICK TEST'), 300, 'joystick test at power-on');
  b.setSys(0); b.frames(3);
  b.send('x');
  b.waitFor(() => inList(b) || b.rows().join('').includes('NO GAMES'), 900, 'out of the joystick test with the serial port');
  console.log('      joystick test (TEST switch, every input mapped, coins): ok');
}

function systemTest() {
  const a = bootList(SD_ARCADE);
  a.serial.length = 0;
  a.setSys(SERVICE); a.frames(4); a.setSys(0);
  a.waitFor(() => a.rows()[11].includes('LINE SENT'), 1500, 'system test results');
  const r = a.rows();
  assert(r[0].includes('SYSTEM TEST'), 'title');
  for (const [row, what] of [[2, 'CPU'], [3, 'ROM'], [4, 'RAM'], [5, 'VRAM'], [6, 'VDP']] as [number, string][])
    assert(r[row].slice(21).trim() === 'OK', `${what}: ${r[row]}`);
  assert(r[7].slice(21).trim() === 'SDSC V1', 'SD card: ' + r[7]);
  assert(r[8].slice(21).trim() === N + ' CATALOG', 'games: ' + r[8]);
  assert(a.serialText().includes('SERIAL OK'), 'serial line');
  a.frames(2);
  a.shot('system_test');
  a.press(ST);
  a.waitFor(() => inList(a), 60, 'back from the system test with START');
  assert(a.rows()[4].includes('1 vs 1 Basketball'), 'list read again');
  // a bad ROM byte is found
  const bad = ROM.slice(); bad[0x1234] ^= 0xFF;
  const c = new Arcade(SD_ARCADE, bad);
  c.setSys(SERVICE);
  c.waitFor(() => c.g2 && c.rows()[11].includes('LINE SENT'), 2500, 'system test at power-on');
  assert(c.rows()[3].slice(21).trim() === 'FAIL', 'bad ROM checksum: ' + c.rows()[3]);
  console.log('      system test (SERVICE switch: CPU, ROM, RAM, VRAM, VDP, SD, audio, serial): ok');
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
  assert(a.ram(0x1200) >= 48 && a.rows()[2].trimEnd().endsWith('1/' + a.ram(0x1200)), 'entries from the directory: ' + a.ram(0x1200));
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
  for (const x of [0xFD80, 0xFD83, 0xFD86, 0xFD89]) assert(rom(x) === 0x4C, `JMP at $${x.toString(16)}`);
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

function credits() {
  const save = new SaveArea();
  const boot = () => { const a = new Arcade(SD_CAB, ROM, save); a.waitFor(() => inList(a), 1500, 'cabinet list'); a.frames(10); return a; };
  // coins in the front-end: one credit per pulse, at most 9; factory settings: every game in free play
  const a = boot();
  assert(a.cred === 0 && a.field() === 'FREE PLAY', 'no credits, free play: ' + a.cred + ' ' + a.field());
  a.coin(COIN1);
  a.coin(COIN2);
  assert(a.cred === 2, 'two coins: ' + a.cred);
  a.setSys(COIN1); a.frames(30); a.setSys(0); a.frames(4);
  assert(a.cred === 3, 'one long pulse = one credit: ' + a.cred);
  for (let i = 0; i < 10; i++) a.coin(i & 1 ? COIN1 : COIN2);
  assert((a.cred & 15) === 9, 'at most 9: ' + a.cred);
  // GAME SETTINGS from the system test: all COIN, then 1 vs 1 back to FREE PLAY
  a.setSys(SERVICE); a.frames(4); a.setSys(0);
  a.waitFor(() => a.rows()[11].includes('LINE SENT'), 1500, 'system test');
  assert(a.rows()[13].includes('BUTTON 1: GAME SETTINGS'), 'settings hint');
  a.press(B1);
  a.waitFor(() => a.rows()[0].includes('GAME SETTINGS'), 30, 'settings page');
  let r = a.rows();
  assert(r[4].includes('ALL GAMES  >  FREE PLAY') && a.nameAt(4, 1) >= 0x80, 'first row: ' + r[4]);
  assert(r[6].startsWith(' 1 vs 1 Basketball ..') && r[6].trimEnd().endsWith('FREE PLAY'), 'game row: ' + r[6]);
  assert(!r.join('').includes('Jukebox'), 'no Jukebox (no zone)');
  a.shot('game_settings');
  a.press(D); a.press(B1);                            // ALL GAMES > COIN
  assert(a.rows()[6].trimEnd().endsWith(' COIN') && a.rows()[19].trimEnd().endsWith(' COIN'), 'all coin');
  a.press(D); a.press(B1);                            // 1 vs 1: FREE PLAY
  r = a.rows();
  assert(r[6].trimEnd().endsWith('FREE PLAY') && r[7].trimEnd().endsWith(' COIN') && a.nameAt(6, 1) >= 0x80, 'one game: ' + r[6]);
  a.press(B2);                                        // save and exit
  a.waitFor(() => inList(a), 120, 'list after the settings');
  assert(a.field() === 'CREDITS 9' && (a.cred & 15) === 9, 'credits kept, coin mode: ' + a.field());
  const sec = save.read(32769);
  assert(String.fromCharCode(...sec.slice(0, 4)) === 'ARCS' && sec[4] === 1 && sec[16 + 2] === 1 && sec[16 + 8] === 2 && sec[16 + 35] === 2, 'settings sector');
  let sum = 0; for (let i = 0; i < 510; i++) sum = (sum + sec[i]) & 0xFFFF;
  assert(sec[510] === (sum & 0xFF) && sec[511] === sum >> 8, 'settings checksum');
  a.shot('list_credits');

  // power-on again: credits lost, settings read back; a game the front-end launches (Times Tables) needs a credit
  const b = boot();
  assert(b.cred === 0 && b.field() === 'CREDITS 0', 'after power-on: ' + b.cred + ' ' + b.field());
  b.select('Times Tables');
  b.press(B1);
  b.waitFor(() => b.nameAt(13, 23) === 128 + 95, 300, 'times tables page');
  b.frames(3);
  assert(b.field() === 'INSERT COIN', 'insert coin: ' + b.field());
  b.shot('insert_coin');
  b.serial.length = 0;
  b.press(ST); b.frames(30);
  assert(!b.serialText().includes('[GAME]') && b.field() === 'INSERT COIN', 'no launch without a credit');
  b.coin(COIN2);
  assert(b.field() === 'CREDITS 1', 'one credit on the page: ' + b.field());
  b.press(ST);
  b.waitFor(() => b.serialText().includes('[GAME]'), 1500, 'times tables launched');
  assert(b.cred === 0, 'credit taken by the front-end: ' + b.cred);

  // a game that takes its credits itself (Asteroids, COIN): the front-end takes none; the NMI counts the coins
  const c = boot();
  c.coin(COIN1); c.coin(COIN1);
  c.select('Asteroids');
  c.press(B2);                                        // from the gallery
  c.waitFor(() => c.nameAt(13, 23) === 128 + 95, 300, 'asteroids picture');
  c.frames(3);
  assert(c.field() === 'CREDITS 2', 'gallery field: ' + c.field());
  c.serial.length = 0;
  c.press(ST);
  c.waitFor(() => c.serialText().includes('[GAME] ASTEROIDS'), 1500, 'asteroids launched');
  c.waitFor(() => c.m.cpu.pc < 0x8000, 50, 'asteroids running');
  assert(c.cred === 2, 'no credit taken, not free play: ' + c.cred);
  c.frames(200);
  c.coin(COIN2, 3);                                   // a pulse of 50 ms during the game
  assert((c.cred & 15) === 3, 'coin counted in the game: ' + c.cred);
  c.shot('game_credits');
  c.setJoy(ST, ST);                                   // (a game started now: the NMI comes every other frame)
  const held = c.waitFor(() => inList(c), 900, 'back from the game');
  c.setJoy(0, 0);
  if (process.env.DUMP) console.log('both START held for', held, 'frames');
  const left = c.cred & 15;
  assert(left >= 1 && c.field() === 'CREDITS ' + left, 'credits kept after the game: ' + c.field());

  // a game in FREE PLAY: bit 4 set at the launch, no credit taken
  const d = boot();
  d.coin(COIN1);
  d.select('1 vs 1 Basketball');
  d.press(B1);
  d.waitFor(() => d.nameAt(13, 23) === 128 + 95, 300, '1 vs 1 page');
  d.frames(3);
  assert(d.field() === 'FREE PLAY', 'free play game: ' + d.field());
  d.serial.length = 0;
  d.press(ST);
  d.waitFor(() => d.serialText().includes('[GAME]'), 1500, '1 vs 1 launched');
  assert(d.cred === 0x11, 'free play bit, credit kept: ' + d.cred.toString(16));

  // a coin while a picture is read from the SD (no frame is waited for about 1 s)
  const e = boot();
  e.press(B1, 0, 2);
  e.frames(12);
  assert(e.nameAt(13, 23) !== 128 + 95, 'picture still loading');
  e.coin(COIN1, 3);
  e.waitFor(() => e.nameAt(13, 23) === 128 + 95, 300, 'picture');
  assert((e.cred & 15) === 1, 'coin during the SD read: ' + e.cred);

  // JT_ARC_USE_CREDIT / JT_ARC_CREDITS from a program in RAM
  const f = boot();
  f.cred = 3;
  const prog = [0xA9, 0x02, 0x20, 0x89, 0xFD, 0x08, 0x68, 0x8D, 0x00, 0x0F,   // LDA #2, JSR $FD89, flags -> $0F00
    0xA9, 0x02, 0x20, 0x89, 0xFD, 0x08, 0x68, 0x8D, 0x01, 0x0F,               // again -> $0F01
    0xA2, 0x5A, 0xA0, 0xA5, 0x20, 0x86, 0xFD, 0x8D, 0x02, 0x0F, 0x08, 0x68, 0x8D, 0x03, 0x0F,  // LDX/LDY, JSR $FD86
    0x8E, 0x04, 0x0F, 0x8C, 0x05, 0x0F, 0x80, 0xFE];                           // X/Y kept, BRA *
  f.m.poke(0x0E00, prog);
  f.m.cpu.pc = 0x0E00; f.frames(2);
  assert((f.ram(0x0F00) & 1) === 0 && (f.ram(0x0F01) & 1) === 1 && f.cred === 1, 'use credit: ' + f.ram(0x0F00) + ' ' + f.ram(0x0F01) + ' ' + f.cred);
  assert(f.ram(0x0F02) === 1 && (f.ram(0x0F03) & 1) === 0 && f.ram(0x0F04) === 0x5A && f.ram(0x0F05) === 0xA5, 'credits: ' + f.ram(0x0F02));
  f.cred = 0x13;                                      // free play
  f.m.cpu.pc = 0x0E00; f.frames(2);
  assert((f.ram(0x0F00) & 1) === 0 && (f.ram(0x0F01) & 1) === 0 && f.cred === 0x13 && (f.ram(0x0F03) & 1) === 1 && f.ram(0x0F02) === 3, 'free play: nothing taken');
  console.log('      credits: coins (max 9), GAME SETTINGS saved on the SD, INSERT COIN, game credits, NMI, free play, jump table: ok');
}

export default async function () {
  const a = listAndPage();
  launchAndExit(a);
  jukebox();
  gallery();
  titleScreen();
  joystickTest();
  systemTest();
  serialCommands();
  plainSd();
  noCard();
  jumpTable();
  credits();
}
