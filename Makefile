AS86    =as86 -0 -a
LD86    =ld86 -0

AS      =as
LD      =ld
LDFLAGS =-m elf_i386 -Ttext 0 -e startup_32 -s -x -M

all: a.img

a.img: boot system
	dd bs=32 if=boot of=a.img skip=1
	objcopy -O binary system head
	cat head >> a.img

boot: boot.o
	$(LD86) -s -o $@ $<

boot.o: boot.s
	$(AS86) -o $@ $<

head.o: head.s
	$(AS) --32 -c -o $@ $<

system:	head.o
	$(LD) $(LDFLAGS) head.o  -o system > System.map

run: a.img
	bochs -q -f ./linux.bxrc
win: a.img
	bochs -q -f ./win.bxrc
x: a.img
	bochs -q -f ./x.bxrc

clean:
	rm -rf a.img boot boot.o head head.o system System.map bochsout.txt
