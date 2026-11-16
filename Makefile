# gdrive-sync — install layout for distribution packages.
#
#   make install DESTDIR="$pkgdir" PREFIX=/usr
#
# Units go to the systemd *user* unit directory, so every user on the
# system can run their own instance with `systemctl --user`. Nothing is
# enabled or started here; each user runs `gdrive-sync-setup` instead.

PREFIX       ?= /usr
BINDIR       ?= $(PREFIX)/bin
DATADIR      ?= $(PREFIX)/share/gdrive-sync
LICENSEDIR   ?= $(PREFIX)/share/licenses/gdrive-sync
USERUNITDIR  ?= $(PREFIX)/lib/systemd/user

INSTALL      ?= install

SCRIPTS = bin/gdrive-sync bin/gdrive-sync-watch bin/gdrive-sync-full bin/gdrive-sync-setup
UNITS   = $(wildcard systemd/*.service systemd/*.timer)

.PHONY: all install uninstall check

all:

install:
	$(INSTALL) -Dm755 -t "$(DESTDIR)$(BINDIR)" $(SCRIPTS)
	$(INSTALL) -dm755 "$(DESTDIR)$(USERUNITDIR)"
	for unit in $(UNITS); do \
		sed 's|/usr/bin/|$(BINDIR)/|g' "$$unit" > "$(DESTDIR)$(USERUNITDIR)/$${unit##*/}"; \
		chmod 644 "$(DESTDIR)$(USERUNITDIR)/$${unit##*/}"; \
	done
	$(INSTALL) -Dm644 filters/bisync-filters.txt "$(DESTDIR)$(DATADIR)/bisync-filters.txt"
	$(INSTALL) -Dm644 LICENSE "$(DESTDIR)$(LICENSEDIR)/LICENSE"

uninstall:
	rm -f $(addprefix "$(DESTDIR)$(BINDIR)"/,$(notdir $(SCRIPTS)))
	rm -f $(addprefix "$(DESTDIR)$(USERUNITDIR)"/,$(notdir $(UNITS)))
	rm -rf "$(DESTDIR)$(DATADIR)" "$(DESTDIR)$(LICENSEDIR)"

check:
	bash -n $(SCRIPTS)
