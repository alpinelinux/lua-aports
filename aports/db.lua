local M = {}
local abuild = require("aports.abuild")
local pkg = require("aports.pkg")

local function split_subpkgs(str, linguas, pkgname)
	local t = {}
	if not str then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = string.gsub(e, ":.*", "")
	end
	for _, v in pairs(linguas) do
		t[#t + 1] = ("%s-lang-%s"):format(pkgname, v)
	end
	return t
end

local function split_deps(str)
	local t = {}
	if not str then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = string.gsub(e, "[=<>~].*", "")
	end
	return t
end

local function split(str)
	local t = {}
	if not str then
		return nil
	end
	for e in string.gmatch(str, "%S+") do
		t[#t + 1] = e
	end
	return t
end

local function split_key(str)
	local t = {}
	for _, key in pairs(split(str) or {}) do
		t[key] = true
	end
	return t
end

local function split_apkbuild(line)
	if not line then
		return nil
	end
	-- stylua: ignore
	local dir, pkgname, pkgver, pkgrel, pkgdesc, arch, license, options, depends,
		makedepends, checkdepends, subpackages, linguas, source, url, provides =
		string.match(line, string.rep("([^\\]*)", 16, "\\"))
	linguas = split(linguas)

	return {
		dir = dir,
		pkgname = pkgname,
		pkgver = pkgver,
		pkgrel = pkgrel,
		pkgdesc = pkgdesc,
		license = license,
		depends = split_deps(depends),
		makedepends = split_deps(makedepends),
		checkdepends = split_deps(checkdepends),
		linguas = linguas,
		subpackages = split_subpkgs(subpackages, linguas, pkgname),
		source = split(source),
		url = url,
		arch = split_key(arch),
		options = split_key(options),
		provides = split_deps(provides),
	}
end

-- parse the APKBUILDs and return an iterator
local function apkbuilds_open(aportsdir, repos)
	local str = ""
	if not repos then
		return nil
	end
	--expand repos
	for _, repo in pairs(repos) do
		str = ("%s %s/%s/*/APKBUILD"):format(str, aportsdir, repo)
	end

	local obj = {}
	--luacheck: ignore 631 (line is too long)
	obj.handle = io.popen(". " .. abuild.functions .. ";" .. [[
		for i in ]] .. str .. [[; do
			pkgname=
			pkgver=
			pkgrel=
			pkgdesc=
			arch=
			license=
			options=
			depends=
			depends_doc=
			depends_dev=
			depends_libs=
			depends_openrc=
			depends_static=
			makedepends=
			makedepends_build=
			makedepends_host=
			checkdepends=
			subpackages=
			provides=
			linguas=
			source=
			url=
			dir="${i%/APKBUILD}";
			[ -n "$dir" ] || exit 1;
			cd "$dir";
			. ./APKBUILD;
			echo $dir\\$pkgname\\$pkgver\\$pkgrel\\$pkgdesc\\$arch\\$license\\$options\\$depends\\$makedepends $makedepends_host $makedepends_build\\$checkdepends\\$subpackages\\$linguas\\$source\\$url\\$provides ;
		done;
	]])
	obj.read = function(self)
		return function()
			return split_apkbuild(self.handle:read("*line"))
		end
	end
	obj.close = function(self)
		return self.handle:close()
	end
	return obj
end

local function init_apkdb(aportsdir, repos, repodest)
	local pkgdb = {}
	local revdeps = {}
	local providers = {}
	local dirs = {}
	local apkbuilds = apkbuilds_open(aportsdir, repos)
	for a in apkbuilds:read() do
		--	io.write(a.pkgname.." "..a.pkgver.."\t"..a.dir.."\n")
		if pkgdb[a.pkgname] == nil then
			pkgdb[a.pkgname] = {}
		end
		pkg.init(a, repodest)
		table.insert(pkgdb[a.pkgname], a)
		-- add subpackages to package db
		for _, v in pairs(a.subpackages) do
			if pkgdb[v] == nil then
				pkgdb[v] = {}
			end
			table.insert(pkgdb[v], a)
		end
		-- add provides
		for _, v in pairs(a.provides) do
			if providers[v] == nil then
				providers[v] = {}
			end
			table.insert(providers[v], a)
		end
		-- add to reverse dependencies
		for dep in a:each_dependency() do
			if revdeps[dep] == nil then
				revdeps[dep] = {}
			end
			table.insert(revdeps[dep], a)
		end
		dirs[a.dir] = a
	end
	if not apkbuilds:close() then
		return nil
	end
	return pkgdb, revdeps, providers, dirs
end

local Aports = {}
function Aports:recursive_dependencies(pkgname)
	local visited = {}
	local apkdb = self.apks

	return coroutine.wrap(function()
		local function recurs(pn)
			if not pn or visited[pn] or (not apkdb[pn] and not self.providers[pn]) then
				return nil
			end
			visited[pn] = true
			for _, p in pairs(apkdb[pn] or {}) do
				for dep in p:each_dependency() do
					if recurs(dep) then
						return true
					end
				end
			end
			for _, p in pairs(self.providers[pn] or {}) do
				for dep in p:each_dependency() do
					if recurs(dep) then
						return true
					end
				end
			end
			coroutine.yield(pn)
		end
		return recurs(pkgname)
	end)
end

function Aports:recursive_reverse_dependencies(pkgname)
	local visited = {}
	local apkdb = self.apks

	return coroutine.wrap(function()
		local function recurs(pn)
			if not pn or visited[pn] or not apkdb[pn] then
				return nil
			end
			visited[pn] = true
			for _, dep in self:each_reverse_dependency(pn) do
				for _, subpkg in pairs(dep.subpackages) do
					if recurs(subpkg) then
						return true
					end
				end
				if recurs(dep.pkgname) then
					return true
				end
			end
			coroutine.yield(pn)
		end
		return recurs(pkgname)
	end)
end

function Aports:target_packages(pkgname)
	return coroutine.wrap(function()
		for _, v in pairs(self.apks[pkgname]) do
			coroutine.yield(pkgname .. "-" .. v.pkgver .. "-r" .. v.pkgrel .. ".apk")
		end
	end)
end

function Aports:each_name()
	return coroutine.wrap(function()
		for k, v in pairs(self.apks) do
			coroutine.yield(k, v)
		end
	end)
end

function Aports:each_reverse_dependency(pname)
	return coroutine.wrap(function()
		for k, v in pairs(self.revdeps[pname] or {}) do
			coroutine.yield(k, v)
		end
	end)
end

function Aports:each_known_dependency(p)
	return coroutine.wrap(function()
		for dep in p:each_dependency() do
			if self.apks[dep] or self.providers[dep] then
				coroutine.yield(dep)
			end
		end
	end)
end

function Aports:each_pkg_with_name(name)
	if not self.apks[name] then
		io.stderr:write("WARNING: " .. name .. ": not provided by any known APKBUILD\n")
		return function()
			return nil
		end
	end
	return coroutine.wrap(function()
		for index, p in pairs(self.apks[name]) do
			coroutine.yield(p, index)
		end
	end)
end

function Aports:each_provider_for(name)
	return coroutine.wrap(function()
		for index, p in pairs(self.apks[name] or {}) do
			coroutine.yield(p, index)
		end
		for index, p in pairs(self.providers[name] or {}) do
			coroutine.yield(p, index)
		end
	end)
end

function Aports:each()
	return coroutine.wrap(function()
		for name, pkglist in self:each_name() do
			for _, p in pairs(pkglist) do
				coroutine.yield(p, name)
			end
		end
	end)
end

function Aports:each_aport()
	return coroutine.wrap(function()
		for p, name in self:each() do
			if name == p.pkgname then
				coroutine.yield(p)
			end
		end
	end)
end

function Aports:each_need_build()
	return coroutine.wrap(function()
		for aport in self:each_aport() do
			if aport:relevant() and not aport:all_apks_exists() then
				coroutine.yield(aport)
			end
		end
	end)
end

function Aports:each_in_build_order(namelist)
	local pkgs = {}
	for _, name in pairs(namelist) do
		for p in self:each_pkg_with_name(name) do
			pkgs[p.dir] = true
		end
	end

	return coroutine.wrap(function()
		for _, name in pairs(namelist) do
			for dep in self:recursive_dependencies(name) do
				for p in self:each_provider_for(dep) do
					if pkgs[p.dir] then
						coroutine.yield(p)
						pkgs[p.dir] = nil
					end
				end
			end
		end
	end)
end

-- Iterate unique outgoing aports (APKBUILD dirs) for a given aport dir.
-- Edges represent build-time dependencies crossing APKBUILD boundaries.
function Aports:each_outgoing_aport(dir)
	local p = self.dirs[dir]
	return coroutine.wrap(function()
		local seen = {}
		for depname in self:each_known_dependency(p) do
			for prov in self:each_provider_for(depname) do
				-- Ignore deps that resolve to the same aport
				if prov.dir ~= p.dir and not seen[prov.dir] then
					seen[prov.dir] = true
					coroutine.yield(prov.dir)
				end
			end
		end
	end)
end

-- Iterate unique aports (APKBUILD origins) as graph nodes.
function Aports:each_graph_aport_node()
	return coroutine.wrap(function()
		local seen = {}
		for p in self:each_aport() do
			if p.dir and not seen[p.dir] then
				seen[p.dir] = true
				coroutine.yield(p.dir)
			end
		end
	end)
end

-- Compute SCCs (Tarjan) and return only those that form cycles.
-- If roots is provided (array of pkgnames), restrict to the reachable subgraph from those roots.
function Aports:circular_dependency_groups(roots)
	-- Build node set (dirs)
	local nodes = {}

	if roots and #roots > 0 then
		-- Resolve root pkgnames -> dirs, then do reachability closure on dir-graph
		local stack = {}

		for i = 1, #roots do
			local name = roots[i]
			-- A name can be a pkgname or subpackage name; both live in self.apks[name]
			for p in self:each_pkg_with_name(name) do
				if p.dir and not nodes[p.dir] then
					nodes[p.dir] = true
					stack[#stack + 1] = p.dir
				end
			end
		end

		while #stack > 0 do
			local v = stack[#stack]
			stack[#stack] = nil
			for depdir in self:each_outgoing_aport(v) do
				if not nodes[depdir] then
					nodes[depdir] = true
					stack[#stack + 1] = depdir
				end
			end
		end
	else
		for dir in self:each_graph_aport_node() do
			nodes[dir] = true
		end
	end

	-- Tarjan SCC
	local index = 0
	local idx = {}
	local low = {}
	local onstack = {}
	local stack = {}

	local function push(v)
		stack[#stack + 1] = v
		onstack[v] = true
	end
	local function pop()
		local v = stack[#stack]
		stack[#stack] = nil
		onstack[v] = nil
		return v
	end

	local sccs = {}

	local function strongconnect(v)
		index = index + 1
		idx[v] = index
		low[v] = index
		push(v)

		for dep in self:each_outgoing_aport(v) do
			if nodes[dep] then
				if not idx[dep] then
					strongconnect(dep)
					if low[dep] < low[v] then
						low[v] = low[dep]
					end
				elseif onstack[dep] then
					if idx[dep] < low[v] then
						low[v] = idx[dep]
					end
				end
			end
		end

		if low[v] == idx[v] then
			local comp = {}
			while true do
				local w = pop()
				comp[#comp + 1] = w
				if w == v then
					break
				end
			end
			sccs[#sccs + 1] = comp
		end
	end

	for v in pairs(nodes) do
		if not idx[v] then
			strongconnect(v)
		end
	end

	-- Filter SCCs to actual cycles
	local cycles = {}
	for _, comp in ipairs(sccs) do
		if #comp > 1 then
			cycles[#cycles + 1] = comp
		end
	end
	return cycles
end

function Aports:circular_dependency_groups_sorted(roots)
	local cycles = self:circular_dependency_groups(roots)

	for i = 1, #cycles do
		table.sort(cycles[i])
	end
	table.sort(cycles, function(a, b)
		return table.concat(a, " ") < table.concat(b, " ")
	end)

	return cycles
end

function Aports:git_describe()
	local cmd = ("git --git-dir %s/.git describe"):format(self.aportsdir)
	local f = io.popen(cmd)
	if not f then
		return nil
	end
	local result = f:read("*line")
	f:read("*a")
	f:close()
	return result
end

function Aports:known_deps_exists(p)
	for name in self:each_known_dependency(p) do
		for dep in self:each_pkg_with_name(name) do
			if dep.pkgname ~= p.pkgname and dep:relevant() and not dep:all_apks_exists() then
				return nil
			end
		end
	end
	return true
end

function M.new(aportsdir, repos, repodest)
	local h = setmetatable({}, { __index = Aports })
	h.aportsdir = aportsdir
	if type(repos) == "table" then
		h.repos = repos
	else
		h.repos = { repos }
	end
	h.apks, h.revdeps, h.providers, h.dirs = init_apkdb(aportsdir, h.repos, repodest)
	if h.apks == nil then
		return nil, h.revdeps
	end
	return h
end

return M
