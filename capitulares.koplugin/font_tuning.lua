-- Ajuste optico por fonte; nunca altera ficheiros TTF/OTF.
local M={}
local SETTING='capitulares_v1_font_tuning'
local function read()
    if not G_reader_settings then return {} end
    local ok,db=pcall(G_reader_settings.readSetting,G_reader_settings,SETTING)
    return ok and type(db)=='table' and db or {}
end
local function put(db)
    if G_reader_settings then G_reader_settings:saveSetting(SETTING,db) end
end
function M.get(path)
    if type(path)~='string' or path=='' then return 1 end
    local v=tonumber(read()[path])
    if not v or v~=v then return 1 end
    return math.max(0.85,math.min(1.25,v))
end
function M.set(path,value)
    if type(path)~='string' or path=='' then return false end
    local v=tonumber(value)
    if not v or v~=v then return false end
    local db=read()
    db[path]=math.max(0.85,math.min(1.25,v))
    put(db)
    return true
end
function M.reset(path)
    if type(path)~='string' or path=='' then return false end
    local db=read()
    db[path]=nil
    put(db)
    return true
end
return M
