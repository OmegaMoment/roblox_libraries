--!native
--!optimize 2
--[[
	! for this PLEASE go to the url and put the string inside of a modulescript INSIDE of the module. 
	! so it'd be something like 
	return [=[
		string
	]=]
	! it will be used as a fallback incase u can't fetch it.

	this is a reformat of what i made a while back, i haven't done that much lua work in a while... TwT
	meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow meow
	"fuck you kayra" <33333
]]

local propertyservice = {}

-- | localization
local game = game

local os_clock = os.clock

local table_sort = table.sort
local table_clone = table.clone

local pcall = pcall
local print = print
local warn = warn
local error = error
local require = require
local tonumber = tonumber

local Color3_new = Color3.new
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local UDim_new = UDim.new
local UDim2_new = UDim2.new
local BrickColor_new = BrickColor.new
local Rect_new = Rect.new
local NumberRange_new = NumberRange.new
local Enum = Enum

-- | caches
local cache_properties = {} -- [class] = {properties, sorted, read_only, is_creatable, count}
local cache_defaults = {} -- [class] = {[property] = value}
local cache_runtime_defaults = {} -- [class] = {[property] = value}
local cache_services = {} -- [class] = {[property] = type}
local cache_enums = {} -- [enum]  = enum data
local cache_classes = {} -- [class] = class data

local raw_api
local api_dump_url = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"

-- | dependencies
local HttpService = game:GetService("HttpService")

-- | dump strings etc :3
local unavailable_contexts = {
	RobloxScriptSecurity = true,
	RobloxSecurity = true,
	LocalUserSecurity = true,
	PluginSecurity = true,
}

local unavailable_tags = {
	Hidden = true,
	NotScriptable = true,
}

local dump_guards = { -- strings the api dump emits when it can't get a default TwT
	["__api_dump_class_not_creatable__"] = true,
	["__api_dump_failed_to_create_class__"] = true,
	["__api_dump_no_string_value__"] = true
}

-- | utilities

