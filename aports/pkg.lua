
local M = {}
local abuild = require('aports.abuild')
local lfs = require('lfs')

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
	local repodest = pkg.repodest or abuild.repodest
	if pkg.repodest == nil and abuild.pkgdest ~= nil and abuild.pkgdest ~= "" then
		return abuild.pkgdest.."/"..M.get_apk_file_name(pkg, name)
	end
	if repodest ~= nil and repodest ~= "" then
		return repodest.."/"..M.get_repo_name(pkg).."/"..abuild.arch.."/"..M.get_apk_file_name(pkg, name)
	end
	return pkg.dir.."/"..M.get_apk_file_name(pkg, name)
end

function M.apk_file_exists(pkg, name)
	-- technically we check if it is readable...
	local filepath = M.get_apk_file_path(pkg, name)
        if lfs.attributes(filepath) == nil then
		io.stderr:write(("DEBUG: path=%s\n"):format(filepath))
	end
	return lfs.attributes(filepath) ~= nil
end

function M.all_apks_exists(pkg)
	if not pkg:apk_file_exists() then
		return false
	end
	for _, subpkgname in pairs(pkg.subpackages) do
		if not pkg:apk_file_exists(subpkgname) then
			return false
		end
	end
	return true
end

function M.arch_enabled(pkg)
	return not pkg.arch["!"..abuild.arch] and (pkg.arch.all or pkg.arch.noarch or pkg.arch[abuild.arch])
end

function M.libc_enabled(pkg)
	return not pkg.options["!libc_"..abuild.libc]
end

function M.relevant(pkg)
	return pkg:arch_enabled() and pkg:libc_enabled()
end

function M.each_dependency(pkg)
	return coroutine.wrap(function()
		for _,dep in pairs(pkg.depends or {}) do
			coroutine.yield(dep)
		end
		for _,dep in pairs(pkg.makedepends or {}) do
			coroutine.yield(dep)
		end
	end)
end


function M.init(pkg, repodest)
	for k,v in pairs(M) do
		pkg[k] = v
	end
	pkg.repodest = repodest
end

return M
