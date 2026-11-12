// Arcade catalog writer: adds to an SD image (made by bo6502-SDbuilder) the list, the previews
// and the descriptions that the front-end of the Arcade BIOS shows (format in frontend.s).
//
// - The list: the GAME programs of the SD directory (not the keyboard versions of Zork) in
//   alphabetical order, then the MiniVIC Jukebox (the songs are played only through it).
// - The previews: every program is taken from the SD image itself, run on the core of the
//   bo6502-emulator (miniVIC with the KEYB/SD BIOS, this same SD inserted) for 450 frames
//   like the games test of the emulator, and its screen is reduced to 128x96 pixels in TMS9918
//   tiles (2 colours per 8-pixel row).
// - The texts: title, players and description from the games table of the README of
//   miniVIC_games, the inspiring game from the description ("Atari 1979: ...") or from
//   gameslist.md ("original game in place of ..."), or from the INSPIRED table below.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { buildMachine, defaultConfig } from 'EMU/src/machines/profiles';
import { SdCardBoard } from 'EMU/src/boards/Boards';
import { TMS_PALETTE, SCREEN_W, BORDER_X, BORDER_Y } from 'EMU/src/devices/TMS9918A';
import { deflateSync, crc32 } from 'node:zlib';

export const CAT_LBA = 24576;
const PAGE_OFS = 64;
const SECTOR = 512;
const TEXT_COLS = 30;
const DESC_LINES = 14;

/** inspiring game of the titles whose README description does not name it */
const INSPIRED: Record<string, [string, string]> = {
  CENTIPEDE: ['Centipede', 'Atari 1981'],
  MISSILECOMMAND: ['Missile Command', 'Atari 1980'],
  LUNARLANDER: ['Lunar Lander', 'Atari 1979'],
  THEWARRIORS: ['Street Fighter', 'Capcom 1987'],
  ZORKIJOYSTICK: ['Zork I', 'Infocom 1980'],
  ZORKIIJOYSTICK: ['Zork II', 'Infocom 1981'],
  ZORKIIIJOYSTICK: ['Zork III', 'Infocom 1982'],
};

export interface DirEntry { slot: number; name: string; type: number; load: number; len: number; entry: number; nameLen: number }
export interface CatEntry {
  slot: number; kind: number; title: string; lines: string[]; preview?: { pat: Uint8Array; col: Uint8Array };
}

const norm = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, '');
const ascii = (s: string) => s.replace(/\*([^*\s][^*]*)\*/g, '$1').replace(/[–—]/g, '-').replace(/×/g, 'x')
  .replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[^\x20-\x7e]/g, '');

/** the BOGS directory of an SD image */
export function readDirectory(img: Uint8Array): DirEntry[] {
  const out: DirEntry[] = [];
  const b0 = img.subarray(0, SECTOR);
  if (String.fromCharCode(...b0.subarray(0, 4)) !== 'BOGS') throw new Error('no BOGS directory on the SD image');
  const total = b0[15] || b0[5];
  for (let page = 0; page * 9 < total; page++) {
    const b = img.subarray(page * 0x8000, page * 0x8000 + SECTOR);
    for (let i = 0; i < b[5]; i++) {
      const p = 16 + i * 8, n = 96 + i * 32;
      let name = '';
      for (let k = 0; k < 31 && b[n + k]; k++) name += String.fromCharCode(b[n + k]);
      out.push({
        slot: page * 9 + i, name, type: b[p + 6], nameLen: b[p + 7],
        load: b[p] | (b[p + 1] << 8), len: b[p + 2] | (b[p + 3] << 8), entry: b[p + 4] | (b[p + 5] << 8),
      });
    }
  }
  return out;
}

interface GameInfo { file: string; title: string; players: string; desc: string }

