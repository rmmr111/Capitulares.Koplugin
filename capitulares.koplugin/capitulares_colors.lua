-- Capitulares v1.0: colors are optional and ONLY applied to the drop cap.
-- Keep a strict palette: book settings never become arbitrary CSS input.
local M={}
local entries={
    {id='original',pt='Original',en='Original'},
    {id='ruby',pt='Vinho',en='Wine',hex='#8B2635',r=139,g=38,b=53},
    {id='copper',pt='Cobre',en='Copper',hex='#9B4B25',r=155,g=75,b=37},
    {id='gold',pt='Ouro antigo',en='Antique gold',hex='#896118',r=137,g=97,b=24},
    {id='forest',pt='Verde floresta',en='Forest green',hex='#245C43',r=36,g=92,b=67},
    {id='teal',pt='Azul petróleo',en='Deep teal',hex='#176878',r=23,g=104,b=120},
    {id='blue',pt='Azul profundo',en='Deep blue',hex='#304F8A',r=48,g=79,b=138},
    {id='violet',pt='Ameixa',en='Plum',hex='#693B76',r=105,g=59,b=118},
    {id='sepia',pt='Sépia',en='Sepia',hex='#76543A',r=118,g=84,b=58},
    {id='black',pt='Preto',en='Black',hex='#000000',r=0,g=0,b=0},
}
local index={}
for i,item in ipairs(entries) do index[item.id]=i end
function M.list() return entries end
function M.normalize(id)
    if type(id)=='string' and index[id] then return id end
    return 'original'
end
function M.next(id,direction)
    local current=index[M.normalize(id)] or 1
    return entries[(current-1+(direction or 1))%#entries+1].id
end
function M.get(id)
    return entries[index[M.normalize(id)]]
end
function M.css(id,enabled)
    if not enabled then return nil end
    local item=M.get(id)
    return item and item.hex or nil
end
return M
