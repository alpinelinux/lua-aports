-- abuild_spec.lua

local posix = require("posix")

describe("abuild", function()
	local tmpdir

	setup(function()
		tmpdir = os.tmpname()
		local abuild_conf = tmpdir .. "/abuild.conf"
		os.remove(tmpdir)
		local lfs = require("lfs")
		lfs.mkdir(tmpdir)
		local f = io.open(abuild_conf, "w")
		f:write(
			"CARCH=aarch64\n"
				.. "CLIBC=musl\n"
				.. "MYVAR=myvalue\n"
				.. "REPODEST="
				.. tmpdir
				.. "\n"
				.. "CHOST=aarch64-alpine-linux-musl\n"
		)
		f:close()
		posix.stdlib.setenv("ABUILD_USERCONF", abuild_conf)
		package.path = "?.lua;" .. package.path
	end)

	teardown(function()
		require("pl.dir").rmtree(tmpdir)
		posix.stdlib.setenv("ABUILD_USERCONF", nil)
	end)

	describe("get_conf", function()
		local abuild = require("aports.abuild")
		it("should return the value of a configuration variable from the user config", function()
			assert.equal("myvalue", abuild.get_conf("MYVAR"))
		end)
	end)

	describe("get_arch", function()
		local abuild = require("aports.abuild")
		it("should return the CARCH value from the environment", function()
			posix.stdlib.setenv("CARCH", "foobar")
			assert.equal("foobar", abuild.get_arch())
			posix.stdlib.setenv("CARCH", nil)
		end)

		it("should return the CARCH value from user config", function()
			assert.equal("aarch64", abuild.get_arch())
			assert.equal("aarch64", abuild.arch)
		end)
	end)

	describe("get_libc", function()
		local abuild = require("aports.abuild")
		it("should return the libc value from the user config", function()
			assert.equal("musl", abuild.get_libc())
			assert.equal("musl", abuild.libc)
		end)
	end)

	describe("abuild.repodest", function()
		local abuild = require("aports.abuild")
		it("should contain the REPODEST value from the user config", function()
			assert.equal(tmpdir, abuild.repodest)
		end)
	end)

	describe("abuild.chost", function()
		local abuild = require("aports.abuild")
		it("should contain the CHOST value from the user config", function()
			assert.equal("aarch64-alpine-linux-musl", abuild.chost)
		end)
	end)
end)
