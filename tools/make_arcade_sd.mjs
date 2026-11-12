// Adds the arcade catalog (list, previews, descriptions) to an SD image of bo6502-SDbuilder.
//   node tools/make_arcade_sd.mjs [--sd IN.img] [--out OUT.img] [--games DIR] [--rom BIOS.bin]
//                                 [--apps DIR] [--title "MINIVIC ARCADE"] [--previews DIR]
// Defaults: ../bo6502-SDbuilder/sd_full.img -> tmp/sd_arcade.img, ../MiniVIC Games (README.md,
// gameslist.md, screenshots/), ../MiniVIC Apps (screenshots/jukebox_play.png), the KEYB/SD BIOS of ../bo6502-emulator (used to run the programs for the previews),
// previews as PNG in tmp/previews. The emulator sources are expected in ../bo6502-emulator.
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const slash = p => p.split(String.fromCharCode(92)).join('/');
const EMU = slash(join(root, '..', 'bo6502-emulator'));
const { build } = createRequire(join(EMU, 'package.json'))('esbuild');
const out = join(root, 'tmp', 'arcade_sd.mjs');
await build({
  entryPoints: [join(here, 'arcade_sd.ts')], outfile: out, bundle: true, platform: 'node', format: 'esm',
  logLevel: 'error', alias: { EMU },
});
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf('--' + name); return i >= 0 ? args[i + 1] : def; };
const { buildCatalog } = await import(pathToFileURL(out).href);
const entries = buildCatalog({
  sd: opt('sd', join(root, '..', 'bo6502-SDbuilder', 'sd_full.img')),
  out: opt('out', join(root, 'tmp', 'sd_arcade.img')),
  games: opt('games', join(root, '..', 'MiniVIC Games')),
  apps: opt('apps', join(root, '..', 'MiniVIC Apps')),
  rom: opt('rom', join(EMU, 'public', 'roms', 'minivic_keybsd.bin')),
  title: opt('title', 'MINIVIC ARCADE'),
  previews: opt('previews', join(root, 'tmp', 'previews')),
});
for (const e of entries) console.log(`${String(e.slot).padStart(3)} ${e.kind === 2 ? 'music' : 'game '} ${e.title.padEnd(24)} ${(e.source ?? '').padEnd(10)} ${e.lines[0] ?? ''} | ${e.lines[1] ?? ''}`);
console.log(`${entries.length} entries`);
