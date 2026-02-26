PREFIX?=/usr/local
DESTDIR?=/

instowl: instowl.janet
	sed 's@\./src/@instowl/@' $< > $@

.PHONY:
install: instowl $(wildcard src/*)
	install -D -m 755 -T instowl $(DESTDIR)/$(PREFIX)/bin/instowl
	install -D -m 644 -t $(DESTDIR)/$(PREFIX)/lib/janet/instowl $(wordlist 2,$(words $^),$^)

