
ix.plugin = ix.plugin or {}
ix.plugin.list = ix.plugin.list or {}
ix.plugin.unloaded = ix.plugin.unloaded or {}

ix.util.Include("helix/gamemode/core/meta/sh_tool.lua")

-- luacheck: globals HOOKS_CACHE
HOOKS_CACHE = {}

function ix.plugin.Load(uniqueID, path, isSingleFile, variable)
	if (hook.Run("PluginShouldLoad", uniqueID) == false) then return end

	variable = variable or "PLUGIN"

	-- Plugins within plugins situation?
	local oldPlugin = PLUGIN
	local PLUGIN = {
		folder = path,
		plugin = oldPlugin,
		uniqueID = uniqueID,
		name = "Unknown",
		description = "Description not available",
		author = "Anonymous"
	}

	if (uniqueID == "schema") then
		if (Schema) then
			PLUGIN = Schema
		end

		variable = "Schema"
		PLUGIN.folder = engine.ActiveGamemode()
	elseif (ix.plugin.list[uniqueID]) then
		PLUGIN = ix.plugin.list[uniqueID]
	end

	_G[variable] = PLUGIN
	PLUGIN.loading = true

	if (!isSingleFile) then
		ix.lang.LoadFromDir(path .. "/languages")
		ix.util.IncludeDir(path .. "/libs", true)
		ix.attributes.LoadFromDir(path .. "/attributes")
		ix.faction.LoadFromDir(path .. "/factions")
		ix.class.LoadFromDir(path .. "/classes")
		ix.item.LoadFromDir(path .. "/items")
		ix.plugin.LoadFromDir(path .. "/plugins")
		ix.util.IncludeDir(path .. "/derma", true)
		ix.plugin.LoadEntities(path .. "/entities")

		hook.Run("DoPluginIncludes", path, PLUGIN)
	end

	ix.util.Include(isSingleFile and path or path .. "/sh_" .. variable:lower() .. ".lua", "shared")
	PLUGIN.loading = false

	local uniqueID2 = uniqueID

	if (uniqueID2 == "schema") then
		uniqueID2 = PLUGIN.name
	end

	function PLUGIN:SetData(value, global, ignoreMap)
		ix.data.Set(uniqueID2, value, global, ignoreMap)
	end

	function PLUGIN:GetData(default, global, ignoreMap, refresh)
		return ix.data.Get(uniqueID2, default, global, ignoreMap, refresh) or {}
	end

	hook.Run("PluginLoaded", uniqueID, PLUGIN)

	if (uniqueID != "schema") then
		PLUGIN.name = PLUGIN.name or "Unknown"
		PLUGIN.description = PLUGIN.description or "No description available."

		for k, v in pairs(PLUGIN) do
			if (isfunction(v)) then
				HOOKS_CACHE[k] = HOOKS_CACHE[k] or {}
				HOOKS_CACHE[k][PLUGIN] = v
			end
		end

		ix.plugin.list[uniqueID] = PLUGIN
		_G[variable] = nil
	end

	if (PLUGIN.OnLoaded) then
		PLUGIN:OnLoaded()
	end
end

function ix.plugin.GetHook(pluginName, hookName)
	local h = HOOKS_CACHE[hookName]

	if (h) then
		local p = ix.plugin.list[pluginName]

		if (p) then
			return h[p]
		end
	end

	return
end

