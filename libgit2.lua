require'libgit2_h'
local ffi = require'ffi'
local C = ffi.load'git2'
local M = setmetatable({}, {__inedx = C})

local function check(ret)
	if ret >= 0 then return ret end
	local e = C.giterr_last()
	error(string.format('libgit2 error: %d/%d: %s',
		ret, e.klass, ffi.string(e.message)))
end

local function version()
	local v = ffi.new'int[3]'
	C.git_libgit2_version(v, v+1, v+2)
	return v[0], v[1], v[2]
end

local function git_buf(size)
	local buf = ffi.new'git_buf'
	local p = ffi.new('uint8_t[?]', size)
	buf.ptr = p
	buf.asize = size
	ffi.gc(buf, function()
		p = nil
	end)
	return buf
end

function M.test()
	local lfs = require'lfs'
	print(version())

	local pwd = lfs.currentdir()
	lfs.chdir'../../../luapower'

	--local buf = git_buf(4096)
	--check(C.git_config_find_xdg(buf))

	--local cfg = ffi.new'git_config*[1]'
	--check(C.git_config_open_default(cfg))

	local repo = ffi.new'git_repository*[1]'
	check(C.git_repository_open_ext(repo,
		'/root/test-git/.git',
		C.GIT_REPOSITORY_OPEN_BARE, nil))
	repo = repo[0]

	--local cfg = ffi.new'git_config*[1]'
	--check(C.git_repository_config(cfg, repo))

	local tags = ffi.new'git_strarray'
	check(C.git_tag_list(tags, repo))

	for i=1,tonumber(tags.count) do
		print(ffi.string(tags.strings[i-1]))
	end

	lfs.chdir(pwd)
end

if not ... then
	M.test()
end

return M
