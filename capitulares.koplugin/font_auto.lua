-- Fontes decorativas: normaliza apenas glifos ausentes, com cache incremental.
-- O motor de leitura pode registar uma fonte durante a sessao; as que ja
-- existem ficam disponiveis sem necessitar de reiniciar entre escolhas.
local alias=require('font_alias')
local T=require('ci_lang').t
local M={}
local SESSION={}
local CACHE_SETTING='capitulares_v1_font_cache2'
local function hashPath(path)
    local n=0
    for i=1,#path do n=(n*131+path:byte(i))%4294967296 end
    return string.format('%08x',n)
end
local function stamp(path)
    local lfs=require('libs/libkoreader-lfs')
    local a=lfs.attributes(path)
    if not a or not a.size then return nil end
    return tostring(a.size)..':'..tostring(a.modification or a.change or 0)
end
local function exists(path)
    local f=io.open(path,'rb')
    if not f then return false end
    f:close();return true
end
local function cache()
    return G_reader_settings:readSetting(CACHE_SETTING) or {}
end
local function remember(path,key,val)
    local c=cache();c[key]={stamp=stamp(path),value=val}
    G_reader_settings:saveSetting(CACHE_SETTING,c)
end
local function findDir(path)
    return path:match('^(.*/)[^/]+$')
end
local function targetFor(rec)
    local path=rec.path
    local dir=rec.preferred and findDir(path) or (require('fontlist').fontdir..'/Initials/')
    if not dir then return nil end
    if not rec.preferred then
        local lfs=require('libs/libkoreader-lfs')
        if lfs.attributes(dir,'mode')~='directory' then
            if not lfs.mkdir(dir) and lfs.attributes(dir,'mode')~='directory' then return nil end
        end
    end
    local base=path:match('([^/]+)$')
    if not base then return nil end
    local ext=base:lower():match('%.otf$') and '.otf' or '.ttf'
    local stem=base:sub(1,#base-4):gsub('[^%w%._%-]','_')
    -- CI2 separa a tabela corrigida da antiga que perdia glifos originais.
    local filename='CI2-'..stem..'-'..hashPath(path)..ext
    local family='CI2 '..rec.name:gsub('[^%w%s%-]','')
    if #family>65 then family=family:sub(1,65) end
    return dir..filename,family
end
function M.prepare(rec)
    if not rec or type(rec.name)~='string' then return nil,T('Fonte inválida.','Invalid font.') end
    if rec.name:match('^CI2 ') then return {name=rec.name,path=rec.path,ready=true} end
    local path=rec.path
    if type(path)~='string' or not path:lower():match('%.([to]tf)$') or (rec.index or 0)~=0 then
        return {name=rec.name,ready=true}
    end
    local srcstamp=stamp(path)
    if not srcstamp then return nil,T('Fonte original indisponível.','Original font unavailable.') end
    local key=hashPath(path)
    local cached=SESSION[path]
    if cached and cached.stamp==srcstamp then return cached.result end
    local persisted=cache()[key]
    local target,family=targetFor(rec)
    if not target then return nil,T('Pasta de fontes indisponível.','Font folder unavailable.') end
    local result
    if persisted and persisted.stamp==srcstamp and persisted.value=='original' then
        result={name=rec.name,ready=true}
    elseif persisted and persisted.stamp==srcstamp and persisted.value=='alias' and exists(target) then
        result={name=family,path=target,ready=true}
    else
        local needs,why=alias.needsNormalization(path)
        if needs==nil then return nil,why end
        if not needs then
            result={name=rec.name,ready=true}
            remember(path,key,'original')
        else
            local ok,err=alias.normalizeFile(path,target,family)
            if not ok then return nil,err end
            result={name=family,path=target,ready=true}
            remember(path,key,'alias')
        end
    end
    SESSION[path]={stamp=srcstamp,result=result}
    return result
end
function M.register(prepared)
    if not prepared or not prepared.path then return true end
    local cre=require('document/credocument'):engineInit()
    for _,name in ipairs(cre.getFontFaces() or {}) do
        if name==prepared.name then return true end
    end
    local ok=pcall(cre.registerFont,prepared.path)
    if not ok then return false end
    for _,name in ipairs(cre.getFontFaces() or {}) do
        if name==prepared.name then return true end
    end
    return false
end
function M.prepareAndRegister(rec)
    local result,err=M.prepare(rec)
    if not result then return nil,err end
    if result.path and not M.register(result) then
        return {name=rec.name,failed_registration=true},'CREngine did not register font'
    end
    return result
end
-- Preparacao incremental: so Initials; nao percorre as fontes de texto comuns.
function M.prewarm(records,onDone)
    if M._prewarmStarted then return end
    M._prewarmStarted=true
    local UIManager=require('ui/uimanager')
    local list={}
    for _,rec in ipairs(records or {}) do
        if rec.preferred then list[#list+1]=rec end
    end
    local index=0
    local function step()
        index=index+1
        if index>#list then
            M._prewarmDone=true
            if onDone then onDone() end
            return
        end
        local rec=list[index]
        local ok=pcall(M.prepareAndRegister,rec)
        -- Falhas individuais nao bloqueiam a biblioteca nem as restantes fontes.
        UIManager:nextTick(step)
    end
    UIManager:nextTick(step)
end
return M
