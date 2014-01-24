
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

function M.get_apk_file_name(pkg, name)
	return (name or pkg.pkgname).."-"..pkg.pkgver.."-r"..pkg.pkgrel..".apk"
end

function M.get_apk_file_path(pkg, name)
	if abuild.pkgdest ~= nil and abuild.pkgdest ~= "" then
		return abuild.pkgdest.."/"..M.get_apk_file_name(pkg, name)
	end
	if abuild.repodest ~= nil and abuild.repodest ~= "" then
		return abuild.repodest.."/"..M.get_repo_name(pkg).."/"..abuild.arch.."/"..M.get_apk_file_name(pkg, name)
	end
	return pkg.dir.."/"..M.get_apk_file_name(pkg, name)
end

function M.apk_file_exists(pkg, name)
	-- technically we check if it is readable...
	local filepath = M.get_apk_file_path(pkg, name)
	local f = io.open(filepath)
	if f == nil then
		return false
	end
	f:close()
	return true
end

function M.arch_enabled(pkg)
	return pkg.arch.all or pkg.arch.noarch or pkg.arch[abuild.arch]
end

function M.init(pkg)
	pkg.all_deps = M.all_deps
	pkg.remote_sources = M.remote_sources
	pkg.get_maintainer = M.get_maintainer
	pkg.get_repo_name = M.get_repo_name
	pkg.get_apk_file_name = M.get_apk_file_name
	pkg.get_apk_file_path = M.get_apk_file_path
	pkg.apk_file_exists = M.apk_file_exists
	pkg.arch_enabled = M.arch_enabled
end
return M
