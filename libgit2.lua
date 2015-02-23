require'libgit2_h'
local ffi = require'ffi'
local C = ffi.load'git2'
local git = setmetatable({}, {__index = C})

--helpers

local function check(ret)
	if ret >= 0 then return ret end
	local e = C.giterr_last()
	error(string.format('libgit2 error: %d/%d: %s',
		ret, e.klass, ffi.string(e.message)))
end

local function checkh(ret)
	if ret ~= nil then return ret end
	local e = C.giterr_last()
	error(string.format('libgit2 error: %d/%d: %s',
		ret, e.klass, ffi.string(e.message)))
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

local function strarray_to_table(sa)
	local t = {}
	for i = 1, tonumber(sa.count) do
		t[i] = ffi.string(sa.strings[i-1])
	end
	return t
end

--procedural API

git.GIT_OID_RAWSZ = 20
git.GIT_OID_HEXSZ = git.GIT_OID_RAWSZ * 2

function git.version()
	local v = ffi.new'int[3]'
	C.git_libgit2_version(v, v+1, v+2)
	return v[0], v[1], v[2]
end

function git.oid(s)
	if type(s) ~= 'string' then return s end
	local oid = ffi.new'git_oid'
	check(C.git_oid_fromstr(oid, s))
	return oid
end

function git.oid_tostr(oid)
	local out = ffi.new('char[?]', git.GIT_OID_HEXSZ+1)
	C.git_oid_tostr(out, git.GIT_OID_HEXSZ+1, oid)
	return ffi.string(out, sz)
end

function git.open(path, flags, ceiling_dirs)
	local repo = ffi.new'git_repository*[1]'
	check(C.git_repository_open_ext(repo, path, flags or 0, ceiling_dirs))
	repo = repo[0]
	ffi.gc(repo, C.git_repository_free)
	return repo
end

function git.repo_free(repo)
	ffi.gc(repo, nil)
	C.git_repository_free(repo)
end

function git.tags(repo)
	local tags = ffi.new'git_strarray'
	check(C.git_tag_list(tags, repo))
	return strarray_to_table(tags)
end

function git.tag_lookup(repo, oid)
	oid = oid or git.oid(oid)
	local tag = ffi.new'git_tag*[1]'
	check(C.git_tag_lookup(tag, repo, oid))
	tag = tag[0]
	ffi.gc(tag, C.git_tag_free)
	return tag
end

function git.tag_free(tag)
	ffi.gc(tag, nil)
	C.git_tag_free(tag)
end

local function getref(func)
	return function(...)
		local ref = ffi.new'git_reference*[1]'
		check(func(ref, ...))
		ref = ref[0]
		ffi.gc(ref, C.git_reference_free)
		return ref
	end
end

git.ref_lookup = getref(C.git_reference_lookup)
git.ref_dwim = getref(C.git_reference_dwim)

function git.ref_name_to_id(repo, name)
	local oid = ffi.new'git_oid'
	check(C.git_reference_name_to_id(oid, repo, name))
	return oid
end

function git.ref_name(ref)
	return ffi.string(checkh(C.git_reference_name(ref)))
end

function git.ref_free(ref)
	ffi.gc(ref, nil)
	C.git_reference_free(ref)
end

function git.refs(repo)
	local refs = ffi.new'git_strarray'
	check(C.git_reference_list(refs, repo))
	return strarray_to_table(refs)
end

function git.commit(repo, oid)
	oid = git.oid(oid)
	local commit = ffi.new'git_commit*[1]'
	check(C.git_commit_lookup(commit, repo, oid))
	commit = commit[0]
	ffi.gc(commit, C.git_commit_free)
	return commit
end

function git.commit_free(commit)
	ffi.gc(commit, nil)
	C.git_commit_free(commit)
end

function git.commit_tree(commit)
	local tree = ffi.new'git_tree*[1]'
	check(C.git_commit_tree(tree, commit))
	tree = tree[0]
	ffi.gc(tree, C.git_tree_free)
	return tree
end

function git.tree_lookup(repo, oid)
	local tree = ffi.new'git_tree*[1]'
	check(C.git_tree_lookup(tree, repo, oid))
	tree = tree[0]
	ffi.gc(tree, C.git_tree_free)
	return tree
end

