// Bundles arcade.test.ts against the emulator sources and runs it
//   node test/run.mjs                  tests tmp/arcade.bin with tmp/sd_arcade.img
//   BIOS_ROM=<file.bin> node test/run.mjs
// Needs: sh make.sh, node tools/make_arcade_sd.mjs, and ../bo6502-emulator, ../bo6502-SDbuilder next to this project.
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const slash = p => p.split(String.fromCharCode(92)).join('/');
const EMU = slash(join(here, '..', '..', 'bo6502-emulator'));
const { build } = createRequire(join(EMU, 'package.json'))('esbuild');
const out = join(here, '..', 'tmp', 'arcade_test.mjs');
await build({
  entryPoints: [join(here, 'arcade.test.ts')], outfile: out, bundle: true, platform: 'node', format: 'esm',
  logLevel: 'error', alias: { EMU }, define: { __dirname_: JSON.stringify(slash(here)) },
});
const mod = await import(pathToFileURL(out).href);
try { await mod.default(); console.log('ALL OK'); } catch (e) { console.error('FAIL ' + (e.stack || e)); process.exit(1); }
