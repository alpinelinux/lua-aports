#!/usr/bin/lua5.2

local lfs = require("lfs")

-- subcommands -----------------------
local subcmd = {}
local deprecated = {}

subcmd.revdep = {
	desc = "Print reverse dependencies",
	usage = "PKG...",
	run = function(db, opts)
		for i = 1, #opts do
			for _, pkg in db:each_reverse_dependency(opts[i]) do
				print(pkg.pkgname)
			end
		end
	end,
}

subcmd.list = {
	desc = "Print all packages built from aports tree",
	usage = "",
	run = function(db)
		for _, pn in db:each() do
			print(pn)
		end
	end,
}

subcmd["recursive-deps"] = {
	desc = "Recursively print all make dependencies for given packages",
	usage = "PKG...",
	run = function(db, opts)
		for i = 1, #opts do
			for dep in db:recursive_dependencies(opts[i]) do
				print(dep)
			end
		end
	end,
}

-- for backwards compatiblity
subcmd.recursdeps = {
	desc = "Alias to recursive-deps for compatibility",
	usage = "PKG...",
	run = subcmd["recursive-deps"].run,
}
deprecated.recursdeps = true

subcmd["recursive-revdeps"] = {
	desc = "Recursively print all reverse make dependencies for given packages",
	usage = "PKG...",
	run = function(db, opts)
		for i = 1, #opts do
			for dep in db:recursive_reverse_dependencies(opts[i]) do
				print(dep)
			end
		end
	end,
}

subcmd.builddirs = {
	desc = "Print the build dirs for given packages in build order",
	usage = "PKG...",
	run = function(db, opts)
		for pkg in db:each_in_build_order(opts) do
			print(pkg.dir)
		end
	end,
}

subcmd.sources = {
	desc = "List sources",
	usage = "PKG...",
	run = function(db, opts)
		for i = 1, #opts do
			for pkg in db:each_pkg_with_name(opts[i]) do
				for url in pkg:remote_sources() do
					print(pkg.pkgname, pkg.pkgver, string.gsub(url, pkg.pkgver, "$VERSION"))
				end
			end
		end
	end,
}

subcmd["build-list"] = {
	desc = "List packages that can/should be rebuilt",
	usage = "",
	run = function(db)
		local nlist = {}
		for pkg in db:each_need_build() do
			table.insert(nlist, pkg.pkgname)
		end
		for pkg in db:each_in_build_order(nlist) do
			print(pkg.dir)
		end
	end,
}

subcmd["apk-list"] = {
	desc = "List all apk files",
	usage = "",
	run = function(db)
		for pkg in db:each() do
			if pkg:relevant() then
				print(pkg:get_apk_file_name())
			end
		end
	end,
}

subcmd["dump-json"] = {
	desc = "Dump all abuilds from aports tree to JSON",
	run = function(db)
		local dump = require("aports.dump")
		print(dump.pkgs_to_json(db:each_aport()))
	end,
}

subcmd["toplevel-aports"] = {
	desc = "List top-level aports",
	run = function(db)
		for p in db:each_aport() do
			if not db.revdeps[p.pkgname] then
				print(p.pkgname)
			end
		end
	end,
}

local function print_usage()
	io.write("usage: ap -d <DIR> SUBCOMMAND [options]\n\nSubcommands are:\n")
	for k in pairs(subcmd) do
		if not deprecated[k] then
			print("  " .. k)
		end
	end
end

-- those should be read from some config file
local repodirs = {}

-- parse args
local opts = {}
local help = false
do
	local i = 1
	while i <= #arg do
		if arg[i] == "-d" then
			i = i + 1
			repodirs[#repodirs + 1] = arg[i]
		elseif arg[i] == "-h" then
			help = true
		else
			opts[#opts + 1] = arg[i]
		end
		i = i + 1
	end
end

local cmd = table.remove(opts, 1)

if help or not cmd then
	print_usage()
	-- usage
	return
end

if #repodirs == 0 then
	if lfs.attributes("APKBUILD") then
		repodirs[1] = string.gsub(lfs.currentdir(), "(.*)/.*", "%1")
	else
		repodirs[1] = lfs.currentdir()
	end
end

if subcmd[cmd] and type(subcmd[cmd].run) == "function" then
	for _, dir in pairs(repodirs) do
		local db = require("aports.db").new(dir:match("(.*)/([^/]*)"))
		subcmd[cmd].run(db, opts)
	end
else
	io.stderr:write(cmd .. ": invalid subcommand\n")
end
