
LUA_VERSION=5.2
prefix?=/usr
sharedir?=$(prefix)/share
luasharedir?=$(sharedir)/lua/$(LUA_VERSION)
bindir?=$(prefix)/bin

aportsfiles= \
	abuild.lua \
	apkrepo.lua \
	db.lua \
	pkg.lua

binfiles=buildrepo.lua

all:
	@echo "To install run:"
	@echo "  make install DESTDIR=<targetroot>"

install: $(binfiles) $(addprefix aports/,$(aportsfiles))
	install -d $(DESTDIR)$(luasharedir)/aports \
		$(DESTDIR)$(bindir)
	install -m644 $(addprefix aports/,$(aportsfiles)) \
		$(DESTDIR)$(luasharedir)/aports/
	for file in $(binfiles); do \
		install -m755 $$file $(DESTDIR)$(bindir)/$${file%.lua} || exit 1; \
	done
