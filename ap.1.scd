ap(1)

# NAME

*ap* - query and analyze an aports tree

# SYNOPSIS

*ap* [-h] [-d _DIR_] _SUBCOMMAND_ [_PKG_...]

# DESCRIPTION

*ap* queries and analyzes an aports tree, providing information about packages,
dependencies, and build requirements.

# OPTIONS

*-d, --dir=DIR*
	Use _DIR_ as repository directory instead of current directory.

*-h, --help*
	Show help and exit.

# SUBCOMMANDS

*revdep* _PKG_...
	Print reverse dependencies for specified packages.

*list*
	Print all packages built from aports tree.

*recursive-deps* _PKG_...
	Recursively print all make dependencies for specified packages.

*recursive-revdeps* _PKG_...
	Recursively print all reverse make dependencies for specified packages.

*builddirs* _PKG_...
	Print the build directories for specified packages in build order.

*sources* _PKG_...
	List sources for specified packages.

*build-list*
	List packages that can/should be rebuilt.

*apk-list*
	List all apk files.

*dump-json*
	Dump all abuilds from aports tree to JSON.

*toplevel-aports*
	List top-level aports (packages with no reverse dependencies).

# EXAMPLE

```
cd ~/aports/main/ && ap recursive-revdeps python3
```

# CAVEATS

ap(1) operates on a single repository and will not find (reverse) dependencies
across repositories (e.g.: it will not find dependants in community for a
package in main).

# SEE ALSO

buildrepo(1), abuild(1), APKBUILD(5), apk(8)

# AUTHORS

Natanael Copa <_ncopa@alpinelinux.org_> and other lua-aports authors
