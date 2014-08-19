
local M = {}
local abuild_conf = {}
M.conf_file = "/etc/abuild.conf"
M.functions = "/usr/share/abuild/functions.sh"

function M.get_conf(var)
	-- check cache
	if abuild_conf[var] ~= nil then
		return abuild_conf[var]
	end

	-- use os env var
	abuild_conf[var] = os.getenv(var)
	if abuild_conf[var] ~= nil then
		return abuild_conf[var]
	end

	-- parse config file
	local f = io.popen(" . "..M.conf_file..' ; echo -n "$'..var..'"')
	abuild_conf[var] = f:read("*all")
	f:close()
	return abuild_conf[var]
end

local function get_cached_var(var)
	if abuild_conf[var] then
		return abuild_conf[var]
	end
	local f = io.popen((' . %s ; echo -n "$%s"'):format(M.functions, var))
	abuild_conf[var] = f:read("*all")
	f:close()
	return abuild_conf[var]
end

function M.get_arch()
	return get_cached_var("CARCH")
end

function M.get_libc()
	return get_cached_var("CLIBC")
end

M.arch = M.get_arch()
M.libc = M.get_libc()
M.repodest = M.get_conf("REPODEST")
M.pkgdest = M.get_conf("PKGDEST")
M.chost = M.get_conf("CHOST")


return M
