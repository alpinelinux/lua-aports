
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

function M.get_arch()
	if abuild_conf.CARCH then
		return abuild_conf.CARCH
	end
	local f = io.popen(" . "..M.functions..' ; echo -n "$CARCH"')
	abuild_conf.CARCH = f:read("*all")
	f:close()
	return abuild_conf.CARCH
end

return M
