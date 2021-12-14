﻿-- This file is subject to copyright - contact swampservers@gmail.com for more information.
--NOMINIFY
-- TODO: check if having non byte aligned stuff matters for performance
local function bitsneeded(maxval)
    return math.ceil(math.log(maxval) / math.log(2))
end

-- this is to make sure the ids dont change order if we change them
-- APIDATAUSEDINDEXES = APIDATAUSEDINDEXES or {}
for i, v in ipairs({"API_DATALEN", "API_ANY", "API_STRUCT_ANY", "API_NIL", "API_FALSE", "API_TRUE", "API_EMPTYTABLE", "API_BOOL", "API_FLOAT", "API_DOUBLE", "API_INT8", "API_INT16", "API_INT32", "API_UINT", "API_UINT8", "API_UINT16", "API_UINT32", "API_STRING", "API_NT_STRING", "API_NETWORK_STRING", "API_NETWORK_STRING_TABLE_UPDATE", "API_VECTOR", "API_COMP_VECTOR", "API_ANGLE", "API_COMP_ANGLE", "API_ENTITY", "API_ENTITY_HANDLE", "API_TABLE", "API_LIST", "API_SET", "API_DICT", "API_STRUCT",}) do
    -- we can't use 1 because we wanna be able to do {TYPE} for a list and {[TYPE]=TYPE} for a dict
    -- if not _G[v] then
    --     _G[v] = i + 1
    --     while (APIDATAUSEDINDEXES[_G[v]] or v) ~= v do
    --         _G[v] = _G[v] + 1
    --     end
    --     APIDATAUSEDINDEXES[_G[v]] = v
    -- end
    _G[v] = i
    API_TYPESIZE = bitsneeded(i)
end

local API_TypeToType = {
    ["nil"] = function(x) return API_NIL end,
    boolean = function(x) return x and API_TRUE or API_FALSE end,
    number = function(x)
        if math.floor(x) ~= x then
            return API_DOUBLE
        elseif x < 0 then
            if x >= -128 then
                return API_INT8
            elseif x >= -32768 then
                return API_INT16
            elseif x >= -2147483648 then
                return API_INT32
            else
                return API_DOUBLE
            end
        else
            if x <= 255 then
                return API_UINT8
            elseif x <= 65535 then
                return API_UINT16
            elseif x <= 4294967295 then
                return API_UINT32
            else
                return API_DOUBLE
            end
        end
    end,
    string = function(x) return API_NetworkStringCache[x] and API_NETWORK_STRING or API_STRING end,
    Vector = function(x) return API_VECTOR end,
    Angle = function(x) return API_ANGLE end,
    Entity = function(x) return API_ENTITY end,
    Player = function(x) return API_ENTITY end,
    table = function(x) return API_TABLE end,
}

function API_GetTableType(x)
    local realcount = table.Count(x)
    if realcount == 0 then return API_EMPTYTABLE end

    for i = 1, realcount do
        if x[i] == nil then return API_DICT end
    end

    return API_LIST
end

function API_GetType(v)
    local fn = API_TypeToType[type(v)]

    if fn == nil then
        print("NOFN", type(v))
    end

    if fn(v) == nil then
        print("FFF", type(v))
    end

    return fn(v)
end

-- bidirectional mapping for NetworkStrings and IDs
API_NetworkStringCache = setmetatable({}, {
    __index = function(tab, key)
        local d

        if isnumber(key) then
            d = util.NetworkIDToString(key)
        else
            d = util.NetworkStringToID(key)

            if d == 0 then
                d = nil
            end
        end

        tab[key] = d

        return d
    end
})

