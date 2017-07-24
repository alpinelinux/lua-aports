#!/usr/bin/lua5.2

local lfs = require('lfs')

local function build_is_outdated(pkg)
	local apk_attr = lfs.attributes(aports.get_apk_file_path(pkg))
	local apkbuild_attr = lfs.attributes(pkg.dir.."/APKBUILD")
	if apk_attr == nil then
		return true
	end
	return os.difftime(apk_attr.modification, apkbuild_attr.modification) < 0
end

local function build_is_missing(pkg)
	return lfs.attributes(aports.get_apk_file_path(pkg)) == nil
end

-- subcommands -----------------------
subcmd = {}
subcmd.revdep = {
	desc = "Print reverse dependencies",
	usage = "PKG...",
	run = function(opts)
		local i
		for i = 1, #opts do
			for _,pkg in db:each_reverse_dependency(opts[i]) do
				print(pkg.pkgname)
			end
		end
	end
}

subcmd.list = {
	desc = "Print all packages built from aports tree",
	usage = "",
	run = function()
		for _,pn in db:each() do
			print(pn)
		end
	end
}

subcmd.recursdeps = {
	desc = "Recursively print all make dependencies for given packages",
	usage = "PKG...",
	run = function (opts)
		for i = 1, #opts do
			for dep in db:recursive_dependencies(opts[i]) do
				print(dep)
			end
		end
	end
}

subcmd.builddirs = {
	desc = "Print the build dirs for given packages in build order",
	usage = "PKG...",
	run = function(opts)
		for pkg in db:each_in_build_order(opts) do
			print(pkg.dir)
		end
	end
}

subcmd.sources = {
	desc = "List sources",
	usage = "PKG...",
	run = function(opts)
		local i, p, _
		for i = 1, #opts do
			for pkg in db:each_pkg_with_name(opts[i]) do
				for url in pkg:remote_sources() do
					print(pkg.pkgname, pkg.pkgver, string.gsub(url, pkg.pkgver, "$VERSION"))
				end
			end
		end
	end
}

subcmd["build-list"] = {
	desc = "List packages that can/should be rebuilt",
	usage = "",
	run = function()
		local nlist = {}
		for pkg in db:each_need_build() do
			table.insert(nlist, pkg.pkgname)
		end
		for pkg in db:each_in_build_order(nlist) do
			print(pkg.dir)
		end
	end
}

subcmd["apk-list"] = {
	desc = "List all apk files",
	usage = "",
	run = function()
		for pkg in db:each() do
			if pkg:relevant() then
				print(pkg:get_apk_file_name())
			end
		end
	end
}

subcmd["dump-json"] = {
	desc = "Dump all abuilds from aports tree to JSON",
	run = function()
		local dump = require "aports.dump"
		print(dump.pkgs_to_json(db:each_aport()))
	end
}

function print_usage()
	io.write("usage: ap -d <DIR> SUBCOMMAND [options]\n\nSubcommands are:\n")
	local k,v
	for k in pairs(subcmd) do
		print("  "..k)
	end
end

-- those should be read from some config file
repodirs = {}


-- parse args
i = 1
opts = {}
help = false
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


cmd = table.remove(opts, 1)

if cmd == nil then
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
	for _,dir in pairs(repodirs) do
	db = require('aports.db').new(dir:match("(.*)/([^/]*)"))
	loadtime = os.clock()
	subcmd[cmd].run(opts)
	runtime = os.clock() - loadtime
--	io.stderr:write("db load time = "..tostring(loadtime).."\n")
--	io.stderr:write("cmd run time = "..tostring(runtime).."\n")
	end
else
	io.stderr:write(cmd..": invalid subcommand\n")
end

