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
							.. "arch='%s'\n"
							.. "provides='%s'\n",
						a.pkgname,
						a.pkgver or "1.0",
						a.pkgrel or "0",
						a.depends or "",
						a.makedepends or "",
						a.checkdepends or "",
						a.options or "",
						a.subpackages or "",
						a.arch or "",
						a.provides or ""
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
					{ pkgname = "not-this", provides = "a" },
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
		it("should list a provides as a known dependencies", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", depends = "b c" },
					{ pkgname = "d", provides = "b" },
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

	describe("each_pkg_with_name", function()
		it("should only list the origin(s) for the given package names", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", subpackages = "a1 a2" },
					{ pkgname = "b" },
					{ pkgname = "c", provides = "a1" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for p in repo1:each_pkg_with_name("a1") do
				res[p.pkgname] = true
			end
			assert.same({ a = true }, res)
		end)
	end)

	describe("each_provider_for", function()
		it("should list the providing origins for the given package names", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", subpackages = "a1 a2" },
					{ pkgname = "b" },
					{ pkgname = "c", provides = "a1 b" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for p in repo1:each_provider_for("a1") do
				res[p.pkgname] = true
			end
			assert.same({ a = true, c = true }, res)
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

	describe("each_in_build_order", function()
		before_each(function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", depends = "b", subpackages = "a1 a2" },
					{ pkgname = "b", depends = "d" },
					{ pkgname = "c", provides = "d>0" },
					{ pkgname = "d" },
					{ pkgname = "docs", depends = "doc-provider man-pages" },
					{ pkgname = "man-pages" },
					{ pkgname = "mandoc", provides = "doc-provider mdocml=1.0-r0" },
				},
			})
		end)
		it("should list the specified aports in build order", function()
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for a in repo1:each_in_build_order({ "a1", "c" }) do
				table.insert(res, a.pkgname)
			end
			assert.same({ "c", "a" }, res)
		end)
		it("should not include other provides when deternmining build order", function()
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for a in repo1:each_in_build_order({ "a1", "d" }) do
				table.insert(res, a.pkgname)
			end
			assert.same({ "d", "a" }, res)
		end)
		it("should build docs last", function()
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			for a in repo1:each_in_build_order({ "docs", "man-pages", "mandoc" }) do
				table.insert(res, a.pkgname)
			end
			assert.same("docs", res[3])
		end)
	end)

	describe("known_deps_exists", function()
		it("should return true", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", arch = "all", depends = "b" },
					{ pkgname = "b", arch = "all", depends = "c" },
					{ pkgname = "c" },
				},
			})
			local repo1 = require("aports.db").new(tmpdir, "repo1")
			local res = {}
			assert.is_not_true(repo1:known_deps_exists(repo1.apks.a[1]))
			assert.is_true(repo1:known_deps_exists(repo1.apks.b[1]))
			repo1.apks.b[1].apk_file_exists = function(self)
				return true
			end
			assert.is_true(repo1:known_deps_exists(repo1.apks.a[1]))
		end)
	end)

	describe("each_outgoing_aport", function()
		it("should yield unique outgoing aport dirs, skipping same-dir deps and including provides", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- Origin aport "a" (dir .../a). It depends on:
					-- - b (real pkg)
					-- - virt (only provided)
					-- - a1 (subpkg in same dir -> should be ignored)
					{ pkgname = "a", depends = "b virt a1", subpackages = "a1" },

					-- Real provider for b in its own dir
					{ pkgname = "b" },

					-- Provider for virt in its own dir
					{ pkgname = "pvirt", provides = "virt" },

					-- Noise: another provider for virt in different dir (should not duplicate)
					{ pkgname = "pvirt2", provides = "virt" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			-- Get the aport object for "a" (origin package)
			local a_aport = repo1.apks.a[1]
			assert.equal("a", a_aport.pkgname)

			local dirs = {}
			for d in repo1:each_outgoing_aport(a_aport.dir) do
				table.insert(dirs, d)
			end

			-- The dirs are filesystem paths; compare as a set to avoid ordering assumptions
			local got = {}
			for _, d in ipairs(dirs) do
				got[d] = true
			end

			-- Expected: outgoing dirs include b's dir and the virt providers' dirs,
			-- but NOT a's own dir (via subpackage a1).
			local b_dir = repo1.apks.b[1].dir
			local v1_dir = repo1.apks.pvirt[1].dir
			local v2_dir = repo1.apks.pvirt2[1].dir

			assert.is_true(got[b_dir])
			-- Should include at least one virt provider dir; both are acceptable,
			-- but since we dedup by prov.dir, and providers are in different dirs,
			-- both will appear (distinct outgoing aports).
			assert.is_true(got[v1_dir])
			assert.is_true(got[v2_dir])

			-- Ensure we did not include a's own dir (same-dir dep via a1)
			assert.is_nil(got[a_aport.dir])
		end)

		it("should deduplicate outgoing dirs when multiple deps resolve to the same dir", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- a depends on b and c, but b and c are produced from same APKBUILD dir (subpackage)
					{ pkgname = "x", depends = "b c" },
					{ pkgname = "b", subpackages = "c" }, -- c is subpackage of b (same dir as b)
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local x_aport = repo1.apks.x[1]
			local dirs = {}
			for d in repo1:each_outgoing_aport(x_aport.dir) do
				table.insert(dirs, d)
			end

			-- Both b and c resolve to the same dir (b's dir), so we should get it once
			assert.equal(1, #dirs)
			assert.equal(repo1.apks.b[1].dir, dirs[1])
		end)
	end)

	describe("each_graph_aport_node", function()
		it("should yield unique APKBUILD dirs, deduplicating subpackages", function()
			mkrepos(tmpdir, {
				repo1 = {
					{ pkgname = "a", subpackages = "a1 a2" },
					{ pkgname = "b" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local dirs = {}
			for d in repo1:each_graph_aport_node() do
				table.insert(dirs, d)
			end

			-- Convert to set for order independence
			local got = {}
			for _, d in ipairs(dirs) do
				got[d] = true
			end

			-- Expect exactly two unique dirs: one for a (and its subpkgs), one for b
			local a_dir = repo1.apks.a[1].dir
			local b_dir = repo1.apks.b[1].dir

			assert.is_true(got[a_dir])
			assert.is_true(got[b_dir])
			assert.equal(2, #dirs)
		end)

		it("should not yield duplicate dirs even if multiple keys map to same origin", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- "b" produces subpackage "c", so apks["c"] exists but shares b.dir
					{ pkgname = "b", subpackages = "c" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local dirs = {}
			for d in repo1:each_graph_aport_node() do
				table.insert(dirs, d)
			end

			assert.equal(1, #dirs)
			assert.equal(repo1.apks.b[1].dir, dirs[1])
		end)
	end)

	describe("circular_dependency_groups (aport-level dirs)", function()
		local function to_set(list)
			local s = {}
			for i = 1, #list do
				s[list[i]] = true
			end
			return s
		end

		local function normalize_cycles(cycles)
			-- Make comparison stable: sort each component, then sort list by concat
			for i = 1, #cycles do
				table.sort(cycles[i])
			end
			table.sort(cycles, function(a, b)
				return table.concat(a, " ") < table.concat(b, " ")
			end)
			return cycles
		end

		it("should find cycles as SCCs over aport dirs", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- Cycle 1: a -> b -> a (different dirs)
					{ pkgname = "a", depends = "b" },
					{ pkgname = "b", depends = "a" },

					-- Cycle 2: c -> d -> e -> c
					{ pkgname = "c", depends = "d" },
					{ pkgname = "d", depends = "e" },
					{ pkgname = "e", depends = "c" },

					-- Noise (acyclic)
					{ pkgname = "x", depends = "a" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local cycles = normalize_cycles(repo1:circular_dependency_groups())

			-- Expected cycles are lists of dirs
			local a_dir = repo1.apks.a[1].dir
			local b_dir = repo1.apks.b[1].dir
			local c_dir = repo1.apks.c[1].dir
			local d_dir = repo1.apks.d[1].dir
			local e_dir = repo1.apks.e[1].dir

			local expected = normalize_cycles({
				{ a_dir, b_dir },
				{ c_dir, d_dir, e_dir },
			})

			assert.same(expected, cycles)
		end)

		it("should restrict to cycles reachable from roots (pkgnames)", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- Cycle 1: a <-> b
					{ pkgname = "a", depends = "b" },
					{ pkgname = "b", depends = "a" },

					-- Cycle 2: c <-> d
					{ pkgname = "c", depends = "d" },
					{ pkgname = "d", depends = "c" },

					-- Acyclic root that reaches only cycle 1
					{ pkgname = "root", depends = "a" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local a_dir = repo1.apks.a[1].dir
			local b_dir = repo1.apks.b[1].dir

			local cycles = normalize_cycles(repo1:circular_dependency_groups({ "root" }))

			local expected = normalize_cycles({
				{ a_dir, b_dir },
			})

			assert.same(expected, cycles)
		end)
	end)

	describe("circular_dependency_groups_sorted (aport-level dirs)", function()
		local function normalize_cycles(cycles)
			for i = 1, #cycles do
				table.sort(cycles[i])
			end
			table.sort(cycles, function(a, b)
				return table.concat(a, " ") < table.concat(b, " ")
			end)
			return cycles
		end

		it("should return the same cycles as circular_dependency_groups, but sorted", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- Cycle 1: b <-> a (intentionally declared reversed)
					{ pkgname = "b", depends = "a" },
					{ pkgname = "a", depends = "b" },

					-- Cycle 2: e -> d -> c -> e (declared out of order)
					{ pkgname = "e", depends = "d" },
					{ pkgname = "d", depends = "c" },
					{ pkgname = "c", depends = "e" },

					-- Noise
					{ pkgname = "x", depends = "a" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local unsorted = repo1:circular_dependency_groups()
			local sorted = repo1:circular_dependency_groups_sorted()

			-- The sorted version should equal a normalized view of the unsorted result
			assert.same(normalize_cycles(unsorted), sorted)

			-- And match explicit expected ordering/content
			local a_dir = repo1.apks.a[1].dir
			local b_dir = repo1.apks.b[1].dir
			local c_dir = repo1.apks.c[1].dir
			local d_dir = repo1.apks.d[1].dir
			local e_dir = repo1.apks.e[1].dir

			local expected = normalize_cycles({
				{ a_dir, b_dir },
				{ c_dir, d_dir, e_dir },
			})
			assert.same(expected, sorted)
		end)

		it("should return sorted cycles restricted to reachable subgraph from roots (pkgnames)", function()
			mkrepos(tmpdir, {
				repo1 = {
					-- Cycle 1: a <-> b
					{ pkgname = "a", depends = "b" },
					{ pkgname = "b", depends = "a" },

					-- Cycle 2: c <-> d (unreachable from root)
					{ pkgname = "c", depends = "d" },
					{ pkgname = "d", depends = "c" },

					-- Root reaches only cycle 1
					{ pkgname = "root", depends = "a" },
				},
			})

			local repo1 = require("aports.db").new(tmpdir, "repo1")
			assert.not_nil(repo1)

			local root_dir = repo1.apks.root[1].dir
			local a_dir = repo1.apks.a[1].dir
			local b_dir = repo1.apks.b[1].dir

			local sorted = repo1:circular_dependency_groups_sorted({ "root" })

			local expected = normalize_cycles({
				{ a_dir, b_dir },
			})
			assert.same(expected, sorted)
		end)
	end)
end)