local API_Readers = {
    [API_DATALEN] = function()
        local l1 = net.ReadUInt(8)

        return l1 == 255 and net.ReadUInt(16) or l1
    end,
    [API_ANY] = function() return API_Read(net.ReadUInt(API_TYPESIZE)) end,
    [API_STRUCT_ANY] = function() return API_Read(net.ReadUInt(API_TYPESIZE)) end,
    [API_NIL] = function() return nil end,
    [API_FALSE] = function() return false end,
    [API_TRUE] = function() return true end,
    [API_EMPTYTABLE] = function() return {} end,
    [API_BOOL] = net.ReadBool,
    [API_FLOAT] = net.ReadFloat,
    [API_DOUBLE] = net.ReadDouble,
    [API_INT8] = function() return net.ReadInt(8) end,
    [API_INT16] = function() return net.ReadInt(16) end,
    [API_INT32] = function() return net.ReadInt(32) end,
    [API_UINT] = function()
        local l1 = net.ReadUInt(8)

        return l1 == 255 and net.ReadUInt(32) or l1
    end,
    [API_UINT8] = function() return net.ReadUInt(8) end,
    [API_UINT16] = function() return net.ReadUInt(16) end,
    [API_UINT32] = function() return net.ReadUInt(32) end,
    [API_STRING] = function()
        local l = API_Read(API_DATALEN)

        return net.ReadData(l)
    end,
    [API_NT_STRING] = net.ReadString,
    [API_NETWORK_STRING] = function()
        local id = net.ReadUInt(12)
        local st = API_NetworkStringCache[id]

        if st == nil then
            ErrorNoHaltWithStack("Unknown network string! " .. id)

            return "UNKNOWN"
        end

        return st
    end,
    [API_NETWORK_STRING_TABLE_UPDATE] = function()
        local t = API_Struct().Read()
        t[1] = API_List(API_NETWORK_STRING).Read()

        return t
    end,
    [API_VECTOR] = function()
        local x = net.ReadFloat()
        local y = net.ReadFloat()
        local z = net.ReadFloat()

        return Vector(x, y, z)
    end,
    [API_COMP_VECTOR] = net.ReadVector,
    [API_ANGLE] = function()
        local x = net.ReadFloat()
        local y = net.ReadFloat()
        local z = net.ReadFloat()

        return Angle(x, y, z)
    end,
    [API_COMP_ANGLE] = net.ReadAngle,
    [API_ENTITY] = net.ReadEntity,
    [API_ENTITY_HANDLE] = function()
        assert(CLIENT)

        return EntityHandle(net.ReadInt(16))
    end,
    [API_TABLE] = function() return API_Dict().Read() end,
    [API_LIST] = function() return API_List().Read() end,
    [API_DICT] = function() return API_Dict().Read() end,
    [API_STRUCT] = function() return API_Struct().Read() end
}

