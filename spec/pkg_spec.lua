posix = require("posix")

describe("aports.pkg", function()
	local pkg, abuild
	local tmpdir, abuild_conf, repodir

	setup(function()
		tmpdir = os.tmpname()
		abuild_conf = tmpdir .. "/abuild.conf"
		repodest = tmpdir .. "/pkgs"
		os.remove(tmpdir)
		lfs.mkdir(tmpdir)
		lfs.mkdir(repodest)
		local f = io.open(abuild_conf, "w")
		f:write(
			"CARCH=aarch64\n"
				.. "CLIBC=musl\n"
				.. "MYVAR=myvalue\n"
				.. "REPODEST="
				.. repodest
				.. "\n"
				.. "CHOST=aarch64-alpine-linux-musl\n"
		)
		f:close()
		posix.stdlib.setenv("ABUILD_USERCONF", abuild_conf)
		pkg = require("aports.pkg")
		abuild = require("aports.abuild")
	end)

	teardown(function()
		os.execute("rm -r " .. tmpdir)
		posix.stdlib.setenv("ABUILD_USERCONF", nil)
	end)

	describe("is_remote", function()
		it("should return true for remote URLs", function()
			assert.is_true(pkg.is_remote("http://example.com"))
			assert.is_true(pkg.is_remote("https://example.com/file.tar.gz"))
			assert.is_true(pkg.is_remote("ftp://example.com"))
			assert.is_true(pkg.is_remote("git::https://example.com"))
		end)
	end)

	it("should return false for non-remote URLs", function()
		assert.is_false(pkg.is_remote("local/file/path"))
		assert.is_false(pkg.is_remote("/absolute/file/path"))
		assert.is_false(pkg.is_remote("file.patch"))
	end)

	describe("remote_sources", function()
		it("should iterate over remote sources", function()
			local p = {
				source = {
					"local/file",
					"http://example.com",
					"ftp://example.com",
					"local/file2",
					"https://example.com",
				},
			}

			local sources = {}
			for url in pkg.remote_sources(p) do
				table.insert(sources, url)
			end

			assert.same({ "http://example.com", "ftp://example.com", "https://example.com" }, sources)
		end)

		it("should return nil if source is not a table", function()
			local p = {
				source = "local/file",
			}

			local sources = pkg.remote_sources(p)

			assert.is_nil(sources)
		end)
	end)

	describe("get_maintainer", function()
		it("should return the maintainer", function()
			local apkbuild = tmpdir .. "/APKBUILD"
			local f = io.open(apkbuild, "w")
			f:write("# Maintainer: Joe User\n")
			f:close()

			assert.is_equal("Joe User", pkg.get_maintainer({ dir = tmpdir }))
		end)
	end)

	describe("get_repo_name", function()
		it("should return the repository name when it exists", function()
			assert.equal("repository", pkg.get_repo_name({ dir = "/path/to/repository/package" }))
		end)

		it("should return nil when package directory is not provided", function()
			assert.is_nil(pkg.get_repo_name({}))
		end)
	end)

	describe("get_apk_file_name", function()
		it("should return the correct apk file name", function()
			assert.equal(
				"myapp-1.0-r0.apk",
				pkg.get_apk_file_name({
					pkgname = "myapp",
					pkgver = "1.0",
					pkgrel = "0",
				})
			)
		end)
	end)

	describe("get_apk_file_path", function()
		it("should return the correct apk file path", function()
			assert.equal(
				repodest .. "/myrepo/aarch64/myapp-doc-1.0-r0.apk",
				pkg.get_apk_file_path({
					pkgname = "myapp",
					pkgver = "1.0",
					pkgrel = "0",
					dir = tmpdir .. "/aports/myrepo/myapp",
				}, "myapp-doc")
			)
		end)
	end)

	describe("apk_file_exists", function()
		it("should return false when the apk file does not exist", function()
			assert.is_false(pkg.apk_file_exists({
				pkgname = "myapp",
				pkgver = "1.0",
				pkgrel = "0",
				dir = tmpdir .. "/aports/myrepo/myapp",
			}, "myapp-doc"))
		end)

		it("should return true when the apk file exists", function()
			lfs.mkdir(repodest .. "/myrepo")
			lfs.mkdir(repodest .. "/myrepo/aarch64")
			local apkfile = repodest .. "/myrepo/aarch64/myapp-doc-1.0-r0.apk"
			local f = io.open(apkfile, "w")
			f:close()

			assert.is_true(pkg.apk_file_exists({
				pkgname = "myapp",
				pkgver = "1.0",
				pkgrel = "0",
				dir = tmpdir .. "/aports/myrepo/myapp",
			}, "myapp-doc"))
		end)
	end)

	describe("all_apks_exists", function()
		local myapp = {
			pkgname = "myapp",
			pkgver = "1.0",
			pkgrel = "0",
			dir = tmpdir .. "/aports/myrepo/myapp",
			subpackages = { "myapp-doc", "myapp-dev" },
		}

		it("should return false when any apk file does not exist", function()
			pkg.apk_file_exists = function(self, name)
				if name == "myapp-doc" then
					return true
				else
					return false
				end
			end
			pkg.init(myapp, repodest)
			assert.is_false(myapp:all_apks_exists())
		end)

		it("should return true when all apk files exist", function()
			pkg.apk_file_exists = function(self, name)
				return true
			end
			pkg.init(myapp, repodest)
			assert.is_true(myapp:all_apks_exists())
		end)
	end)

	describe("arch_enabled", function()
		it("should return true when arch is enabled for the package", function()
			assert.is_true(pkg.arch_enabled({ arch = { [abuild.arch] = true } }))
		end)

		it("should return true when all arches are enabled for the package", function()
			assert.is_true(pkg.arch_enabled({ arch = { all = true } }))
		end)

		it("should return true for noarch packages", function()
			assert.is_true(pkg.arch_enabled({ arch = { noarch = true } }))
		end)

		it("should return falsy when arch is empty for the package", function()
			assert.is_falsy(pkg.arch_enabled({ arch = {} }))
		end)

		it("should return false when arch is disabled for the package", function()
			assert.is_false(pkg.arch_enabled({ arch = { all = true, ["!" .. abuild.arch] = true } }))
		end)

		it("should return false when arch is disabled for a noarch package", function()
			assert.is_false(pkg.arch_enabled({ arch = { noarch = true, ["!" .. abuild.arch] = true } }))
		end)
	end)

	describe("each_dependency", function()
		it("should yield dependencies from 'depends' field", function()
			local p = {
				depends = {
					"dependency1",
					"dependency2",
				},
				makedepends = {},
				checkdepends = {},
				options = {},
			}

			pkg.init(p)
			local dependencies = {}
			for dep in p:each_dependency() do
				table.insert(dependencies, dep)
			end

			assert.same({ "dependency1", "dependency2" }, dependencies)
		end)

		it("should yield dependencies from 'makedepends' field", function()
			local p = {
				depends = {},
				makedepends = {
					"dependency1",
					"dependency2",
				},
				checkdepends = {},
				options = {},
			}

			pkg.init(p)
			local dependencies = {}
			for dep in p:each_dependency() do
				table.insert(dependencies, dep)
			end

			assert.same({ "dependency1", "dependency2" }, dependencies)
		end)

		it("should yield dependencies from 'checkdepends' field when options['!check'] is falsy", function()
			local p = {
				depends = {},
				makedepends = {},
				checkdepends = {
					"dependency1",
					"dependency2",
				},
				options = {}
			}

			pkg.init(p)
			local dependencies = {}
			for dep in p:each_dependency() do
				table.insert(dependencies, dep)
			end

			assert.same({ "dependency1", "dependency2" }, dependencies)
		end)

		it("should not yield dependencies from 'checkdepends' field when options['!check'] is truthy", function()
			local p = {
				depends = {},
				makedepends = {},
				checkdepends = {
					"dependency1",
					"dependency2",
				},
				options = {
					["!check"] = true,
				},
			}

			pkg.init(p)
			local dependencies = {}
			for dep in p:each_dependency() do
				table.insert(dependencies, dep)
			end

			assert.same({}, dependencies)
		end)
	end)
end)
