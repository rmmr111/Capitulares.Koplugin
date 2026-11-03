-- Lista do CREngine; filtro conservador para capitulares alfabéticas.
-- Usa fontes existentes, sem ficheiros alterados ou dependências externas.
local M={}
local SESSION={}
local CACHE_KEY='capitulares_v1_usable_font_cache_t15'
local cache_loaded
local cache_dirty=false
local function preferred(path)
    return type(path)=='string' and path:lower():gsub('\\','/'):find('/initials/',1,true)~=nil
end
M.preferred=preferred
local function symbolName(name)
    local n=(name or ''):lower()
    -- Uma fonte nomeada como conjunto de ornamentos não é uma capitular.
    for _,word in ipairs({'fleuron','dingbat','wingding','webding','pictogram',
        'emoji','symbols','symbol font','ornaments','ornament set',
        'borders','border font','icons','icon font','decorative elements'}) do
        if n:find(word,1,true) then return true end
    end
    return false
end
local function stamp(path)
    if not path or path=='' then return nil end
    local ok,lfs=pcall(require,'libs/libkoreader-lfs')
    if not ok then return nil end
    local a=lfs.attributes(path)
    if not a then return nil end
    return tostring(a.size or 0)..':'..tostring(a.modification or 0)
end
local function readCache()
    if cache_loaded then return cache_loaded end
    local ok,data=pcall(function()
        return G_reader_settings and G_reader_settings:readSetting(CACHE_KEY)
    end)
    cache_loaded=ok and type(data)=='table' and data or {}
    return cache_loaded
end
-- Precisamos das 26 maiúsculas; uma fonte parcial pode deixar a primeira
-- letra invisível no ::first-letter do CREngine, como foi visto no Kobo.
local function hasAlphabet(rec)
    if not rec.path or rec.path=='' then return nil end
    local ok,result=pcall(function()
        local Font=require('ui/font')
        local face=Font:getFace(rec.path,24,rec.index or 0)
        if not face or not face.ftsize or not face.ftsize.hasGlyph then return nil end
        for cp=65,90 do
            if not face.ftsize:hasGlyph(cp) then return false end
        end
        -- Checking character coverage alone is not enough: some symbol fonts
        -- supply an empty glyph for a letter. Inspect a few real ink boxes.
        local rt_ok,RenderText=pcall(require,'ui/rendertext')
        if rt_ok and RenderText and RenderText.getGlyph then
            for _,cp in ipairs({65,77,81,90}) do  -- A, M, Q, Z
                local rendered,glyph=pcall(RenderText.getGlyph,RenderText,face,cp)
                if rendered and glyph and glyph.bb and
                    glyph.bb.getWidth and glyph.bb.getHeight and
                    (glyph.bb:getWidth()<=0 or glyph.bb:getHeight()<=0) then
                    return false
                end
            end
        end
        return true
    end)
    if ok then return result end
    return nil
end
function M.usable(rec)
    if not rec or type(rec.name)~='string' then return false end
    if symbolName(rec.name) then return false end
    local sig=stamp(rec.path)
    local key=tostring(rec.path)..'#'..tostring(rec.index or 0)
    if sig and SESSION[key] and SESSION[key].sig==sig then
        return SESSION[key].value
    end
    local cache=readCache()
    if sig and type(cache[key])=='table' and cache[key].sig==sig then
        SESSION[key]=cache[key]
        return cache[key].value
    end
    local result=hasAlphabet(rec)
    -- A fonte não pode ser inspecionada: não a excluir apenas por precaução.
    -- A escolha tipográfica continua disponível com fallback CSS serif.
    if result==nil then return true end
    if sig then
        local entry={sig=sig,value=result}
        SESSION[key]=entry
        cache[key]=entry
        cache_dirty=true
    end
    return result
end
function M.list(usable_only)
    local cre=require('document/credocument'):engineInit()
    local faces=cre.getFontFaces() or {}
    local records={};local seen={}
    for _,name in ipairs(faces) do
        if type(name)=='string' and name~='' and not seen[name] and
            not name:match('^CI ') and not name:match('^CI2 ') then
            seen[name]=true
            local path,index
            local ok,a,b=pcall(cre.getFontFaceFilenameAndFaceIndex,name)
            if ok then path,index=a,b end
            local rec={name=name,path=path,index=index or 0,preferred=preferred(path)}
            if not usable_only or M.usable(rec) then records[#records+1]=rec end
        end
    end
    if cache_dirty and G_reader_settings then
        pcall(G_reader_settings.saveSetting,G_reader_settings,CACHE_KEY,readCache())
        cache_dirty=false
    end
    table.sort(records,function(a,b)
        if a.preferred~=b.preferred then return a.preferred end
        return a.name:lower()<b.name:lower()
    end)
    return records
end
return M
