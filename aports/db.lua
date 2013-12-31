
local abuild = require('aports.abuild')
local M = {}

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
local function parse_apkbuilds(dirs)
	local i,v, p
	local str=""
	if dirs == nil then
		return nil
	end
	--expand repos
	for i,v in ipairs(dirs) do
		str = str..v.."/*/APKBUILD "
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



-- return a key list with makedepends and depends
function M.all_deps(p)
	local m = {}
	local k,v
	if p == nil then
		return m
	end
	if type(p.depends) == "table" then
		for k,v in pairs(p.depends) do
			m[v] = true
		end
	end
	if type(p.makedepends) == "table" then
		for k,v in pairs(p.makedepends) do
			m[v] = true
		end
	end
	return m
end

function M.is_remote(url)
	local _,pref
	for _,pref in pairs{ "^http://", "^ftp://", "^https://", ".*::.*" } do
		if string.match(url, pref) then
			return true
		end
	end
	return false
end

-- iterator for all remote sources of given pkg/aport
function M.remote_sources(p)
	if p == nil or type(p.source) ~= "table" then
		return nil
	end
	return coroutine.wrap(function()
		for _,url in pairs(p.source) do
			if M.is_remote(url) then
				coroutine.yield(url)
			end
		end
	end)
end

function M.get_maintainer(pkg)
	if pkg == nil or pkg.dir == nil then
		return nil
	end
	local f = io.open(pkg.dir.."/APKBUILD")
	if f == nil then
		return nil
	end
	local line
	for line in f:lines() do
		local maintainer = line:match("^%s*#%s*Maintainer:%s*(.*)")
		if maintainer then
			f:close()
			return maintainer
		end
	end
	f:close()
	return nil
end

function M.get_repo_name(pkg)
	if pkg == nil or pkg.dir == nil then
		return nil
	end
	return string.match(pkg.dir, ".*/(.*)/.*")
end

function M.get_apk_filename(pkg)
	return pkg.pkgname.."-"..pkg.pkgver.."-r"..pkg.pkgrel..".apk"
end

function M.get_apk_file_path(pkg)
	local pkgdest = abuild.get_conf("PKGDEST")
	if pkgdest ~= nil and pkgdest ~= "" then
		return pkgdest.."/"..M.get_apk_filename(pkg)
	end
	local repodest = abuild.get_conf("REPODEST")
	if repodest ~= nil and repodest ~= "" then
		local arch = abuild.get_conf("CARCH")
		return repodest.."/"..M.get_repo_name(pkg).."/"..arch.."/"..M.get_apk_filename(pkg)
	end
	return pkg.dir.."/"..M.get_apk_filename(pkg)
end


local function init_apkdb(repodirs)
	local pkgdb = {}
	local revdeps = {}
	local a
	for a in parse_apkbuilds(repodirs) do
	--	io.write(a.pkgname.." "..a.pkgver.."\t"..a.dir.."\n")
		if pkgdb[a.pkgname] == nil then
			pkgdb[a.pkgname] = {}
		end
		a.all_deps = M.all_deps
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
		for v in pairs(M.all_deps(a)) do
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
				for d in pairs(M.all_deps(p)) do
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

function Aports:each()
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

function Aports:each_pkg(pkg, f)
	if self.apks[pkg] == nil then
		io.stderr:write("WARNING: "..pkg.." has no data\n")
	end
	return coroutine.wrap(function()
		for k,v in pairs(self.apks[pkg]) do
			coroutine.yield(k,v)
		end
	end)
end

function Aports:each_aport()
	return coroutine.wrap(function()
		for pkgname,v in self:each() do
			for _,pkg in self:each_pkg(pkgname) do
				if pkgname == pkg.pkgname then
					coroutine.yield(pkg)
				end
			end
		end
	end)
end

function M.new(repodirs)
	local h = Aports
	h.repodirs = repodirs
	h.apks, h.revdeps = init_apkdb(repodirs)
	return h
end

return M
