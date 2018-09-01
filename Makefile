
VERSION = 0.7.0
LUA_VERSION = 5.3
prefix ?= /usr
sharedir ?= $(prefix)/share
luasharedir ?= $(sharedir)/lua/$(LUA_VERSION)
bindir ?= $(prefix)/bin
# Shebang to replace "/usr/bin/env lua" with. If empty, shebang is keep
# unchanged (default).
luashebang ?=

aportsfiles = \
	abuild.lua \
	apkrepo.lua \
	db.lua \
	dump.lua \
	pkg.lua

binfiles = buildrepo.lua ap.lua

all:
	@echo "To install run:"
	@echo "  make install DESTDIR=<targetroot>"

# Note: -i.tmp is needed for compatibility with both GNU and BSD sed.
install: $(addprefix bin/,$(binfiles)) $(addprefix aports/,$(aportsfiles))
	install -d $(DESTDIR)$(luasharedir)/aports \
		$(DESTDIR)$(bindir)
	install -m644 $(addprefix aports/,$(aportsfiles)) \
		$(DESTDIR)$(luasharedir)/aports/
	for file in $(binfiles); do \
		install -m755 bin/$$file $(DESTDIR)$(bindir)/$${file%.lua} || exit 1; \
		if [ -n "$(luashebang)" ]; then \
			sed -i.tmp "s|^#!/usr/bin/env lua|#!$(luashebang)|" \
				$(DESTDIR)$(bindir)/$${file%.lua} || exit 1; \
			rm $(DESTDIR)$(bindir)/$${file%.lua}.tmp; \
		fi; \
	done

check: lint

lint:
	luacheck aports bin
