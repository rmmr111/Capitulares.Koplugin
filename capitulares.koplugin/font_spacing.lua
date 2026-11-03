-- Capitulares v1.0: ajustes opticos independentes por fonte.
-- Chave por caminho+indice (ou nome se a fonte nao tem caminho).
-- Nunca modifica ficheiros TTF/OTF nem preferencias tipograficas do livro.
local M={}
local SETTING='capitulares_v1_font_spacing'
local function bounded(v,lo,hi)
    v=tonumber(v)
    if not v or v~=v or v==math.huge or v==-math.huge then return nil end
    return math.max(lo,math.min(hi,v))
end
local function read()
    if not G_reader_settings then return {} end
    local ok,db=pcall(G_reader_settings.readSetting,G_reader_settings,SETTING)
    return ok and type(db)=='table' and db or {}
end
function M.key(mode,path,name,index)
    if mode=='book' then return 'book:inherit' end
    if type(path)=='string' and path~='' then
        return 'path:'..path..'#'..tostring(tonumber(index) or 0)
    end
    if type(name)=='string' and name~='' then return 'name:'..name end
    return nil
end
function M.get(key)
    if not key then return nil end
    local data=read()[key]
    if type(data)~='table' then return nil end
    local size=bounded(data.size,1.5,8.5)
    local gap=bounded(data.gap,0,0.8)
    local vertical=bounded(data.vertical,-0.65,0.65)
    if not size or not gap or not vertical then return nil end
    local profile={size=size,gap=gap,vertical=vertical,offset_x=bounded(data.offset_x,-0.40,0.40) or 0}
    for _,k in ipairs({'size_px','gap_px','vertical_px','offset_x_px'}) do
        local px=bounded(data[k],-2000,2000)
        if px then profile[k]=px end
    end
    return profile
end
function M.set(key,data)
    if not key or type(data)~='table' then return false end
    local size=bounded(data.size,1.5,8.5)
    local gap=bounded(data.gap,0,0.8)
    local vertical=bounded(data.vertical,-0.65,0.65)
    if not size or not gap or not vertical then return false end
    local db=read()
    db[key]={size=size,gap=gap,vertical=vertical,offset_x=bounded(data.offset_x,-0.40,0.40) or 0}
    for _,k in ipairs({'size_px','gap_px','vertical_px','offset_x_px'}) do
        local px=bounded(data[k],-2000,2000)
        if px then db[key][k]=px end
    end
    G_reader_settings:saveSetting(SETTING,db)
    return true
end
function M.reset(key)
    if not key then return false end
    local db=read()
    db[key]=nil
    G_reader_settings:saveSetting(SETTING,db)
    return true
end
return M
