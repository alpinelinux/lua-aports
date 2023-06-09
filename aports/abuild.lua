local M = {}
local abuild_conf = {}
M.functions = "/usr/share/abuild/functions.sh"

function M.get_conf(var)
	-- check cache
	local value = os.getenv(var) or abuild_conf[var]
	if value ~= nil then
		return value
	end

	-- execute functions.sh
	local f = io.popen((' . %s ; printf "%%s" "$%s"'):format(M.functions, var))
	abuild_conf[var] = f:read("*all")
	f:close()
	return abuild_conf[var]
end

function M.get_arch()
	return M.get_conf("CARCH")
end

function M.get_libc()
	return M.get_conf("CLIBC")
end

M.arch = M.get_arch()
M.libc = M.get_libc()
M.repodest = M.get_conf("REPODEST")
M.pkgdest = M.get_conf("PKGDEST")
M.chost = M.get_conf("CHOST")

return M
