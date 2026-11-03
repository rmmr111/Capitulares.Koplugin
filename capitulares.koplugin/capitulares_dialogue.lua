-- Capitulares v1.0: impedir capitulares que englobam travessoes de dialogo.
-- O texto do EPUB e lido APENAS em memoria; nunca exportado nem guardado.
local M={}
local LEADING={
    '\239\187\191', -- UTF-8 BOM
    '\194\160', -- no-break space
    '\226\128\139', -- zero-width space
    '\226\128\175', -- narrow no-break space
    '\226\128\137', -- thin space
    '\226\128\138', -- hair space
}
local PREFIXES={
    '—', -- travessao (U+2014)
    '–', -- meia-risca (U+2013)
    '―', -- barra horizontal (U+2015)
    '‒', -- figure dash (U+2012)
    '−', -- sinal de menos (U+2212)
    '-', -- hifen ASCII, usado em varios EPUBs antigos
}
local QUOTES={'«','“','„','\"','‘','\''}
local function trim(t)
    for _=1,16 do
        local old=t
        t=t:gsub('^%s+','')
        for _,v in ipairs(LEADING) do
            if t:sub(1,#v)==v then t=t:sub(#v+1) end
        end
        if old==t then break end
    end
    return t
end
function M.startsWithDialogue(text)
    if type(text)~='string' or #text==0 then return false end
    local t=trim(text)
    -- Alguns EPUBs iniciam o dialogo com aspas tipograficas antes do travessao.
    for _,q in ipairs(QUOTES) do
        if t:sub(1,#q)==q then t=trim(t:sub(#q+1));break end
    end
    for _,dash in ipairs(PREFIXES) do
        if t:sub(1,#dash)==dash then return true end
    end
    return false
end
function M.isDialogue(doc,pointer,fallback)
    if not doc or type(doc.getTextFromXPointer)~='function' then return false end
    local function safeGet(xp)
        if not xp then return nil end
        local ok,s=pcall(doc.getTextFromXPointer,doc,xp)
        return ok and type(s)=='string' and s or nil
    end
    local text=safeGet(pointer)
    if text==nil or text=='' then text=safeGet(fallback) end
    return M.startsWithDialogue(text)
end
return M
