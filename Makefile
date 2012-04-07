.SUFFIXES: .c .s

.c.s:
	@echo "dc16cc $<"
	@./compile $< > $@

%.bin: %.s Makefile
	@echo "dasm $<"
	@./dasm $< temp.bin
	@ruby -e 'File.open("temp.bin", "rb") { |f| f.read }.bytes.each_slice(2) { |a,b| printf("%02x%02x\n", b, a) }' > $@
	@rm temp.bin

clean:
	rm -f *.s
	rm -f *.bin