-- just a shitty parser for the api dump (some of them cause fuck roblox) TwT
local function parse_default_value(value_type: string, raw: string?, enum_name: string?): any
	if raw == nil or dump_guards[raw] then
		return nil
	end

	if value_type == "number" then
		return tonumber(raw)
		
	elseif value_type == "boolean" then
		return raw == "true"
		
	elseif value_type == "string" then
		return raw
		
	elseif value_type == "Color3" then
		local r, g, b = raw:match("([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
		if r then
			return Color3_new(tonumber(r), tonumber(g), tonumber(b))
		end
		
	elseif value_type == "Vector3" then
		local x, y, z = raw:match("([%d%.-]+),%s*([%d%.-]+),%s*([%d%.-]+)")
		if x then
			return Vector3_new(tonumber(x), tonumber(y), tonumber(z))
		end
		
	elseif value_type == "Vector2" then
		local x, y = raw:match("([%d%.-]+),%s*([%d%.-]+)")
		if x then
			return Vector2_new(tonumber(x), tonumber(y))
		end
		
	elseif value_type == "UDim" then
		local scale, offset = raw:match("([%d%.-]+),%s*([%d%.-]+)")
		if scale then
			return UDim_new(tonumber(scale), tonumber(offset))
		end
		
	elseif value_type == "UDim2" then
		-- "{x scale, x offset}, {y scale, y offset}"
		local xs, xo, ys, yo = raw:match("{([%d%.-]+),%s*([%d%.-]+)},%s*{([%d%.-]+),%s*([%d%.-]+)}")
		if xs then
			return UDim2_new(tonumber(xs), tonumber(xo), tonumber(ys), tonumber(yo))
		end
		
	elseif value_type == "EnumItem" and enum_name then
		local success, result = pcall(function()
			return Enum[enum_name][raw]
		end)
		
		if success and result then
			return result
		end
		
	elseif value_type == "BrickColor" then -- useless but whatever
		local success, result = pcall(BrickColor_new, raw)
		if success then
			return result
		end
		
	elseif value_type == "Rect" then
		local x, y, x1, y1 = raw:match("([%d%.-]+),%s*([%d%.-]+),%s*([%d%.-]+),%s*([%d%.-]+)")
		if x then
			return Rect_new(tonumber(x), tonumber(y), tonumber(x1), tonumber(y1))
		end
		
	elseif value_type == "NumberRange" then
		local mn, mx = raw:match("([%d%.-]+),%s*([%d%.-]+)")
		if mn then
			return NumberRange_new(tonumber(mn), tonumber(mx))
		end
		
	end
	
	-- | fuck these TwT
	return nil
end

local function normalize_value(member: any): (string?, string?)
	local value_type = member.ValueType
	if not value_type then
		return "unknown", nil
	end

	local category = value_type.Category
	local name = value_type.Name

	if category == "Enum" then
		return "EnumItem", name
		
	elseif category == "Class" then
		return "Instance", nil
		
	elseif category == "Primitive" then
		if name == "bool" then
			return "boolean", nil
			
		elseif name == "int" or name == "int64" or name == "Int64" or name == "double" or name == "float" then
			return "number", nil
			
		elseif name == "string" then
			return "string", nil
			
		else
			-- non serializeable primitive stuff (null etc)
			return nil, nil
		end
		
	elseif category == "DataType" then
		if name == "ContentId" then
			return "string", nil -- url string
			
		elseif name == "BinaryString" or name == "DateTime" or name == "buffer" or name == "ProtectedString" then
			return nil, nil -- not serializable
		end
		-- types keep their names :P
		return name, nil
		
	elseif category == "Group" then
		-- table based stuff not serializable TwT
		return nil, nil
	end

	return name, nil
end

-- | core

function propertyservice.fetch_classes()
	local start_time = os_clock()
	print("[propertyservice]: starting to fetch...")

	propertyservice.classes = {}
	propertyservice.enums = {}

	local success, result = pcall(function()
		return HttpService:GetAsync(api_dump_url, false)
	end)

	if success and result then
		raw_api = result
	else
		warn(`[propertyservice]: failed to fetch the apidump from tracker, using fallback. time_elapsed: {os_clock() - start_time}`)

		local ok, fallback = pcall(require, script:FindFirstChildWhichIsA("ModuleScript"))
		if ok then
			raw_api = fallback
		else
			error("[propertyservice]: no api dump available (network failed and no fallback found)")
		end
	end

	print(`[propertyservice]: successfully processed the apidump. time_elapsed: {os_clock() - start_time}`)
	local decoded = HttpService:JSONDecode(raw_api :: string)

	local class_count = 0
	local enum_count = 0

	for _, class in decoded.Classes do -- for loop of doom and misery
		local new_class = {
			name = class.Name,
			superclass = class.Superclass,
			properties = {},
			readonly_properties = {},
			deprecated_properties = {},
			serializable_properties = {},
			functions = {},
			deprecated_functions = {},
			events = {},
			deprecated_events = {},
			callbacks = {},
			deprecated_callbacks = {},
			tags = {},
			is_creatable = true,
			default_values = {},
			readonly_tags = {},
			hidden_tags = {},
			notscriptable_tags = {},
		}

		if class.Tags then
			for _, tag in class.Tags do
				new_class.tags[tag] = true
				
				if tag == "NotCreatable" then
					new_class.is_creatable = false
				end
				
			end
			
		end

		if class.Members then
			for _, member in class.Members do
				local member_type = member.MemberType
				local name = member.Name
				local tags = member.Tags or {}
				local is_deprecated = false

				for _, tag in tags do
					if tag == "Deprecated" then
						is_deprecated = true
						break
					end
				end

				if member_type == "Property" then
					local is_property = true
					local is_readonly = false

					for _, tag in tags do
						if unavailable_tags[tag] then
							is_property = false
							break
							
						elseif tag == "ReadOnly" then
							is_readonly = true
						end
					end

					local security = member.Security or {}
					if security.Read and unavailable_contexts[security.Read] then
						is_property = false
						
					elseif security.Write and unavailable_contexts[security.Write] then
						is_readonly = true
					end

					if is_property then
						local value_type, enum_name = normalize_value(member)
						if value_type then
							local parsed = parse_default_value(value_type, member.Default, enum_name)
							if parsed ~= nil then
								new_class.default_values[name] = parsed
							end

							local serialization = member.Serialization or {}
							new_class.serializable_properties[name] = serialization.CanSave == true

							if is_readonly then
								if is_deprecated then
									new_class.deprecated_properties[name] = value_type
									
								else
									new_class.readonly_properties[name] = value_type
								end
							else
								if is_deprecated then
									new_class.deprecated_properties[name] = value_type
									
								else
									new_class.properties[name] = value_type
								end
							end
							
						end
						
					end

					-- still probably useful to record them even when filtered
					for _, tag in tags do
						if tag == "ReadOnly" then
							new_class.readonly_tags[name] = true
							
						elseif tag == "Hidden" then
							new_class.hidden_tags[name] = true
							
						elseif tag == "NotScriptable" then
							new_class.notscriptable_tags[name] = true
						end
					end
					
				elseif member_type == "Function" then
					if is_deprecated then
						new_class.deprecated_functions[name] = true
						
					else
						new_class.functions[name] = true
					end
					
				elseif member_type == "Event" then
					if is_deprecated then
						new_class.deprecated_events[name] = true
						
					else
						new_class.events[name] = true
					end
					
				elseif member_type == "Callback" then
					if is_deprecated then
						new_class.deprecated_callbacks[name] = true
						
					else
						new_class.callbacks[name] = true
					end
					
				end
				
			end
			
		end

		propertyservice.classes[class.Name] = new_class
		class_count += 1
	end

	for _, enum in decoded.Enums do
		propertyservice.enums[enum.Name] = enum
		enum_count += 1
	end

	print(`[propertyservice]: processed apidump. classes: {class_count} | enums: {enum_count} | time_elapsed: {os_clock() - start_time}`)
end

propertyservice.fetch_classes()

function propertyservice.get_properties_of_class(class: string): ({[string]: string}, {string}, {[string]: string}, boolean, number, {[string]: boolean})
	local cached = cache_properties[class]
	if cached then
		return cached.properties, cached.sorted, cached.read_only, cached.is_creatable, cached.count, cached.serializable
	end

	local properties = {}
	local sorted_names = {}
	local read_only = {}
	local serializable = {}
	local current_class = class
	local count = 0

	local root_data = propertyservice.classes[class]
	local is_creatable = root_data and root_data.is_creatable or false

	while current_class do
		local data = propertyservice.classes[current_class]
		if not data then
			break
		end

		for name, type in data.properties do
			if not properties[name] and not read_only[name] then
				count += 1
				properties[name] = type
				sorted_names[count] = name
				serializable[name] = data.serializable_properties[name] == true
			end
		end

		for name, type in data.readonly_properties do
			if not read_only[name] then
				read_only[name] = type
			end
		end

		current_class = data.superclass
	end

	table_sort(sorted_names)

	cache_properties[class] = {
		properties = properties,
		sorted = sorted_names,
		read_only = read_only,
		is_creatable = is_creatable,
		count = count,
		serializable = serializable,
	}

	return properties, sorted_names, read_only, is_creatable, count, serializable
end

-- | returns [property] = type
function propertyservice.fetch_properties(instance: Instance): {[string]: string}
	local class = instance.ClassName
	local properties, _, read_only = propertyservice.get_properties_of_class(class)

	local property_to_type = table_clone(properties)
	for name, type in read_only do
		property_to_type[name] = type
	end

	return property_to_type
end

function propertyservice.get_service_data(class: string): {[string]: string}
	local cached = cache_services[class]
	if cached then
		return cached
	end

	local success, service = pcall(game.GetService, game, class)
	if not success then
		return {}
	end

	local properties = propertyservice.fetch_properties(service)
	cache_services[class] = properties
	return properties
end

-- | internal, not run time.
function propertyservice.fetch_default_properties(class: string): {[string]: any}
	local cached = cache_defaults[class]
	if cached then
		return cached
	end

	local property_to_value = {}
	local current_class = class

	while current_class do
		local data = propertyservice.classes[current_class]
		if not data then
			break
		end

		for name, value in data.default_values do
			if property_to_value[name] == nil then
				property_to_value[name] = value
			end
		end

		current_class = data.superclass
	end

	cache_defaults[class] = property_to_value
	return property_to_value
end

function propertyservice.fetch_runtime_default_properties(class: string): {[string]: any}
	local cached = cache_runtime_defaults[class]
	if cached then
		return cached
	end

	local dump_defaults = propertyservice.fetch_default_properties(class)
	local properties = propertyservice.get_properties_of_class(class)

	local class_data = propertyservice.classes[class]
	if not class_data or not class_data.is_creatable then
		-- | gotta get the dump, can't get it from runtime :P 
		cache_runtime_defaults[class] = dump_defaults
		return dump_defaults
	end

	local created, instance = pcall(Instance.new, class)
	if not created or not instance then
		cache_runtime_defaults[class] = dump_defaults
		return dump_defaults
	end

	local runtime_defaults = {}

	for name in properties do
		local success, value = pcall(function()
			return instance[name]
		end)

		if success then
			runtime_defaults[name] = value
		else
			-- | error? wtf?
			runtime_defaults[name] = dump_defaults[name]
		end
	end

	instance:Destroy()

	cache_runtime_defaults[class] = runtime_defaults
	return runtime_defaults
end

function propertyservice.get_enum_data(enum: string): any
	local cached = cache_enums[enum]
	if cached then
		return cached
	end

	local data = propertyservice.enums[enum]
	cache_enums[enum] = data
	return data
end

function propertyservice.get_class_data(class: string): any
	local cached = cache_classes[class]
	if cached then
		return cached
	end

	local data = propertyservice.classes[class]
	cache_classes[class] = data
	return data
end

return propertyservice
