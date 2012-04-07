.SUFFIXES: .c .s

.c.s:
	./compile $< > $@

%.bin: %.s
	#./as16 $< | grep -Pv "^(LABEL|LINKED)" | ruby -e 'puts STDIN.read.split' > $@
	./dasm $< temp.bin
	ruby -e 'File.open("temp.bin", "rb") { |f| f.read }.bytes.each_slice(2) { |a,b| printf("%02x%02x\n", b, a) }' > $@
	rm temp.bin

clean:
	rm -f *.s
	rm -f *.bin