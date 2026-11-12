# Builds the Arcade BIOS: tmp/arcade.bin (32 KB, the whole EEPROM image $8000-$FFFF)
# and writes the ROM checksum at $FDFE (16-bit sum of $8000-$AFFF and $E000-$FFFF without those two bytes)
mkdir -p tmp
ca65 -D boogs msbasic.s -o tmp/arcade.o &&
ld65 -C boogs.cfg tmp/arcade.o -o tmp/arcade.bin -Ln tmp/arcade.lbl -m tmp/arcade.map &&
node -e "
const fs = require('fs'), f = 'tmp/arcade.bin', b = fs.readFileSync(f), at = 0xFDFE - 0x8000;
let s = 0;
for (let i = 0; i < b.length; i++) if ((i < 0x3000 || i >= 0x6000) && i !== at && i !== at + 1) s = (s + b[i]) & 0xFFFF;
b[at] = s & 0xFF; b[at + 1] = s >> 8; fs.writeFileSync(f, b);
console.log('tmp/arcade.bin, ROM sum \$' + s.toString(16).toUpperCase().padStart(4, '0'));
"
