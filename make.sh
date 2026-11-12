# Builds the Arcade BIOS: tmp/arcade.bin (32 KB, the whole EEPROM image $8000-$FFFF)
mkdir -p tmp
ca65 -D boogs msbasic.s -o tmp/arcade.o &&
ld65 -C boogs.cfg tmp/arcade.o -o tmp/arcade.bin -Ln tmp/arcade.lbl -m tmp/arcade.map &&
echo "tmp/arcade.bin"
