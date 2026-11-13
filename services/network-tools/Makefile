TARGET_ARCH :=$(shell uname -m)
CC ?= cc
CPPFLAGS ?=
CFLAGS ?=
LDFLAGS ?=
LDLIBS ?=

.PHONY: all install clean package

all: arp_read arp_write dhcp_discover script_wrapper

arp_read: arp_read.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -std=gnu11 $(LDFLAGS) -o $@ $< -lpcap -lhiredis $(LDLIBS)

arp_write: arp_write.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -std=gnu11 $(LDFLAGS) -o $@ $< -lnet -lhiredis $(LDLIBS)

dhcp_discover: dhcp_discover.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $< -lnet -lpcap $(LDLIBS)

script_wrapper: script_wrapper.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

# Where to put executable commands on 'make install'?
BIN = $(DESTDIR)/opt/eblocker-network/bin
SYSTEMD = $(DESTDIR)/lib/systemd/system

install: all
	install -d $(BIN)
	install ./arp_read $(BIN)
	install ./arp_write $(BIN)
	install ./dhcp_discover $(BIN)
	install ./script_wrapper $(BIN)
	install -d $(SYSTEMD)
	install -m 644 ./etc/arpwrite.service $(SYSTEMD)
	install -m 644 ./etc/arpread.service $(SYSTEMD)

clean:
	rm -f arp_read arp_write dhcp_discover script_wrapper

package:
	dpkg-buildpackage -us -uc

