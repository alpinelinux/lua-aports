#!/usr/bin/lua5.2

local abuild = require("aports.abuild")
local apkrepo = require("aports.apkrepo")
local lfs = require("lfs")
local optarg = require("optarg")

local pluginsdir = "/etc/buildrepo/plugins.d"

local function warn(formatstr, ...)
	io.stderr:write(("WARNING: %s\n"):format(formatstr:format(...)))
	io.stderr:flush()
end

local function err(formatstr, ...)
	io.stderr:write(("ERROR: %s\n"):format(formatstr:format(...)))
	io.stderr:flush()
end

local function fatal(exitcode, formatstr, ...)
	err(formatstr, ...)
	os.exit(exitcode)
end

local function info(formatstr, ...)
	io.stdout:write(("%s\n"):format(formatstr:format(...)))
	io.stdout:flush()
end

local function skip_aport(aport)
	local dirattr = lfs.attributes(aport.dir.."/src/")
	local fileattr = lfs.attributes(aport.dir.."/APKBUILD")
	if not dirattr or not fileattr then
		return false
	end
	if os.difftime(fileattr.modification, dirattr.modification) > 0 then
		return false
	end
	warn("%s: Skipped due to previous build failure", aport.pkgname)
	return true
end

local function run_plugins(dirpath, func, ...)
	local a = lfs.attributes(dirpath)
	if a == nil or a.mode ~= "directory" then
		return
	end
	local flist = {}
	for f in lfs.dir(dirpath) do
		if string.match(f, ".lua$") then
			table.insert(flist, f)
		end
	end
	table.sort(flist)
	for i = 1,#flist do
		local m = dofile(dirpath.."/"..flist[i])
		if type(m[func]) == "function" then
			m[func](...)
		end
	end
end

local function plugins_prebuild(...)
	return run_plugins(pluginsdir, "prebuild", ...)
end

local function plugins_postbuild(...)
	return run_plugins(pluginsdir, "postbuild", ...)
end

local function logfile_path(logdirbase, repo, aport)
	if logdirbase == nil then
		return nil
	end
	local dir = ("%s/%s/%s"):format(logdirbase, repo, aport.pkgname)
	if not lfs.attributes(dir) then
		local path = ""
		for n in string.gmatch(dir, "[^/]+") do
			path = path.."/"..n
			lfs.mkdir(path)
		end
	end
	return ("%s/%s-%s-r%s.log"):format(dir, aport.pkgname, aport.pkgver, aport.pkgrel)
end


local function build_aport(aport, repodest, logfile)
	local success, errmsg = lfs.chdir(aport.dir)
	if not success then
		err("%s", errmsg)
		return nil
	end
	local logredirect = ""
	if logfile ~= nil then
		logredirect = ("> '%s' 2>&1"):format(logfile)
	end
	local cmd = ("REPODEST='%s' abuild -r -m %s"):format(repodest, logredirect)
	success = os.execute(cmd)
	if not success then
		err("%s: Failed to build", aport.pkgname)
	end
	return success
end

local function log_progress(progress, repo, aport)
	info("%d/%d %d/%d %s/%s %s-r%s",
		progress.tried, progress.total,
		progress.repo_built, progress.repo_total,
		repo, aport.pkgname, aport.pkgver, aport.pkgrel)
end
-----------------------------------------------------------------
local opthelp = [[
 -a, --aports=DIR      Set the aports base dir to DIR instead of $HOME/aports
 -d, --destdir=DIR     Set destination repository base to DIR instead of
                       $HOME/packages
 -h, --help            Show this help and exit
 -l, --logdir=DIR      Create build logs in DIR/REPO/pkgname/ instead of stdout
 -k, --keep-going      Keep going, even if packages fails
 -n, --dry-run         Dry run. Don't acutally build or delete, just print
 -p, --purge           Purge obsolete packages from REPODIR after build
 -r, --deps-repo=REPO  Dependencies are found in REPO
 -s, --skip-failed     Skip those who previously failed (src dir exists)
]]

