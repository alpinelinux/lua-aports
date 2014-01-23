local M = {}

local lfs = require('lfs')

function M.update_index(dir, arch, description)
	local indexopt=""
	local descriptionopt=""
	local olddir = lfs.currentdir()
	local archdir = ("%s/%s"):format(dir, arch)
	assert(lfs.chdir(archdir), archdir)
	local signed_index = "APKINDEX.tar.gz"
	local unsigned_index = "APKINDEX.tar.gz.unsigned"
	if lfs.attributes(signed_index) ~= nil then
		indexopt = "--index "..signed_index
	end
	if description then
		descriptionopt="--description "..description
	end
	local indexcmd = ("apk index --quiet %s %s --output '%s' --rewrite-arch %s *.apk"):format(indexopt, descriptionopt, unsigned_index, arch)
	local signcmd = "abuild-sign -q "..unsigned_index
	assert(os.execute(indexcmd), indexcmd)
	assert(os.execute(signcmd), signcmd)
	assert(os.rename(unsigned_index, signed_index), signed_index)
	lfs.chdir(olddir)
end

return M
