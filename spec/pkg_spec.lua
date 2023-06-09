describe("aports.pkg", function()
	pkg = require("aports.pkg")

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
				}
			}

			local sources = {}
			for url in pkg.remote_sources(p) do
				table.insert(sources, url)
			end

			assert.same({"http://example.com", "ftp://example.com", "https://example.com"}, sources)
		end)

		it("should return nil if source is not a table", function()
			local p = {
				source = "local/file"
			}

			local sources = pkg.remote_sources(p)

			assert.is_nil(sources)
		end)
	end)

	describe("get_repo_name", function()
		it("should return the repository name when it exists", function()
			assert.equal("repository", pkg.get_repo_name({ dir = "/path/to/repository/package"}))
		end)

		it("should return nil when package directory is not provided", function()
			assert.is_nil(pkg.get_repo_name({}))
		end)
	end)

	describe("get_apk_file_name", function()
		it("should return the correct apk file name", function()
			assert.equal("myapp-1.0-r0.apk", pkg.get_apk_file_name({
				pkgname="myapp",
				pkgver="1.0",
				pkgrel="0",
			}))
		end)
	end)

end)
