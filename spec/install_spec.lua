local lfs = require("lfs")
local path = require("pl.path")

local function mktmpdir()
	local dir = os.tmpname()
	os.remove(dir)
	assert(lfs.mkdir(dir))
	return dir
end

local function shell_quote(s)
	return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

local function run(cmd)
	local ok, why, code = os.execute(cmd)
	if type(ok) == "number" then
		return ok == 0, ok
	end
	return ok == true and code == 0, code or why
end

local function slurp(file)
	local f = assert(io.open(file, "r"))
	local data = f:read("*a")
	f:close()
	return data
end

describe("install", function()
	local tmpdir
	local cwd

	setup(function()
		cwd = assert(lfs.currentdir())
	end)

	before_each(function()
		tmpdir = mktmpdir()
	end)

	after_each(function()
		require("pl.dir").rmtree(tmpdir)
	end)

	it("should install scripts and libraries using the configured Lua version", function()
		local quoted_tmpdir = shell_quote(tmpdir)
		local ok = run(
			"cd " .. shell_quote(cwd) .. " && make install-lib install-bin DESTDIR=" .. quoted_tmpdir .. " prefix=/usr"
		)
		assert.is_true(ok)

		local version = io.popen("cd " .. shell_quote(cwd) .. " && make -s print-lua-version"):read("*l")
		assert.is_truthy(version)

		local ap = path.join(tmpdir, "usr/bin/ap")
		local buildrepo = path.join(tmpdir, "usr/bin/buildrepo")
		local lib = path.join(tmpdir, "usr/share/lua", version, "aports", "db.lua")

		assert.is_truthy(lfs.attributes(ap, "mode"))
		assert.is_truthy(lfs.attributes(buildrepo, "mode"))
		assert.is_truthy(lfs.attributes(lib, "mode"))

		assert.equal("#!/usr/bin/lua" .. version, slurp(ap):match("([^\n]*)"))
		assert.equal("#!/usr/bin/lua" .. version, slurp(buildrepo):match("([^\n]*)"))
	end)
end)