function ix.plugin.LoadEntities(path)
	local bLoadedTools
	local files, folders

	local function IncludeFiles(path2, bClientOnly)
		if (SERVER and !bClientOnly) then
			if (file.Exists(path2 .. "init.lua", "LUA")) then
				ix.util.Include(path2 .. "init.lua", "server")
			elseif (file.Exists(path2 .. "shared.lua", "LUA")) then
				ix.util.Include(path2 .. "shared.lua")
			end

			if (file.Exists(path2 .. "cl_init.lua", "LUA")) then
				ix.util.Include(path2 .. "cl_init.lua", "client")
			end
		elseif (file.Exists(path2 .. "cl_init.lua", "LUA")) then
			ix.util.Include(path2 .. "cl_init.lua", "client")
		elseif (file.Exists(path2 .. "shared.lua", "LUA")) then
			ix.util.Include(path2 .. "shared.lua")
		end
	end

	local function HandleEntityInclusion(folder, variable, register, default, clientOnly, create, complete)
		files, folders = file.Find(path .. "/" .. folder .. "/*", "LUA")
		default = default or {}

		for _, v in ipairs(folders) do
			local path2 = path .. "/" .. folder .. "/" .. v .. "/"
			v = ix.util.StripRealmPrefix(v)

			_G[variable] = table.Copy(default)

			if (!isfunction(create)) then
				_G[variable].ClassName = v
			else
				create(v)
			end

			IncludeFiles(path2, clientOnly)

			if (clientOnly) then
				if (CLIENT) then
					register(_G[variable], v)
				end
			else
				register(_G[variable], v)
			end

			if (isfunction(complete)) then
				complete(_G[variable])
			end

			_G[variable] = nil
		end

		for _, v in ipairs(files) do
			local niceName = ix.util.StripRealmPrefix(string.StripExtension(v))

			_G[variable] = table.Copy(default)

			if (!isfunction(create)) then
				_G[variable].ClassName = niceName
			else
				create(niceName)
			end

			ix.util.Include(path .. "/" .. folder .. "/" .. v, clientOnly and "client" or "shared")

			if (clientOnly) then
				if (CLIENT) then
					register(_G[variable], niceName)
				end
			else
				register(_G[variable], niceName)
			end

			if (isfunction(complete)) then
				complete(_G[variable])
			end

			_G[variable] = nil
		end
	end

	local function RegisterTool(tool, className)
		local gmodTool = weapons.GetStored("gmod_tool")

		if (className:sub(1, 3) == "sh_") then
			className = className:sub(4)
		end

		if (gmodTool) then
			gmodTool.Tool[className] = tool
		else
			-- this should never happen
			ErrorNoHalt(string.format("attempted to register tool '%s' with invalid gmod_tool weapon", className))
		end

		bLoadedTools = true
	end

	-- Include entities.
	HandleEntityInclusion("entities", "ENT", scripted_ents.Register, {
		Type = "anim",
		Base = "base_gmodentity",
		Spawnable = true
	}, false, nil, function(ent)
		if (SERVER and ent.Holdable == true) then
			ix.allowedHoldableClasses[ent.ClassName] = true
		end
	end)

	-- Include weapons.
	HandleEntityInclusion("weapons", "SWEP", weapons.Register, {
		Primary = {},
		Secondary = {},
		Base = "weapon_base"
	})

	HandleEntityInclusion("tools", "TOOL", RegisterTool, {}, false, function(className)
		if (className:sub(1, 3) == "sh_") then
			className = className:sub(4)
		end

		TOOL = ix.meta.tool:Create()
		TOOL.Mode = className
		TOOL:CreateConVars()
	end)

	-- Include effects.
	HandleEntityInclusion("effects", "EFFECT", effects and effects.Register, nil, true)

	-- only reload spawn menu if any new tools were registered
	if (CLIENT and bLoadedTools) then
		RunConsoleCommand("spawnmenu_reload")
	end
end

function ix.plugin.Initialize()
	ix.plugin.unloaded = ix.data.Get("unloaded", {}, true, true)

	ix.plugin.LoadFromDir("helix/plugins")

	ix.plugin.Load("schema", engine.ActiveGamemode() .. "/schema")
	hook.Run("InitializedSchema")

	ix.plugin.LoadFromDir(engine.ActiveGamemode() .. "/plugins")
	hook.Run("InitializedPlugins")
end

function ix.plugin.Get(identifier)
	return ix.plugin.list[identifier]
end

function ix.plugin.LoadFromDir(directory)
	local files, folders = file.Find(directory .. "/*", "LUA")

	for _, v in ipairs(folders) do
		ix.plugin.Load(v, directory .. "/" .. v)
	end

	for _, v in ipairs(files) do
		ix.plugin.Load(string.StripExtension(v), directory .. "/" .. v, true)
	end
end

function ix.plugin.SetUnloaded(uniqueID, state, bNoSave)
	local plugin = ix.plugin.list[uniqueID]

	if (state) then
		if (plugin and plugin.OnUnload) then
			plugin:OnUnload()
		end

		ix.plugin.unloaded[uniqueID] = true
	elseif (ix.plugin.unloaded[uniqueID]) then
		ix.plugin.unloaded[uniqueID] = nil
	else
		return false
	end

	if (SERVER and !bNoSave) then
		local status

		if (state) then
			status = true
		end

		local unloaded = ix.data.Get("unloaded", {}, true, true)
			unloaded[uniqueID] = status
		ix.data.Set("unloaded", unloaded, true, true)
	end

	if (state) then
		hook.Run("PluginUnloaded", uniqueID)
	end

	return true
end

