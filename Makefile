.SUFFIXES: .c .s

.c.s:
	./compile $< > $@

%.hex: %.s
	./a16 $<
	mv out.hex $@

clean:
	rm -f *.s
	rm -f *.hex