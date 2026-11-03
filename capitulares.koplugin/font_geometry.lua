-- Capitulares v1.0 Teste 7: metricas reais, cache persistente.
-- Perfis opticos sao uma estimativa; o CREngine faz a composicao final.
local M={}
local SESSION={}
local SETTING='capitulares_v1_optical_metrics3'
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function stamp(path)
    local ok,lfs=pcall(require,'libs/libkoreader-lfs')
    if not ok then return nil end
    local a=lfs.attributes(path)
    if not a or not a.size then return nil end
    return tostring(a.size)..':'..tostring(a.modification or 0)
end
local function percentile(list,ratio)
    if #list==0 then return nil end
    table.sort(list)
    local i=clamp(math.floor((#list-1)*ratio+1.5),1,#list)
    return list[i]
end
local function fallback()
    return {height=0.92,width=0.88,measured=false}
end
local function readDB()
    if not G_reader_settings then return {} end
    local ok,data=pcall(G_reader_settings.readSetting,G_reader_settings,SETTING)
    return ok and type(data)=='table' and data or {}
end
local function writeDB(path,data)
    if not G_reader_settings then return end
    local db=readDB()
    db[path]=data
    pcall(G_reader_settings.saveSetting,G_reader_settings,SETTING,db)
end
function M.measure(path,index)
    if type(path)~='string' or path=='' then return fallback() end
    index=tonumber(index) or 0
    local key=path..'#'..index
    local current=stamp(path)
    if not current then return fallback() end
    if SESSION[key] and SESSION[key].stamp==current then return SESSION[key].profile end
    local entry=readDB()[key]
    if entry and entry.stamp==current and type(entry.profile)=='table' then
        SESSION[key]=entry
        return entry.profile
    end
    local profile=fallback()
    local ok=pcall(function()
        local Font=require('ui/font')
        local RenderText=require('ui/rendertext')
        -- A fonte e carregada pelo caminho real; nunca usar glyph fallback.
        local face=Font:getFace(path,64,index)
        if not face or type(face.size)~='number' or face.size<=0
            or not face.ftsize or not face.ftsize.hasGlyph then return end
        local heights,widths={},{ }
        local per_char={}
        for cp=65,90 do
            if face.ftsize:hasGlyph(cp) then
                local success,g=pcall(RenderText.getGlyph,RenderText,face,cp)
                if success and g and g.bb and g.bb.getHeight and g.bb.getWidth then
                    local h=g.bb:getHeight()/face.size
                    local w=math.max(g.bb:getWidth(),g.ax or 0)/face.size
                    if h>=0.2 and h<=2.6 and w>=0.2 and w<=2.6 then
                        local c=string.char(cp)
                        per_char[c]={height=h,width=w,top=(g.t or 0)/face.size}
                        heights[#heights+1]=h
                        widths[#widths+1]=w
                    end
                end
            end
        end
        if #heights<3 then return end
        -- A geometria CSS nao sabe a inicial do capitulo. Usa uma medida
        -- conservadora, privilegiando a inicial A e percentis, sem obrigar
        -- todas as letras a usar o maior glifo da fonte.
        local typical_h=percentile(heights,0.80) or 0.92
        local typical_w=percentile(widths,0.80) or 0.88
        profile={
            height=clamp(math.max(typical_h,(per_char.A and per_char.A.height or 0)),0.42,2.2),
            width=clamp(math.max(typical_w,(per_char.A and per_char.A.width or 0)),0.3,2.2),
            max_height=percentile(heights,1),
            glyphs=per_char,measured=true,
        }
    end)
    if not ok then profile=fallback() end
    SESSION[key]={stamp=current,profile=profile}
    writeDB(key,SESSION[key])
    return profile
end
return M
