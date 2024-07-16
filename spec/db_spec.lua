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
						"pkgname='%s'\n"
							.. "pkgver='%s'\n"
							.. "pkgrel='%s'\n"
							.. "depends='%s'\n"
							.. "makedepends='%s'\n"
							.. "checkdepends='%s'\n"
							.. "options='%s'\n"
							.. "subpackages='%s'\n"
							.. "arch='%s'\n",
						a.pkgname,
						a.pkgver or "1.0",
						a.pkgrel or "0",
						a.depends or "",
						a.makedepends or "",
						a.checkdepends or "",
						a.options or "",
						a.subpackages or "",
						a.arch or ""
					)
				)
			end
		end
	end

	setup(function()
		package.path = "?.lua;" .. package.path
	end)

	before_each(function()
		tmpdir = mktmpdir()
	end)

	after_each(function()
		require("pl.dir").rmtree(tmpdir)
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
			assert.same({ "a-2.0-r3.apk" }, res)
		end)
	end)

	describe("recursive_dependencies", function()
		it("should list all dependencies in correct order", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", depends = "b" },
					{ pkgname = "b", makedepends = "c" },
					{ pkgname = "c", checkdepends = "d" },
					{ pkgname = "d", checkdepends = "e", options = "!check" },
					{ pkgname = "e" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)
			local res = {}
			for p in repo1:recursive_dependencies("a") do
				table.insert(res, p)
			end
			assert.same({ "d", "c", "b", "a" }, res)
		end)
	end)

	describe("recursive_reverse_dependencies", function()
		it("should list all reverse dependencies in correct order", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", depends = "b" },
					{ pkgname = "b", makedepends = "c" },
					{ pkgname = "c" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)
			local res = {}
			for p in repo1:recursive_reverse_dependencies("c") do
				table.insert(res, p)
			end
			assert.same({ "a", "b", "c" }, res)
		end)
	end)

	describe("each_name", function()
		it("should list all apk names and its origin", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", subpackages = "a1 a2" },
					{ pkgname = "b" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)
			local res = {}
			for name, pkgs in repo1:each_name() do
				res[name] = pkgs[1].pkgname
			end
			assert.same({ a = "a", a1 = "a", a2 = "a", b = "b" }, res)
		end)
	end)

	describe("each_known_dependency", function()
		it("should list all known dependencies", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", depends = "b c" },
					{ pkgname = "b" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for dep in repo1:each_known_dependency(repo1.apks.a[1]) do
				table.insert(res, dep)
			end
			assert.same({ "b" }, res)
		end)
	end)

	describe("each_aport", function()
		it("should list all apk names and its origin", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", subpackages = "a1 a2" },
					{ pkgname = "b" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for dep in repo1:each_aport() do
				res[dep.pkgname] = true
			end
			assert.same({ a = true, b = true }, res)
		end)
	end)

	describe("each_need_build", function()
		it("should list all aports that don't have built apk file", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", arch = "all", subpackages = "a1 a2" },
					{ pkgname = "b", arch = "noarch" },
					{ pkgname = "c" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for dep in repo1:each_need_build() do
				res[dep.pkgname] = true
			end
			assert.same({ a = true, b = true }, res)
		end)
	end)
end)