local function usage(exitcode)
	io.stdout:write((
"Usage: %s [-hknps] [-a DIR] [-d DIR] [-l DIR] [-r REPO] REPO...\n"..
"Options:\n%s\n"):format(_G.arg[0], opthelp))
	os.exit(exitcode)
end

opts, args = optarg.from_opthelp(opthelp)
if opts == nil or #args == 0 then
	usage(1)
end

if opts.h then
	usage(0)
end

homedir = os.getenv("HOME")
aportsdir = opts.a or ("%s/aports"):format(homedir)
repodest = opts.d or abuild.repodest or ("%s/packages"):format(homedir)
logdirbase = opts.l

if opts.n then
	build_aport = function() return true end
end

stats = {}
for _,repo in pairs(args) do
	local db = require('aports.db').new(aportsdir, repo)
	local pkgs = {}
	local unsorted = {}
	local logdir = nil
	stats[repo] = {}
	local start_time = os.clock()

	if db == nil then
		err("%s/%s: Failed to open apkbuilds", aportsdir, repo)
		os.exit(1)
	end

	-- count total aports
	relevant_aports = 0
	total_aports = 0
	for aport in db:each_aport() do
		total_aports = total_aports + 1
		if aport:relevant() then
			relevant_aports = relevant_aports + 1
		end
	end
	stats[repo].relevant_aports = relevant_aports
	stats[repo].total_aports = total_aports

	-- find out what needs to be built
	for aport in db:each_need_build() do
		table.insert(pkgs, aport.pkgname)
		if unsorted[aport.pkgname] then
			warn("more than one aport provides %s", aport.pkgname)
		end
		unsorted[aport.pkgname] = true
	end

	-- build packages
	local built = 0
	local tried = 0
	for aport in db:each_in_build_order(pkgs) do
		local logfile = logfile_path(logdirbase, repo, aport)
		tried = tried + 1
		local progress = { tried = tried, total = #pkgs,
			repo_built = stats[repo].relevant_aports - #pkgs + built,
			repo_total = stats[repo].relevant_aports,
		}
		if not db:known_deps_exists(aport) then
			warn("%s: Skipped due to missing dependencies", aport.pkgname)
		elseif not (opts.s and skip_aport(aport)) then
			log_progress(progress, repo, aport)
			plugins_prebuild(aport, progress, repodest, abuild.arch, logfile)
			local success = build_aport(aport, repodest, logfile)
			plugins_postbuild(aport, success, repodest, abuild.arch, logfile)
			if success then
				built = built + 1
			end
			if not success and not opts.k then
				os.exit(1)
			end
		end
	end

	-- purge old packages
	local deleted = 0
	if opts.p then
		local keep = {}
		for aport,name in db:each() do
			keep[aport:get_apk_file_name(name)] = true
		end
		local apkrepodir = ("%s/%s/%s"):format(repodest, repo, abuild.arch)
		for file in lfs.dir(apkrepodir) do
			if file:match("%.apk$") and not keep[file] then
				info("Deleting %s", file)
				if not opts.n then
					os.remove(("%s/%s"):format(apkrepodir, file))
					deleted = deleted + 1
				end
			end
		end
	end

	-- generate new apkindex
	if not opts.n and built > 0 then
		info("Updating apk index")
		apkrepo.update_index(("%s/%s"):format(repodest, repo),
				abuild.arch, db:git_describe())
	end
	stats[repo].built = built
	stats[repo].tried = tried
	stats[repo].deleted = deleted
	stats[repo].time = os.clock() - start_time
end

for repo,stat in pairs(stats) do
	info("%s built:\t%d", repo, stat.built)
	info("%s tried:\t%d", repo, stat.tried)
	info("%s deleted:\t%d", repo, stat.deleted)
	info("%s total built:\t%d", repo, stat.relevant_aports - stat.tried + stat.built)
	info("%s total relevant aports:\t%d", repo, stat.relevant_aports)
	info("%s total aports:\t%d", repo, stat.total_aports)
end