if (SERVER) then
	ix.plugin.repos = ix.plugin.repos or {}
	ix.plugin.files = ix.plugin.files or {}

	function ix.plugin.LoadRepo(url, name, callback, faultCallback)
		name = name or url

		local curPlugin = ""
		local curPluginName = ""
		local cache = {data = {url = url}, files = {}}

		MsgN("Loading plugins from '" .. url .. "'")

		http.Fetch(url, function(body)
			if (body:find("<h1>")) then
				local fault = body:match("<h1>([_%w%s]+)</h1>") or "Unknown Error"

				if (faultCallback) then
					faultCallback(fault)
				end

				return MsgN("\t* ERROR: " .. fault)
			end

			local exploded = string.Explode("\n", body)

			print("   * Repository identifier set to '" .. name .. "'")

			for _, line in ipairs(exploded) do
				if (line:sub(1, 1) == "@") then
					local key, value = line:match("@repo%-([_%w]+):[%s*](.+)")

					if (key and value) then
						if (key == "name") then
							print("   * " .. value)
						end

						cache.data[key] = value
					end
				else
					local fullName = line:match("!%b[]")

					if (fullName) then
						curPlugin = fullName:sub(3, -2)
						fullName = fullName:sub(8, -2)
						curPluginName = fullName
						cache.files[fullName] = {}

						MsgN("\t* Found '" .. fullName .. "'")
					elseif (curPlugin and line:sub(1, #curPlugin) == curPlugin and cache.files[curPluginName]) then
						table.insert(cache.files[curPluginName], line:sub(#curPlugin + 2))
					end
				end
			end

			file.CreateDir("helix/plugins")
			file.CreateDir("helix/plugins/" .. cache.data.id)

			if (callback) then
				callback(cache)
			end

			ix.plugin.repos[name] = cache
		end, function(fault)
			if (faultCallback) then
				faultCallback(fault)
			end

			MsgN("\t* ERROR: " .. fault)
		end)
	end

	function ix.plugin.Download(repo, plugin, callback)
		local plugins = ix.plugin.repos[repo]

		if (plugins) then
			if (plugins.files[plugin]) then
				local files = plugins.files[plugin]
				local baseDir = "helix/plugins/" .. plugins.data.id .. "/" .. plugin .. "/"

				-- Re-create the old file.Write behavior.
				local function WriteFile(name, contents)
					name = string.StripExtension(name) .. ".txt"

					if (name:find("/")) then
						local exploded = string.Explode("/", name)
						local tree = ""

						for k, v in ipairs(exploded) do
							if (k == #exploded) then
								file.Write(baseDir .. tree .. v, contents)
							else
								tree = tree .. v .. "/"
								file.CreateDir(baseDir .. tree)
							end
						end
					else
						file.Write(baseDir .. name, contents)
					end
				end

				MsgN("* Downloading plugin '" .. plugin .. "' from '" .. repo .. "'")
				ix.plugin.files[repo .. "/" .. plugin] = {}

				local function DownloadFile(i)
					MsgN("\t* Downloading... " .. (math.Round(i / #files, 2) * 100) .. "%")

					local url = plugins.data.url .. "/repo/" .. plugin .. "/" .. files[i]

					http.Fetch(url, function(body)
						WriteFile(files[i], body)
						ix.plugin.files[repo .. "/" .. plugin][files[i]] = body

						if (i < #files) then
							DownloadFile(i + 1)
						else
							if (callback) then
								callback(true)
							end

							MsgN("* '" .. plugin .. "' has completed downloading")
						end
					end, function(fault)
						callback(false, fault)
					end)
				end

				DownloadFile(1)
			else
				return false, "cloud_no_plugin"
			end
		else
			return false, "cloud_no_repo"
		end
	end

	function ix.plugin.LoadFromLocal(repo, plugin)

	end

	concommand.Add("ix_cloudloadrepo", function(client, _, arguments)
		local url = arguments[1]
		local name = arguments[2] or "default"

		if (!IsValid(client)) then
			ix.plugin.LoadRepo(url, name)
		end
	end)

	concommand.Add("ix_cloudget", function(client, _, arguments)
		if (!IsValid(client)) then
			local status, result = ix.plugin.Download(arguments[2] or "default", arguments[1])

			if (status == false) then
				MsgN("* ERROR: " .. result)
			end
		end
	end)
end

do
	-- luacheck: globals hook
	hook.ixCall = hook.ixCall or hook.Call

	function hook.Call(name, gm, ...)
		local cache = HOOKS_CACHE[name]

		if (cache) then
			for k, v in pairs(cache) do
				local a, b, c, d, e, f = v(k, ...)

				if (a != nil) then
					return a, b, c, d, e, f
				end
			end
		end

		if (Schema and Schema[name]) then
			local a, b, c, d, e, f = Schema[name](Schema, ...)

			if (a != nil) then
				return a, b, c, d, e, f
			end
		end

		return hook.ixCall(name, gm, ...)
	end
end