local API_Writers = {
    [API_DATALEN] = function(v)
        if v > 255 then
            net.WriteUInt(255, 8)
            assert(v <= 65535)
            net.WriteUInt(v, 16)
        else
            net.WriteUInt(v, 8)
        end
    end,
    [API_ANY] = function(v)
        local typ = API_GetType(v)
        net.WriteUInt(typ, API_TYPESIZE)
        API_Write(typ, v)
    end,
    [API_STRUCT_ANY] = function(v)
        local typ = API_GetType(v)

        if typ == API_TABLE then
            typ = API_STRUCT
        end

        net.WriteUInt(typ, API_TYPESIZE)
        API_Write(typ, v)
    end,
    [API_NIL] = function(v) end,
    [API_FALSE] = function(v) end,
    [API_TRUE] = function(v) end,
    [API_EMPTYTABLE] = function(v) end,
    [API_BOOL] = net.WriteBool,
    [API_FLOAT] = net.WriteFloat,
    [API_DOUBLE] = net.WriteDouble,
    [API_INT8] = function(v) return net.WriteInt(v, 8) end,
    [API_INT16] = function(v) return net.WriteInt(v, 16) end,
    [API_INT32] = function(v) return net.WriteInt(v, 32) end,
    [API_UINT] = function(v)
        if v > 255 then
            net.WriteUInt(255, 8)
            net.WriteUInt(v, 32)
        else
            net.WriteUInt(v, 8)
        end
    end,
    [API_UINT8] = function(v) return net.WriteUInt(v, 8) end,
    [API_UINT16] = function(v) return net.WriteUInt(v, 16) end,
    [API_UINT32] = function(v) return net.WriteUInt(v, 32) end,
    [API_STRING] = function(v)
        local l = v:len()
        API_Write(API_DATALEN, l)
        net.WriteData(v, l)
    end,
    [API_NT_STRING] = net.WriteString,
    [API_NETWORK_STRING] = function(v)
        local id = API_NetworkStringCache[v]

        if not id and SERVER then
            util.AddNetworkString(v)
            id = API_NetworkStringCache[v]
        end

        if not id then
            ErrorNoHaltWithStack("No Network String ID! " .. v)
            id = 0
        end

        net.WriteUInt(id, 12)
    end,
    [API_NETWORK_STRING_TABLE_UPDATE] = function(v)
        local r = v[1]

        if r then
            v[1] = nil
        end

        API_Struct().Write(v)
        API_Set(API_NETWORK_STRING).Write(r or {})

        if r then
            v[1] = r
        end

        return t
    end,
    [API_VECTOR] = function(v)
        net.WriteFloat(v.x)
        net.WriteFloat(v.y)
        net.WriteFloat(v.z)
    end,
    [API_COMP_VECTOR] = net.WriteVector,
    [API_ANGLE] = function(v)
        net.WriteFloat(v.x)
        net.WriteFloat(v.y)
        net.WriteFloat(v.z)
    end,
    [API_COMP_ANGLE] = net.WriteAngle,
    [API_ENTITY] = net.WriteEntity,
    [API_ENTITY_HANDLE] = function(v)
        assert(SERVER)
        local id = ToHandleID(v)
        -- remember to destroy the handle later
        API_EntityHandles[id] = true
        net.WriteInt(id, 16)
    end,
    [API_TABLE] = function(v)
        API_Dict().Write(v)
    end,
    [API_LIST] = function(v)
        API_List().Write(v)
    end,
    [API_DICT] = function(v)
        API_Dict().Write(v)
    end,
    [API_STRUCT] = function(v)
        API_Struct().Write(v)
    end
}

function API_Union(...)
    local types = {...}

    local itypes, ntypes = table.Inverse(types), #types
    local typebits = bitsneeded(ntypes)
    -- any struct/list/dict should be the final type
    local table_type = types[ntypes]

    return {
        Read = function() return API_Read(types[net.ReadUInt(typebits)]) end,
        Write = function(v)
            local typ = API_GetType(v)

            if typ == API_TABLE then
                typ = table_type
            end

            net.WriteUInt(itypes[typ], typebits)
            API_Write(typ, v)
        end
    }
end

function API_Optional(typ)
    return API_Union(API_NIL, typ)
end

function API_List(value_type)
    value_type = value_type or API_ANY

    return {
        Read = function()
            local out, nvals = {}, API_Read(API_DATALEN)

            for i = 1, nvals do
                out[i] = API_Read(value_type)
            end

            return out
        end,
        Write = function(v)
            local nvals = #v
            API_Write(API_DATALEN, nvals)

            for i = 1, nvals do
                API_Write(value_type, v[i])
            end
        end
    }
end

function API_Dict(key_type, value_type)
    key_type = key_type or API_ANY
    value_type = value_type or API_ANY

    return {
        Read = function()
            local out, nvals = {}, API_Read(API_DATALEN)

            for i = 1, nvals do
                local k = API_Read(key_type)
                out[k] = API_Read(value_type)
            end

            return out
        end,
        Write = function(val)
            API_Write(API_DATALEN, table.Count(val))

            for k, v in pairs(val) do
                print(key_type, k, API_NETWORK_STRING)
                API_Write(key_type, k)
                API_Write(value_type, v)
            end
        end
    }
end

function API_Set(key_type)
    return API_Dict(key_type or API_ANY, API_TRUE)
end