/** the games table of the README of miniVIC_games */
function readGames(gamesDir: string): GameInfo[] {
  const md = readFileSync(join(gamesDir, 'README.md'), 'utf8');
  const out: GameInfo[] = [];
  for (const line of md.split(/\r?\n/)) {
    const m = /^\|\s*`([^`]+)\.asm`\s*\|\s*\*\*(.+?)\*\*\s*\|\s*([^|]+?)\s*\|\s*(.+?)\s*\|\s*$/.exec(line);
    if (m) out.push({ file: m[1], title: ascii(m[2]), players: ascii(m[3]), desc: ascii(m[4]) });
  }
  return out;
}

/** "original game in place of X" of gameslist.md, by normalized title */
function readInPlaceOf(gamesDir: string): Map<string, string> {
  const map = new Map<string, string>();
  const f = join(gamesDir, 'gameslist.md');
  if (!existsSync(f)) return map;
  for (const line of readFileSync(f, 'utf8').split(/\r?\n/)) {
    const m = /^\|\s*\*\*(.+?)\*\*\s*\(original game in place of (.+?)\)/.exec(line);
    if (m) map.set(norm(m[1]), ascii(m[2]).split(',')[0]);
  }
  return map;
}

/** words wrapped at `cols` columns */
export function wrap(text: string, cols: number): string[] {
  const lines: string[] = [];
  let cur = '';
  for (const w of text.split(/\s+/).filter(Boolean)) {
    if (!cur) cur = w.slice(0, cols);
    else if (cur.length + 1 + w.length <= cols) cur += ' ' + w;
    else { lines.push(cur); cur = w.slice(0, cols); }
  }
  if (cur) lines.push(cur);
  return lines;
}

/** description in at most `max` lines: whole sentences if possible, otherwise cut with "..." */
export function fitText(text: string, cols: number, max: number): string[] {
  const all = wrap(text, cols);
  if (all.length <= max) return all;
  const sentences = text.match(/[^.!?]+[.!?]+(\s|$)|[^.!?]+$/g) ?? [text];
  let best = '';
  for (const s of sentences) {
    const next = (best + ' ' + s.trim()).trim();
    if (wrap(next, cols).length > max) break;
    best = next;
  }
  if (best) return wrap(best, cols);
  const cut = all.slice(0, max);
  cut[max - 1] = cut[max - 1].slice(0, cols - 3) + '...';
  return cut;
}

function headerLines(title: string, info: GameInfo | undefined, inPlace: Map<string, string>): [string, string] {
  const key = norm(title);
  const players = info ? `Players: ${info.players.replace(/\s/g, '')}` : '';
  const m = info && /^([A-Z][A-Za-z]+) (19\d\d|20\d\d)[:,]/.exec(info.desc);
  let from = '', made = '';
  if (m) { from = info!.title; made = `${m[1]} ${m[2]}`; }
  else if (inPlace.has(key)) { from = inPlace.get(key)!; made = 'Original game'; }
  else if (INSPIRED[key]) [from, made] = INSPIRED[key];
  else if (info && /^An original/i.test(info.desc)) made = 'Original game';
  const l0 = from ? (`Inspired by: ${from}`.length <= 31 ? `Inspired by: ${from}` : `After ${from}`) : made;
  const l1 = from ? [made, players].filter(Boolean).join(' - ') : players;
  return [l0.slice(0, 31), l1.slice(0, 31)];
}

/** program screen after `frames` frames (palette indices of the 256x192 active area) */
export function captureScreen(img: Uint8Array, d: DirEntry, rom: Uint8Array, frames = 450): Uint8Array {
  const m = buildMachine(defaultConfig('minivic'));
  m.loadRom(rom);
  (m.board<SdCardBoard>('sdcard') as any).card.insert(img.slice());
  m.powerOn();
  for (let i = 0; i < 60; i++) m.runFrame();
  const start = d.slot * 0x8000 + 0x1000;
  m.poke(d.load, img.subarray(start, start + d.len));
  m.cpu.pc = d.entry;
  m.cpu.sp = 0xFF;
  for (let i = 0; i < frames; i++) m.runFrame();
  const f = m.vdu!.vdp.frame, out = new Uint8Array(256 * 192);
  for (let y = 0; y < 192; y++) for (let x = 0; x < 256; x++) {
    const c = f[(y + BORDER_Y) * SCREEN_W + x + BORDER_X];
    out[y * 256 + x] = c || 1;
  }
  return out;
}

const dist = (a: number, b: number) => {
  const p = TMS_PALETTE[a], q = TMS_PALETTE[b];
  return (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2;
};

/** 256x192 screen -> 128x96 preview: 192 tiles (16 x 12) of patterns and colours */
export function makePreview(scr: Uint8Array): { pat: Uint8Array; col: Uint8Array; px: Uint8Array } {
  const px = new Uint8Array(128 * 96);
  for (let y = 0; y < 96; y++) for (let x = 0; x < 128; x++) {
    const n = new Map<number, number>();
    for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
      const c = scr[(y * 2 + dy) * 256 + x * 2 + dx];
      n.set(c, (n.get(c) ?? 0) + 1);
    }
    // the most frequent colour; with a tie the brightest one (thin lines survive)
    px[y * 128 + x] = [...n].sort((a, b) => b[1] - a[1] || TMS_PALETTE[b[0]].reduce((s, v) => s + v, 0) - TMS_PALETTE[a[0]].reduce((s, v) => s + v, 0))[0][0];
  }
  const pat = new Uint8Array(192 * 8), col = new Uint8Array(192 * 8), out = new Uint8Array(px.length);
  for (let t = 0; t < 192; t++) {
    const tx = (t % 16) * 8, ty = Math.floor(t / 16) * 8;
    for (let r = 0; r < 8; r++) {
      const row = Array.from({ length: 8 }, (_, i) => px[(ty + r) * 128 + tx + i]);
      const n = new Map<number, number>();
      for (const c of row) n.set(c, (n.get(c) ?? 0) + 1);
      const order = [...n].sort((a, b) => b[1] - a[1]).map(e => e[0]);
      const fg = order[0], bg = order[1] ?? order[0];
      let bits = 0;
      row.forEach((c, i) => {
        const on = c === fg || (c !== bg && dist(c, fg) <= dist(c, bg));
        if (on) bits |= 0x80 >> i;
        out[(ty + r) * 128 + tx + i] = on ? fg : bg;
      });
      pat[t * 8 + r] = bits;
      col[t * 8 + r] = (fg << 4) | bg;
    }
  }
  return { pat, col, px: out };
}

/** text sector: 16 lines of 32 bytes */
export function textSector(lines: string[]): Uint8Array {
  const s = new Uint8Array(SECTOR);
  lines.slice(0, 16).forEach((l, i) => { for (let k = 0; k < Math.min(31, l.length); k++) s[i * 32 + k] = l.charCodeAt(k); });
  return s;
}

/** writes the catalog into the image (extended if it is shorter) and returns it */
export function writeCatalog(img: Uint8Array, entries: CatEntry[], title: string): Uint8Array {
  const end = (CAT_LBA + PAGE_OFS + entries.length * 8) * SECTOR;
  if (img.length < end) { const big = new Uint8Array(end); big.set(img); img = big; }
  const base = CAT_LBA * SECTOR;
  img.fill(0, base, base + PAGE_OFS * SECTOR);
  img.set([0x41, 0x52, 0x43, 0x44, 1, entries.length], base);
  for (let k = 0; k < Math.min(31, title.length); k++) img[base + 16 + k] = title.charCodeAt(k);
  entries.forEach((e, i) => {
    const o = base + SECTOR + i * 32;
    img[o] = e.slot; img[o + 1] = e.kind; img[o + 2] = (e.preview ? 1 : 0) | (e.lines.length ? 2 : 0);
    for (let k = 0; k < Math.min(23, e.title.length); k++) img[o + 8 + k] = e.title.charCodeAt(k);
    const p = (CAT_LBA + PAGE_OFS + i * 8) * SECTOR;
    img.fill(0, p, p + 8 * SECTOR);
    img.set(textSector(e.lines), p);
    if (e.preview) { img.set(e.preview.pat, p + SECTOR); img.set(e.preview.col, p + 4 * SECTOR); }
  });
  return img;
}

export interface Options { sd: string; out: string; games: string; rom: string; title: string; previews?: string; songs?: boolean }

export function buildCatalog(o: Options): CatEntry[] {
  let img = new Uint8Array(readFileSync(o.sd));
  const dir = readDirectory(img);
  const games = readGames(o.games), inPlace = readInPlaceOf(o.games);
  const rom = new Uint8Array(readFileSync(o.rom));
  const byKey = new Map<string, GameInfo>();
  for (const g of games) { byKey.set(norm(g.title), g); byKey.set(norm(g.file), g); }
  const pick = dir.filter(d => d.type === 1 && !/KEYBOARD/.test(d.name));
  const entries: CatEntry[] = pick.map(d => {
    const info = byKey.get(norm(d.name));
    const title = info ? info.title : d.name.replace(/\w\S*/g, w => w[0] + w.slice(1).toLowerCase());
    const head = headerLines(title, info, inPlace);
    const desc = info ? fitText(info.desc, TEXT_COLS, DESC_LINES) : [];
    return { slot: d.slot, kind: 1, title, lines: [...head, ...desc], _d: d } as CatEntry & { _d: DirEntry };
  }).sort((a, b) => a.title.localeCompare(b.title));
  const juke = dir.find(d => d.name.startsWith('JUKEBOX'));
  if (juke) {
    const songs = dir.filter(d => d.type === 4).map(d => d.name.replace(/\w\S*/g, w => w[0] + w.slice(1).toLowerCase()));
    const text = 'The MiniVIC Jukebox plays the songs of MiniVIC Sound on the two AY-3-8910 sound chips, '
      + 'in stereo. Choose a song with the joystick.' + (songs.length ? ` Songs on this card: ${songs.join(', ')}.` : '');
    entries.push({ slot: juke.slot, kind: 2, title: 'MiniVIC Jukebox', lines: ['MiniVIC Sound', 'Music player', ...fitText(text, TEXT_COLS, DESC_LINES)], _d: juke } as any);
  }
  if (entries.length > 255) throw new Error('more than 255 entries');
  if (o.previews) mkdirSync(o.previews, { recursive: true });
  for (const e of entries as (CatEntry & { _d: DirEntry })[]) {
    const pv = makePreview(captureScreen(img, e._d, rom));
    e.preview = { pat: pv.pat, col: pv.col };
    if (o.previews) writePngTo(o.previews, e._d.name, pv.px);
    delete (e as any)._d;
  }
  img = writeCatalog(img, entries, o.title);
  writeFileSync(o.out, img);
  return entries;
}

/** PNG file of palette indices */
export function writePngTo(dir: string, name: string, px: Uint8Array, w = 128, h = 96) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0;
    for (let x = 0; x < w; x++) for (const v of TMS_PALETTE[px[y * w + x]]) raw[o++] = v;
  }
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  writeFileSync(join(dir, name.replace(/[^A-Za-z0-9]+/g, '_') + '.png'), Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]));
}
