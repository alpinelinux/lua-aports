buildrepo(1)

# NAME

*buildrepo* - build an apk repository tree

# SYNOPSIS

*buildrepo* [-hknps] [-a _DIR_] [-d _DIR_] [-l _DIR_] [-r _REPO_] _REPO_...

# DESCRIPTION

*buildrepo* builds an apk repository tree, taking care to build dependant
packages in the correct order. *buildrepo* shall skip packages that are already
up to date.

# OPTIONS

*-a, --aports=DIR*
	Set the aports base dir to _DIR_ instead of _$HOME/aports_.

*-c, --config=FILE*
	Use _FILE_ as config instead of _/etc/buildrepo/config.lua_.

*-d, --destdir=DIR*
	Set destination repository base to _DIR_ instead of _$HOME/packages_.

*-h, --help*
	Show help and exit.

*-l, --logdir=DIR*
	Create build logs in _DIR/REPO/pkgname/_ instead of stdout.

*-k, --keep-going*
	Keep going, even if packages fails.

*-n, --dry-run*
	Dry run. Don't actually build or delete, just print

*-p, --purge*
	Purge obsolete packages from _REPODIR_ after build.

*-r, --deps-repo=REPO*
	Dependencies are found in _REPO_.

*-s, --skip-failed*
	Skip those which previously failed (src dir exists).

*-R, --rootbld*
	Build packages in clean chroots.

# EXAMPLE

```
CBUILD=aarch64 buildrepo -d "$HOME/packages" -a "$(pwd)" -p -R builder
```

# SEE ALSO

abuild(1), APKBUILD(5), apk(8)

# AUTHORS

Natanael Copa <_ncopa@alpinelinux.org_> and other lua-aports authors