--- A struct is a table with only string keys, and all string keys are kept on the NetworkString table. It's not as static as a C struct.
function API_Struct(value_type)
    return API_Dict(API_NETWORK_STRING, value_type or API_STRUCT_ANY)
end

function API_Read(typ)
    if istable(typ) then
        -- if typ.Read then
        return typ.Read()
    else -- end -- local key_type, value_type = next(typ) -- local nvals = API_Read(API_DATALEN) -- local out = {} -- -- list -- if key_type == 1 then --     for i = 1, nvals do --         out[i] = API_Read(value_type) --     end -- else --     for i = 1, nvals do --         local k = API_Read(key_type) --         out[k] = API_Read(value_type) --     end -- end -- return out
        return API_Readers[typ]()
    end
end

function API_Write(typ, val)
    if istable(typ) then
        -- if typ.Write then
        return typ.Write(val)
    else -- end -- local key_type, value_type = next(typ) -- -- list -- if key_type == 1 then --     local nvals = #val --     API_Write(API_DATALEN, nvals) --     for i = 1, nvals do --         API_Write(value_type, val[i]) --     end -- else --     API_Write(API_DATALEN, table.Count(val)) --     for k, v in pairs(val) do --         API_Write(key_type, k) --         API_Write(value_type, v) --     end -- end -- return out
        API_Writers[typ](val)
    end
end

-- special for broadcasting
-- AllPlayers = AllPlayers or {}
--- Register a function which is called on the server and executed on the client. See this file for details.
if CLIENT then
    function API_Command(name, argtypes, client_function, unreliable)
        unreliable = unreliable or false
        local nargs = #argtypes

        net.Receive(name, function()
            local argvals = {}

            for i = 1, nargs do
                argvals[i] = API_Read(argtypes[i])
            end

            client_function(unpack(argvals))
        end)
    end

    function API_Request(name, argtypes, unreliable)
        unreliable = unreliable or false
        local nargs = #argtypes

        _G["Request" .. name] = function(...)
            local argvals = {...}

            net.Start(name, unreliable)

            for i = 1, nargs do
                API_Write(argtypes[i], argvals[i])
            end

            net.SendToServer()
        end
    end
end

-- function API_Request(name, args, unreliable)
-- end
-- if SERVER then
-- end
-- this stuff is for sending info about entities that maybe aren't loaded yet
API_EntityHandles = API_EntityHandles or {}

function ToHandleID(ent)
    if not isentity(ent) then
        print(ent)
        ErrorNoHaltWithStack("WTF")

        return 0
    end

    if ent:IsPlayer() then
        local id = -ent:UserID()
        assert(id >= -32768)

        return id
    end

    local id = ent:EntIndex()
    assert(id >= 0 and id < 32768)

    return id
end

if CLIENT then
    function ApplyNetworkStringTableUpdate(tab, update)
        local remove = update[1]
        update[1] = nil

        for k, v in pairs(update) do
            tab[k] = v
        end

        for i, v in ipairs(remove) do
            tab[v] = nil
        end
    end

    function FromHandleID(id)
        return id < 0 and Player(-id) or Entity(id)
    end

    function EntityHandle(id)
        local h = API_EntityHandles[id]

        if not h then
            h = {
                id = id,
                ent = FromHandleID(id),
                callbacks = {},
                OnValid = function(handle, func)
                    if IsValid(handle.ent) then
                        func(handle.ent)
                    else
                        table.insert(handle.callbacks, func)
                    end
                end
            }

            API_EntityHandles[id] = h
        end

        return h
    end

    hook.Add("OnEntityCreated", "EntityHandle", function(ent)
        local h = API_EntityHandles[ToHandleID(ent)]

        if h then
            h.ent = ent

            for i, v in ipairs(h.callbacks) do
                v(ent)
            end

            table.Empty(h.callbacks)
        end
    end)

    -- added on server in sv_
    API_Command("CancelEntityHandle", {API_ENTITY_HANDLE}, function(h)
        API_EntityHandles[h.id] = nil
    end)
end
