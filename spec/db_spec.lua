-- abuild_spec.lua

local lfs = require("lfs")
local utils = require("pl.utils")
local path = require("pl.path")

local function mktmpdir()
	local dir = os.tmpname()
	os.remove(dir)
	lfs.mkdir(dir)
	return dir
end

describe("db", function()
	local tmpdir
	local posix = require("posix")

	local function mkrepos(dir, repos)
		for name, repo in pairs(repos) do
			lfs.mkdir(path.join(dir, name))
			for _, a in pairs(repo) do
				local d = path.join(dir, name, a.pkgname)
				lfs.mkdir(d)
				utils.writefile(
					path.join(d, "APKBUILD"),
					string.format(
						"pkgname='%s'\n" .. "pkgver='%s'\n" .. "pkgrel='%s'\n",
						a.pkgname,
						a.pkgver or "1.0",
						a.pkgrel or "0"
					)
				)
			end
		end
	end

	setup(function()
		tmpdir = mktmpdir()
		local abuild_conf = tmpdir .. "/abuild.conf"
		utils.writefile(abuild_conf, [[
			CARCH=aarch64
			CLIBC=musl
			MYVAR=myvalue
			CHOST=aarch64-alpine-linux-musl
			]] .. "REPODEST=" .. tmpdir)
		posix.stdlib.setenv("ABUILD_USERCONF", abuild_conf)
		package.path = "?.lua;" .. package.path
	end)

	teardown(function()
		require("pl.dir").rmtree(tmpdir)
		posix.stdlib.setenv("ABUILD_USERCONF", nil)
	end)

	describe("new", function()
		it("should initialize the APK database correctly", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a" },
					{ pkgname = "b" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)
			assert.equal(repo1.apks.a[1].pkgname, "a")
			assert.equal(repo1.apks.b[1].pkgname, "b")
		end)
	end)

	describe("target_packages", function()
		it("should list all target packages", function()
			mkrepos(tmpdir, {
				repo1 = { { pkgname = "a", pkgver = "2.0", pkgrel = "3" } },
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)
			local res = {}
			for p in repo1:target_packages("a") do
				table.insert(res, p)
			end
			assert.same(res, { "a-2.0-r3.apk" })
		end)
	end)
end)
