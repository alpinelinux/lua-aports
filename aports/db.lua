
local M = {}
local abuild = require('aports.abuild')
local pkg = require('aports.pkg')

local function split_subpkgs(str)
	local t = {}
	local e
	if (str == nil) then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = string.gsub(e, ":.*", "")
	end
	return t
end

local function split(str)
	local t = {}
	local e
	if (str == nil) then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = e
	end
	return t
end

local function split_apkbuild(line)
	local r = {}
	local dir,pkgname, pkgver, pkgrel, arch, depends, makedepends, subpackages, source, url = string.match(line, "([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
	r.dir = dir
	r.pkgname = pkgname
	r.pkgver = pkgver
	r.pkgrel = pkgrel
	r.depends = split(depends)
	r.makedepends = split(makedepends)
	r.subpackages = split_subpkgs(subpackages)
	r.source = split(source)
	r.url = url
	return r
end

-- parse the APKBUILDs and return an iterator
local function parse_apkbuilds(aportsdir, repos)
	local i,v, p
	local str=""
	if repos == nil then
		return nil
	end
	--expand repos
	for _,repo in pairs(repos) do
		str = ("%s %s/%s/*/APKBUILD"):format(str, aportsdir, repo)
	end

	local p = io.popen(". "..abuild.functions..";"..[[
		for i in ]]..str..[[; do
			pkgname=
			pkgver=
			pkgrel=
			arch=
			depends=
			makedepends=
			subpackages=
			source=
			url=
			dir="${i%/APKBUILD}";
			[ -n "$dir" ] || exit 1;
			cd "$dir";
			. ./APKBUILD;
			echo $dir\|$pkgname\|$pkgver\|$pkgrel\|$arch\|$depends\|$makedepends\|$subpackages\|$source\|$url ;
		done;
	]])
	return function()
		local line = p:read("*line")
		if line == nil then
			p:close()
			return nil
		end
		return split_apkbuild(line)
	end
end

local function init_apkdb(aportsdir, repos)
	local pkgdb = {}
	local revdeps = {}
	local a
	for a in parse_apkbuilds(aportsdir, repos) do
	--	io.write(a.pkgname.." "..a.pkgver.."\t"..a.dir.."\n")
		if pkgdb[a.pkgname] == nil then
			pkgdb[a.pkgname] = {}
		end
		pkg.init(a)
		table.insert(pkgdb[a.pkgname], a)
		-- add subpackages to package db
		local k,v
		for k,v in pairs(a.subpackages) do
			if pkgdb[v] == nil then
				pkgdb[v] = {}
			end
			table.insert(pkgdb[v], a)
		end
		-- add to reverse dependencies
		for v in pairs(a:all_deps()) do
			if revdeps[v] == nil then
				revdeps[v] = {}
			end
			table.insert(revdeps[v], a)
		end
	end
	return pkgdb, revdeps
end

local Aports = {}
function Aports:recursive_dependencies(pn)
	local visited={}
	local apkdb = self.apks

	return coroutine.wrap(function()
		function recurs(pn)
			if pn == nil or visited[pn] or apkdb[pn] == nil then
				return false
			end
			visited[pn] = true
			local _, p
			for _, p in pairs(apkdb[pn]) do
				local d
				for d in pairs(p:all_deps()) do
					if recurs(d) then
						return true
					end
				end
			end
			coroutine.yield(pn)
		end
		return recurs(pn)
	end)
end

function Aports:target_packages(pkgname)
	return coroutine.wrap(function()
		for k,v in pairs(self.apks[pkgname]) do
			coroutine.yield(pkgname.."-"..v.pkgver.."-r"..v.pkgrel..".apk")
		end
	end)
end

function Aports:each_name()
	local apks = self.apks
	return coroutine.wrap(function()
		for k,v in pairs(self.apks) do
			coroutine.yield(k,v)
		end
	end)
end

function Aports:each_reverse_dependency(pkg)
	return coroutine.wrap(function()
		for k,v in pairs(self.revdeps[pkg] or {}) do
			coroutine.yield(k,v)
		end
	end)
end

function Aports:each_pkg_with_name(name)
	if self.apks[name] == nil then
		io.stderr:write("WARNING: "..name.." has no data\n")
	end
	return coroutine.wrap(function()
		for index, pkg in pairs(self.apks[name]) do
			coroutine.yield(pkg, index)
		end
	end)
end

function Aports:each()
	return coroutine.wrap(function()
		for name, pkglist in self:each_name() do
			for _, pkg in pairs(pkglist) do
				coroutine.yield(pkg, name)
			end
		end
	end)
end

function Aports:each_aport()
	return coroutine.wrap(function()
		for pkg, name in self:each() do
			if name == pkg.pkgname then
				coroutine.yield(pkg)
			end
		end
	end)
end

function Aports:each_need_build()
	return coroutine.wrap(function()
		for aport in self:each_aport() do
			if not aport:apk_file_exists() then
				coroutine.yield(aport)
			end
		end
	end)
end

function M.new(aportsdir, ...)
	local h = Aports
	h.aportsdir = aportsdir
	h.repos = {...}
	h.apks, h.revdeps = init_apkdb(aportsdir, h.repos)
	return h
end

return M
