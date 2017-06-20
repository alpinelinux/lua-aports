
local M = {}
local abuild = require('aports.abuild')
local pkg = require('aports.pkg')

local function split_subpkgs(str, linguas, pkgname)
	local t = {}
	local e
	if (str == nil) then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = string.gsub(e, ":.*", "")
	end
	for k,v in pairs(linguas) do
		t[#t + 1] = ("%s-lang-%s"):format(pkgname, v)
	end
	return t
end

local function split_deps(str)
	local t = {}
	local e
	if (str == nil) then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = string.gsub(e, "[=<>].*", "")
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

local function split_key(str)
	local t = {}
	for _,key in pairs(split(str)) do
		t[key] = true
	end
	return t
end

local function split_apkbuild(line)
	if line == nil then
		return nil
	end
	local r = {}
	local dir, pkgname, pkgver, pkgrel, arch, license, options, depends,
		makedepends, checkdepends, subpackages, linguas, source, url =
		string.match(line, string.rep("([^\\]*)", 14, "\\"))
	r.dir = dir
	r.pkgname = pkgname
	r.pkgver = pkgver
	r.pkgrel = pkgrel
	r.license = license
	r.depends = split_deps(depends)
	r.makedepends = split_deps(makedepends)
	r.checkdepends = split_deps(checkdepends)
	r.linguas = split(linguas)
	r.subpackages = split_subpkgs(subpackages, r.linguas, pkgname)
	r.source = split(source)
	r.url = url
	r.arch = split_key(arch)
	r.options = split_key(options)
	return r
end

-- parse the APKBUILDs and return an iterator
local function apkbuilds_open(aportsdir, repos)
	local i,v, p
	local str=""
	if repos == nil then
		return nil
	end
	--expand repos
	for _,repo in pairs(repos) do
		str = ("%s %s/%s/*/APKBUILD"):format(str, aportsdir, repo)
	end

	local obj = {}
	obj.handle = io.popen(". "..abuild.functions..";"..[[
		for i in ]]..str..[[; do
			pkgname=
			pkgver=
			pkgrel=
			arch=
			license=
			options=
			depends=
			makedepends=
			checkdepends=
			subpackages=
			linguas=
			source=
			url=
			dir="${i%/APKBUILD}";
			[ -n "$dir" ] || exit 1;
			cd "$dir";
			. ./APKBUILD;
			echo $dir\\$pkgname\\$pkgver\\$pkgrel\\$arch\\$license\\$options\\$depends\\$makedepends\\$checkdepends\\$subpackages\\$linguas\\$source\\$url ;
		done;
	]])
	obj.read = function(self)
		return function()
			return split_apkbuild(self.handle:read("*line"))
		end

	end
	obj.close = function(self)
		return self.handle:close()
	end
	return obj
end

local function init_apkdb(aportsdir, repos, repodest)
	local pkgdb = {}
	local revdeps = {}
	local apkbuilds = apkbuilds_open(aportsdir, repos)
	for a in apkbuilds:read() do
	--	io.write(a.pkgname.." "..a.pkgver.."\t"..a.dir.."\n")
		if pkgdb[a.pkgname] == nil then
			pkgdb[a.pkgname] = {}
		end
		pkg.init(a, repodest)
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
		for dep in a:each_dependency() do
			if revdeps[dep] == nil then
				revdeps[dep] = {}
			end
			table.insert(revdeps[dep], a)
		end
	end
	if not apkbuilds:close() then
		return nil
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
				return nil
			end
			visited[pn] = true
			local _, p
			for _, p in pairs(apkdb[pn]) do
				for dep in p:each_dependency() do
					if recurs(dep) then
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

function Aports:each_known_dependency(pkg)
	return coroutine.wrap(function()
		for dep in pkg:each_dependency() do
			if self.apks[dep] then
				coroutine.yield(dep)
			end
		end
	end)
end

function Aports:each_pkg_with_name(name)
	if self.apks[name] == nil then
		io.stderr:write("WARNING: "..name..": not provided by any known APKBUILD\n")
		return function() return nil end
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
			if aport:relevant() and not aport:all_apks_exists() then
				coroutine.yield(aport)
			end
		end
	end)
end

function Aports:each_in_build_order(namelist)
	local pkgs = {}
	for _,name in pairs(namelist) do
		for pkg in self:each_pkg_with_name(name) do
			pkgs[pkg.dir] = true
		end
	end

	return coroutine.wrap(function()
		for _,name in pairs(namelist) do
			for dep in self:recursive_dependencies(name) do
				for pkg in self:each_pkg_with_name(dep) do
					if pkgs[pkg.dir] then
						coroutine.yield(pkg)
						pkgs[pkg.dir] = nil
					end
				end
			end
		end
	end)
end

function Aports:git_describe()
	local cmd = ("git --git-dir %s/.git describe"):format(self.aportsdir)
	local f = io.popen(cmd)
	if f == nil then
		return nil
	end
	local result = f:read("*line")
	f:read("*a")
	f:close()
	return result
end

function Aports:known_deps_exists(pkg)
	for name in self:each_known_dependency(pkg) do
		for dep in self:each_pkg_with_name(name) do
			if dep.pkgname ~= pkg.pkgname and dep:relevant() and not dep:all_apks_exists() then
				return nil
			end
		end
	end
	return true
end

function M.new(aportsdir, repos, repodest)
	local h = Aports
	h.aportsdir = aportsdir
	if type(repos) == "table" then
		h.repos = repos
	else
		h.repos = { repos }
	end
	h.apks, h.revdeps = init_apkdb(aportsdir, h.repos, repodest)
	if h.apks == nil then
		return nil, h.revdeps
	end
	return h
end

return M
