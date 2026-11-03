-- KOReader UI language: Portuguese variants -> European Portuguese; other -> English.
local M={}
function M.isPortuguese()
    local lang=G_reader_settings and G_reader_settings:readSetting('language') or 'en'
    return type(lang)=='string' and lang:lower():match('^pt[%-%_]?')~=nil
end
function M.t(pt,en) return M.isPortuguese() and pt or en end
return M