function git.tree_free(tree)
	ffi.gc(tree, nil)
	C.git_tree_free(tree)
end

function git.tree_entrycount(tree)
	return tonumber(check(C.git_tree_entrycount(tree)))
end

function git.tree_entry_byindex(tree, i)
	return checkh(C.git_tree_entry_byindex(tree, i))
end

function git.tree_walk(repo, tree, func, level)
	level = level or 0
	for i = 0, tree:count()-1 do
		local entry = tree:byindex(i)
		func(entry, tree, level)
		if entry:type() == C.GIT_OBJ_TREE then
 			local subtree = repo:tree_lookup(entry:id())
 			git.tree_walk(repo, subtree, func, level + 1)
 			subtree:free()
		end
	end
end

function git.files(repo, tree, func)
	local level0, name0 = 0
	local parents = {}
	return coroutine.wrap(function()
		git.tree_walk(repo, tree, function(entry, tree, level)
				local name = entry:name()
				if level > level0 then
					table.insert(parents, name0)
				elseif level < level0 then
					table.remove(parents)
				end
				table.insert(parents, name)
				local path = table.concat(parents, '/')
				table.remove(parents)
				coroutine.yield(path)
				level0, name0 = level, name
			end)
	end)
end

git.tree_entry_type = C.git_tree_entry_type

function git.tree_entry_name(entry)
	return ffi.string(C.git_tree_entry_name(entry))
end

git.tree_entry_id = C.git_tree_entry_id

local function findconfig(func)
	return function()
		local sz = 4096
		local path = ffi.new('char[?]', sz)
		check(func(path, sz))
		return ffi.string(path)
	end
end
git.config_find_global = findconfig(C.git_config_find_global)
git.config_find_xdg    = findconfig(C.git_config_find_xdg)
git.config_find_system = findconfig(C.git_config_find_system)

local function getconfig(func)
	return function(...)
		local cfg = ffi.new'git_config*[1]'
		check(func(cfg, ...))
		cfg = cfg[0]
		ffi.gc(cfg, C.git_config_free)
		return cfg
	end
end

git.config_open_default = getconfig(C.git_config_open_default)
git.repo_config = C.git_repository_config

	ffi.gc(cfg, C.git_config_free)


function git.config(repo, var)
		local cfg = ffi.new'git_config*cfg[1]'
		check(C.git_config_open_default(cfg))
		C.git_repository_config(cfg, repo)
	C.git_config_get_string
end

--object API

ffi.metatype('git_oid', {__index = {
		tostr = git.oid_tostr,
	}})

ffi.metatype('git_repository', {__index = {
		free = git.repo_free,
		tags = git.tags,
		commit = git.commit,
		tag_lookup = git.tag_lookup,
		tree_lookup = git.tree_lookup,
		ref_lookup = git.ref_lookup,
		ref_dwim = git.ref_dwim,
		ref_name_to_id = git.ref_name_to_id,
		refs = git.refs,
		walk = git.tree_walk,
		files = git.files,
	}})

ffi.metatype('git_tag', {__index = {
		free = git.tag_free,
	}})

ffi.metatype('git_reference', {__index = {
		free = git.ref_free,
		name = git.ref_name,
	}})

ffi.metatype('git_commit', {__index = {
		free = git.commit_free,
		tree = git.commit_tree,
	}})

ffi.metatype('git_tree', {__index = {
		free = git.tree_free,
		count = git.tree_entrycount,
		byindex = git.tree_entry_byindex,
	}})

ffi.metatype('git_tree_entry', {__index = {
		type = git.tree_entry_type,
		name = git.tree_entry_name,
		id   = git.tree_entry_id,
	}})


if not ... then

	local pp = require'pp'
	local lfs = require'lfs'
	print(git.version())

	local pwd = lfs.currentdir()
	lfs.chdir'../../../luapower'

	local repo = git.open'.'

	pp(repo:tags())
	pp(repo:refs())

	local ref = repo:ref_dwim'master'
	local id = repo:ref_name_to_id(ref:name())
	print(id:tostr())
	local commit = repo:commit(id)
	local tree = commit:tree()
	for path in repo:files(tree) do
		print(path)
	end

	tree:free()
	commit:free()
	ref:free()
	repo:free()

	lfs.chdir(pwd)
end

return git

