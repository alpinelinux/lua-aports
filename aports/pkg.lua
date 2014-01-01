
local M = {}
local abuild = require('aports.abuild')

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

function M.get_apk_file_name(pkg)
	return pkg.pkgname.."-"..pkg.pkgver.."-r"..pkg.pkgrel..".apk"
end

function M.get_apk_file_path(pkg)
	local pkgdest = abuild.get_conf("PKGDEST")
	if pkgdest ~= nil and pkgdest ~= "" then
		return pkgdest.."/"..M.get_apk_file_name(pkg)
	end
	local repodest = abuild.get_conf("REPODEST")
	if repodest ~= nil and repodest ~= "" then
		local arch = abuild.get_arch()
		return repodest.."/"..M.get_repo_name(pkg).."/"..arch.."/"..M.get_apk_file_name(pkg)
	end
	return pkg.dir.."/"..M.get_apk_file_name(pkg)
end

function M.apk_file_exists(pkg)
	-- technically we check if it is readable...
	local filepath = M.get_apk_file_path(pkg)
	local f = io.open(filepath)
	if f == nil then
		return false
	end
	f:close()
	return true
end

function M.init(pkg)
	pkg.all_deps = M.all_deps
	pkg.remote_sources = M.remote_sources
	pkg.get_maintainer = M.get_maintainer
	pkg.get_repo_name = M.get_repo_name
	pkg.get_apk_file_name = M.get_apk_file_name
	pkg.get_apk_file_path = M.get_apk_file_path
	pkg.apk_file_exists = M.apk_file_exists
end
return M
