
VERSION = 1.3.1
LUA_VERSION = 5.5
prefix ?= /usr
sharedir ?= $(prefix)/share
luasharedir ?= $(sharedir)/lua/$(LUA_VERSION)
bindir ?= $(prefix)/bin

aportsfiles = \
	abuild.lua \
	apkrepo.lua \
	db.lua \
	dump.lua \
	pkg.lua

binfiles = buildrepo.lua ap.lua

all: doc

doc: buildrepo.1 ap.1

%: %.scd
	scdoc < '$<' > '$@'

install: all $(addprefix bin/,$(binfiles)) $(addprefix aports/,$(aportsfiles))
	install -d $(DESTDIR)$(luasharedir)/aports/
	install -m644 $(addprefix aports/,$(aportsfiles)) \
		$(DESTDIR)$(luasharedir)/aports/
	for file in $(binfiles); do \
		sed '1s|^#!.*|#!/usr/bin/lua$(LUA_VERSION)|' bin/$$file > $(DESTDIR)$(bindir)/$${file%.lua} || exit 1; \
		chmod 755 $(DESTDIR)$(bindir)/$${file%.lua} || exit 1; \
	done
	install -Dm644 buildrepo.1	$(DESTDIR)$(prefix)/share/man/man1/buildrepo.1
	install -Dm644 ap.1			$(DESTDIR)$(prefix)/share/man/man1/ap.1

check: lint
	env -i busted-$(LUA_VERSION) --verbose

lint:
	luacheck aports bin
