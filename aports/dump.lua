---------
-- Dump packages info into JSON.
----
local cjson = require('cjson')
local pkgmod = require('aports.pkg')

local get_maintainer = pkgmod.get_maintainer
local push = table.insert


-- Tables with this metatable are encoded as an array by our patched cjson.
local empty_array_mt = { __name = 'array' }

local empty_array = setmetatable({}, empty_array_mt)

--- Converts pkg's `arch` map into list of architectures.
-- Negated architecture is prefixed by "!".
--
-- @tparam {[string]=bool,...} arch
-- @treturn {string,...}
local function convert_arch(arch)
	local t = {}
	for name, value in pairs(arch) do
		push(t, value and name or '!'..name)
	end
	return t
end

--- "Marks" the given table to be encoded as a JSON array.
local function array(tab)
	return #tab == 0
		and empty_array
		or setmetatable(tab, empty_array_mt)
end

--- Converts the `pkg` into a simple table (map) that can be serialized.
--
-- @tparam table pkg The package table (see @{db.split_apkbuild}).
-- @treturn table A simple map of values.
local function pkg_to_table(pkg)
	return {
		pkgname = pkg.pkgname,
		pkgver = pkg.pkgver,
		pkgrel = tonumber(pkg.pkgrel),
		pkgdesc = pkg.pkgdesc,
		url = pkg.url,
		license = pkg.license,
		arch = array(convert_arch(pkg.arch)),
		depends = array(pkg.depends),
		makedepends = array(pkg.makedepends),
		checkdepends = array(pkg.checkdepends),
		subpackages = array(pkg.subpackages),
		source = array(pkg.source),
		maintainer = get_maintainer(pkg),
	}
end


local M = {}

--- Dumps packages from the given iterator to a map indexed by package name.
function M.pkgs_to_map(iter, state)
	local t = {}
	for pkg in iter, state do
		t[pkg.pkgname] = pkg_to_table(pkg)
	end
	return t
end

--- Dumps packages from the given iterator to JSON.
-- @see pkgs_to_map
function M.pkgs_to_json(iter, state)
	cjson.encode_sort_keys = true
	return cjson.encode(M.pkgs_to_map(iter, state))
end

return M
