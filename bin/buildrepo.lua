#!/usr/bin/lua5.2

local abuild = require("aports.abuild")
local apkrepo = require("aports.apkrepo")
local lfs = require("lfs")
local optarg = require("optarg")

local conf = {}

local function warn(formatstr, ...)
	io.stderr:write(("WARNING: %s\n"):format(formatstr:format(...)))
	io.stderr:flush()
end

local function err(formatstr, ...)
	io.stderr:write(("ERROR: %s\n"):format(formatstr:format(...)))
	io.stderr:flush()
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
	if not a or a.mode ~= "directory" then
		return
	end
	local flist = {}
	for f in lfs.dir(dirpath) do
		if string.match(f, ".lua$") then
			table.insert(flist, f)
		end
	end
	table.sort(flist)
	for i = 1, #flist do
		local m = dofile(dirpath.."/"..flist[i])
		if type(m[func]) == "function" then
			m[func](...)
		end
	end
end

local function plugins_prebuild(...)
	return run_plugins(conf.pluginsdir, "prebuild", ...)
end

local function plugins_postbuild(...)
	return run_plugins(conf.pluginsdir, "postbuild", ...)
end

local function plugins_prerepo(...)
	return run_plugins(conf.pluginsdir, "prerepo", ...)
end

local function plugins_postrepo(...)
	return run_plugins(conf.pluginsdir, "postrepo", ...)
end

local function logfile_path(logdirbase, repo, aport)
	if not logdirbase then
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


local function build_aport(aport, aportsdir, repodest, logfile, do_rootbld)
	local success, errmsg = lfs.chdir(aport.dir)
	if not success then
		err("%s", errmsg)
		return nil
	end
	local logredirect = ""
	if logfile ~= nil then
		logredirect = ("> '%s' 2>&1"):format(logfile)
	end
	local cmd = ("APORTSDIR='%s' REPODEST='%s' abuild -r -m %s"):
		format(aportsdir, repodest, logredirect)
	if do_rootbld ~= nil then
		cmd = ("APORTSDIR='%s' REPODEST='%s' abuild -m %s rootbld"):
			format(aportsdir, repodest, logredirect)
	end
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
 -c, --config=FILE     Use FILE as config instead of /etc/buildrepo/config.lua
 -d, --destdir=DIR     Set destination repository base to DIR instead of
                       $HOME/packages
 -h, --help            Show this help and exit
 -l, --logdir=DIR      Create build logs in DIR/REPO/pkgname/ instead of stdout
 -k, --keep-going      Keep going, even if packages fails
 -n, --dry-run         Dry run. Don't acutally build or delete, just print
 -p, --purge           Purge obsolete packages from REPODIR after build
 -r, --deps-repo=REPO  Dependencies are found in REPO
 -s, --skip-failed     Skip those who previously failed (src dir exists)
 -R, --rootbld         Build packages in clean chroots
]]

local function usage(exitcode)
	io.stdout:write((
		"Usage: %s [-hknps] [-a DIR] [-d DIR] [-l DIR] [-r REPO] REPO...\n"..
		"Options:\n%s\n"):format(_G.arg[0], opthelp))
	os.exit(exitcode)
end

local opts, args = optarg.from_opthelp(opthelp)
if not opts  or #args == 0 then
	usage(1)
end

if opts.h then
	usage(0)
end

local configfile = opts.c or "/etc/buildrepo/config.lua"
local f = loadfile(configfile, "t", conf)
if f then
	f()
end

conf.pluginsdir = conf.pluginsdir or "/usr/share/buildrepo/plugins"
conf.opts = opts
conf.arch = abuild.arch

local homedir = os.getenv("HOME")
conf.aportsdir = opts.a or conf.aportsdir or ("%s/aports"):format(homedir)
conf.repodest = opts.d or conf.repodest or abuild.repodest or ("%s/packages"):format(homedir)
conf.logdir = opts.l or conf.logdir

if opts.n then
	build_aport = function() return true end
end

local stats = {}
for _, repo in pairs(args) do
	local db = require('aports.db').new(conf.aportsdir, repo, conf.repodest)
	local pkgs = {}
	local unsorted = {}
	stats[repo] = {}
	local start_time = os.clock()

	if not db then
		err("%s/%s: Failed to open apkbuilds", conf.aportsdir, repo)
		os.exit(1)
	end

	-- count total aports
	local relevant_aports = 0
	local total_aports = 0
	for aport in db:each_aport() do
		total_aports = total_aports + 1
		if aport:relevant() then
			relevant_aports = relevant_aports + 1
		end
	end
	stats[repo].relevant_aports = relevant_aports
	stats[repo].total_aports = total_aports

	-- run prerepo hooks
	plugins_prerepo(conf, repo, stats[repo])

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
		aport.logfile = logfile_path(conf.logdir, repo, aport)
		tried = tried + 1
		local progress = {
			tried = tried,
			total = #pkgs,
			repo_built = stats[repo].relevant_aports - #pkgs + built,
			repo_total = stats[repo].relevant_aports,
		}
		if opts.s and (not db:known_deps_exists(aport)) then
			warn("%s: Skipped due to missing dependencies", aport.pkgname)
		elseif not (opts.s and skip_aport(aport)) then
			log_progress(progress, repo, aport)
			plugins_prebuild(conf, aport, progress)
			local success = build_aport(aport, conf.aportsdir, conf.repodest, aport.logfile, opts.R)
			plugins_postbuild(conf, aport, success)
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
		for aport, name in db:each() do
			if aport:relevant() then
				keep[aport:get_apk_file_name(name)] = true
			end
		end
		local apkrepodir = ("%s/%s/%s"):format(conf.repodest, repo, abuild.arch)
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
	if not opts.n and (built > 0 or deleted > 0) then
		info("Updating apk index")
		apkrepo.update_index(("%s/%s"):format(conf.repodest, repo),
				abuild.arch, db:git_describe())
	end
	stats[repo].built = built
	stats[repo].tried = tried
	stats[repo].deleted = deleted
	stats[repo].time = os.clock() - start_time

	-- run portrepo hooks
	plugins_postrepo(conf, repo, stats[repo])
end

for repo, stat in pairs(stats) do
	info("%s built:\t%d", repo, stat.built)
	info("%s tried:\t%d", repo, stat.tried)
	info("%s deleted:\t%d", repo, stat.deleted)
	info("%s total built:\t%d", repo, stat.relevant_aports - stat.tried + stat.built)
	info("%s total relevant aports:\t%d", repo, stat.relevant_aports)
	info("%s total aports:\t%d", repo, stat.total_aports)
end
