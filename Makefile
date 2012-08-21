PREFIX := /usr/local

all: apache-vsl

# Docs are shipped pre-compiled
doc: apache-vsl.8 apache-vsl.8.html

apache-vsl.8: apache-vsl
	pod2man -c '' -r '' -s 8 $< >$@

apache-vsl.8.html: apache-vsl
	pod2html $< >$@
	rm -f pod2htmd.tmp pod2htmi.tmp

test:
	@perl -MConfig::General -e 'print "Config::General is installed.\n";'
	@perl -MGetopt::Long -e 'print "Getopt::Std is installed.\n";'
	@perl -MPod::Usage -e 'print "Pod::Usage is installed.\n";'
	@perl -MPOSIX -e 'print "POSIX is installed.\n";'
	@perl -MFile::Path -e 'print "File::Path is installed.\n";'
	@perl -MFile::Basename -e 'print "File::Basename is installed.\n";'
	@perl -MFile::Spec -e 'print "File::Spec is installed.\n";'
	@perl -MCwd -e 'print "Cwd is installed.\n";'
	@echo 'All tests complete.'

install: all
	install -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	install -d -m 0755 $(DESTDIR)$(PREFIX)/share/man/man8
	install -m 0755 apache-vsl $(DESTDIR)$(PREFIX)/bin
	install -m 0644 apache-vsl.8 $(DESTDIR)$(PREFIX)/share/man/man8

distclean: clean

clean:

doc-clean:
	rm -f apache-vsl.8 apache-vsl.8.html