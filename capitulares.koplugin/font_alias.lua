-- Cria uma COPIA de uma fonte SFNT (.ttf/.otf) com as iniciais PT
-- mapeadas para os glifos A-Z; o EPUB original permanece intacto.
-- As fontes convertidas destinam-se APENAS a capitulares.
local M = {}
local function u16(s,p) local a,b=s:byte(p,p+1); if not b then error('Ficheiro truncado') end; return a*256+b end
local function u32(s,p) return u16(s,p)*65536+u16(s,p+2) end
local function w16(n) n=n%65536; return string.char(math.floor(n/256),n%256) end
local function w32(n) n=n%4294967296; return w16(math.floor(n/65536))..w16(n) end
local function align(n) return (n+3)-((n+3)%4) end
local function padded(s) return s..string.rep('\0',align(#s)-#s) end
local function checksum(s) local z=padded(s); local sum=0; for p=1,#z,4 do sum=(sum+u32(z,p))%4294967296 end; return sum end
local function map4(s,base,cp)
    local n=u16(s,base+6)/2
    local endings=base+14
    local starts=endings+2*n+2
    local deltas=starts+2*n
    local ranges=deltas+2*n
    for i=0,n-1 do
        if cp<=u16(s,endings+2*i) then
            if cp<u16(s,starts+2*i) then return nil end
            local delta=u16(s,deltas+2*i)
            local off=u16(s,ranges+2*i)
            if off==0 then return (cp+delta)%65536 end
            local glyph=u16(s,ranges+2*i+off+2*(cp-u16(s,starts+2*i)))
            return glyph~=0 and (glyph+delta)%65536 or nil
        end
    end
end
local function map12(s,base,cp)
    local n=u32(s,base+12)
    for i=0,n-1 do
        local p=base+16+i*12
        local a,b,g=u32(s,p),u32(s,p+4),u32(s,p+8)
        if cp>=a and cp<=b then return g+cp-a end
        if cp<a then break end
    end
end
local function readGlyph(s,tab,cp)
    local n=u16(s,tab+2)
    local records={}
    for i=0,n-1 do
        local p=tab+4+i*8
        local platform,enc,off=u16(s,p),u16(s,p+2),u32(s,p+4)
        local pos=tab+off
        local fmt=u16(s,pos)
        if (fmt==4 or fmt==12) and (platform==3 or platform==0) then
            records[#records+1]={p=pos,fmt=fmt,prio=(platform==3 and enc==10) and 3 or (platform==3 and enc==1) and 2 or 1}
        end
    end
    table.sort(records,function(a,b) return a.prio>b.prio end)
    for _,r in ipairs(records) do
        local gid
        if r.fmt==12 then gid=map12(s,r.p,cp)
        else gid=map4(s,r.p,cp) end
        if gid and gid~=0 then return gid end
    end
end
-- Todas as maiusculas e minusculas PT mais comuns; o desenho e sempre da maiuscula.
local letters={
    A='ÀÁÂÃÄÅàáâãäå', E='ÈÉÊËèéêë', I='ÌÍÎÏìíîï',
    O='ÒÓÔÕÖòóôõö', U='ÙÚÛÜùúûü', C='Çç', N='Ññ', Y='ÝŸýÿ',
}
local function codepoints(s)
    local r={}
    local i=1
    while i<=#s do
        local a=s:byte(i)
        if a<128 then r[#r+1]=a;i=i+1
        elseif a>=194 and a<=223 then
            local b=s:byte(i+1);if not b then break end
            r[#r+1]=(a-192)*64+b-128;i=i+2
        elseif a>=224 and a<=239 then
            local b,c=s:byte(i+1,i+2);if not c then break end
            r[#r+1]=(a-224)*4096+(b-128)*64+c-128;i=i+3
        else i=i+1 end
    end
    return r
end
-- Preserva todos os glifos Unicode existentes. Uma copia anterior substituia
-- a tabela cmap por apenas A-Z, perdendo simbolos e caracteres proprios.
local function collectGlyphs(s, cmapPos)
    local n=u16(s,cmapPos+2)
    local recs,seen={},{}
    for i=0,n-1 do
        local p=cmapPos+4+i*8
        local platform,encoding,off=u16(s,p),u16(s,p+2),u32(s,p+4)
        local pos=cmapPos+off
        if pos<=#s-15 and not seen[pos] and (platform==0 or platform==3) then
            local fmt=u16(s,pos)
            if fmt==4 or fmt==12 then
                seen[pos]=true
                recs[#recs+1]={pos=pos,fmt=fmt,prio=(platform==3 and encoding==10) and 3 or (platform==3 and encoding==1) and 2 or 1}
            end
        end
    end
    -- Do menos preferido para o mais preferido: o mapeamento de Windows
    -- permanece prioritario, tal como na leitura anterior.
    table.sort(recs,function(a,b)return a.prio<b.prio end)
    local glyphs={}
    for _,r in ipairs(recs) do
        if r.fmt==4 then
            local count=u16(s,r.pos+6)/2
            local ends=r.pos+14
            local starts=ends+2*count+2
            for i=0,count-1 do
                local first,last=u16(s,starts+i*2),u16(s,ends+i*2)
                if first<=last then
                    for cp=first,math.min(last,65534) do
                        local gid=map4(s,r.pos,cp)
                        if gid and gid~=0 then glyphs[cp]=gid end
                    end
                end
            end
        else
            local count=u32(s,r.pos+12)
            if count>10000 then error('cmap12 demasiado grande') end
            for i=0,count-1 do
                local pos=r.pos+16+i*12
                local first,last,gid=u32(s,pos),u32(s,pos+4),u32(s,pos+8)
                if last<first or last-first>80000 then error('Intervalo cmap12 inesperado') end
                for cp=first,last do
                    if cp<=0x10ffff and gid+cp-first~=0 then glyphs[cp]=gid+cp-first end
                end
            end
        end
    end
    if not next(glyphs) then error('Fonte sem cmap Unicode adequado') end
    return glyphs
end
local function buildCmap(glyphs)
    local cps,bmp={},{}
    for cp in pairs(glyphs) do
        cps[#cps+1]=cp
        if cp<65535 then bmp[#bmp+1]=cp end
    end
    table.sort(cps);table.sort(bmp)
    -- O formato 4 usa offsets de 16 bits. Limitar a transformacao a
    -- fontes ornamentais pequenas em vez de criar tabelas corruptas.
    local segs=#bmp+1
    if segs>6200 then error('cmap demasiado extensa para conversao segura') end
    local p2,entry=1,0
    while p2*2<=segs do p2=p2*2;entry=entry+1 end
    local f4={w16(4),w16(16+8*segs),w16(0),w16(segs*2),w16(p2*2),w16(entry),w16(segs*2-p2*2)}
    for _,cp in ipairs(bmp) do f4[#f4+1]=w16(cp) end
    f4[#f4+1]=w16(65535);f4[#f4+1]=w16(0)
    for _,cp in ipairs(bmp) do f4[#f4+1]=w16(cp) end
    f4[#f4+1]=w16(65535)
    for _,cp in ipairs(bmp) do f4[#f4+1]=w16(glyphs[cp]-cp) end
    f4[#f4+1]=w16(1)
    for _=1,segs do f4[#f4+1]=w16(0) end
    f4=table.concat(f4)
    local f12={w16(12),w16(0),w32(16+12*#cps),w32(0),w32(#cps)}
    for _,cp in ipairs(cps) do f12[#f12+1]=w32(cp)..w32(cp)..w32(glyphs[cp]) end
    f12=table.concat(f12)
    return w16(0)..w16(2)..w16(3)..w16(1)..w32(20)..w16(3)..w16(10)..w32(20+#f4)..f4..f12
end
-- Detecta apenas acentos que faltam E cuja letra-base existe.
local function missingGlyphAliases(s,cmapPos)
    local absent={}
    for letter,chars in pairs(letters) do
        local base=readGlyph(s,cmapPos,letter:byte())
        if base and base~=0 then
            for _,cp in ipairs(codepoints(chars)) do
                if not readGlyph(s,cmapPos,cp) then absent[cp]=base end
            end
        end
    end
    return absent
end
function M.needsNormalization(path)
    if type(path)~='string' then return nil,'Caminho invalido' end
    local f=io.open(path,'rb');if not f then return nil,'Fonte nao encontrada' end
    local data=f:read('*a');f:close()
    local ok,missing=pcall(function()
        local n=u16(data,5)
        for i=0,n-1 do
            local p=13+i*16
            if data:sub(p,p+3)=='cmap' then
                return missingGlyphAliases(data,u32(data,p+8)+1)
            end
        end
        error('Sem cmap')
    end)
    if not ok then return nil,tostring(missing) end
    return next(missing)~=nil
end
local function asciiUTF16(s) return (s:gsub('.',function(c) return '\0'..c end)) end
local function buildName(s,base,name)
    local count=u16(s,base+2)
    local stringOffset=u16(s,base+4)
    local records,strings={},{}
    local cursor=0
    for i=0,count-1 do
        local p=base+6+i*12
        local plat,encoding,language,id=u16(s,p),u16(s,p+2),u16(s,p+4),u16(s,p+6)
        local length,offset=u16(s,p+8),u16(s,p+10)
        local val=s:sub(base+stringOffset+offset,base+stringOffset+offset+length-1)
        if id==1 or id==4 or id==6 or id==16 then
            local selected=(id==6) and name:gsub(' ','') or name
            val=plat==3 and asciiUTF16(selected) or selected
        end
        records[#records+1]=w16(plat)..w16(encoding)..w16(language)..w16(id)..w16(#val)..w16(cursor)
        strings[#strings+1]=val;cursor=cursor+#val
    end
    return w16(0)..w16(count)..w16(6+12*count)..table.concat(records)..table.concat(strings)
end
function M.coverage(path, sample)
    local f=io.open(path,'rb');if not f then return nil end
    local data=f:read('*a');f:close()
    local ok,res=pcall(function()
        local n=u16(data,5)
        local cmapPos
        for i=0,n-1 do
            local p=13+i*16
            if data:sub(p,p+3)=='cmap' then cmapPos=u32(data,p+8)+1;break end
        end
        if not cmapPos then error('Sem cmap') end
        local absent={}
        for _,cp in ipairs(codepoints(sample)) do
            if cp~=32 and not readGlyph(data,cmapPos,cp) then
                absent[#absent+1]=cp
            end
        end
        return absent
    end)
    if ok then return res end
    return nil
end
function M.normalizeFile(path,target,uniqueName)
    if not path or not path:lower():match('%.otf$') and not path:lower():match('%.ttf$') then
        return false,'Apenas TTF ou OTF.'
    end
    local f=io.open(path,'rb');if not f then return false,'Nao foi possivel abrir a fonte.' end
    local data=f:read('*a');f:close()
    local ok,err=pcall(function()
        if #data>20*1024*1024 then error('Fonte demasiado grande (>20 MB).') end
        local signature=data:sub(1,4)
        if signature~='OTTO' and signature~='\0\1\0\0' then error('Formato SFNT nao suportado.') end
        local n=u16(data,5)
        if n<1 or n>100 then error('Cabecalho invalido') end
        local tableEntries={}
        local byTag={}
        for i=0,n-1 do
            local p=13+16*i;local tag=data:sub(p,p+3)
            local offset=u32(data,p+8);local len=u32(data,p+12)
            if offset+len>#data then error('Tabela invalida: '..tag) end
            local e={tag=tag,bytes=data:sub(offset+1,offset+len)}
            tableEntries[#tableEntries+1]=e;byTag[tag]=e
        end
        if not byTag.cmap or not byTag.name or not byTag.head then error('Fonte sem cmap/name/head') end
        local cmapPos
        for i=0,n-1 do local p=13+16*i;if data:sub(p,p+3)=='cmap' then cmapPos=u32(data,p+8)+1 end end
        local glyphs=collectGlyphs(data,cmapPos)
        local missing=missingGlyphAliases(data,cmapPos)
        if not next(missing) then error('Esta fonte ja suporta os acentos disponiveis.') end
        for cp,gid in pairs(missing) do glyphs[cp]=gid end
        byTag.cmap.bytes=buildCmap(glyphs)
        local nmPos
        for i=0,n-1 do local p=13+16*i;if data:sub(p,p+3)=='name' then nmPos=u32(data,p+8)+1 end end
        byTag.name.bytes=buildName(data,nmPos,uniqueName)
        byTag.head.bytes=byTag.head.bytes:sub(1,8)..w32(0)..byTag.head.bytes:sub(13)
        local power=1;local selector=0;while power*2<=n do power=power*2;selector=selector+1 end
        local header=signature..w16(n)..w16(power*16)..w16(selector)..w16(n*16-power*16)
        local offsets=#header+16*n
        local directory,blocks={},{}
        local headOffset
        for _,e in ipairs(tableEntries) do
            local bytes=e.bytes
            directory[#directory+1]=e.tag..w32(checksum(bytes))..w32(offsets)..w32(#bytes)
            blocks[#blocks+1]=padded(bytes)
            if e.tag=='head' then headOffset=offsets+1 end
            offsets=offsets+align(#bytes)
        end
        local output=header..table.concat(directory)..table.concat(blocks)
        local correction=(0xB1B0AFBA-checksum(output))%4294967296
        output=output:sub(1,headOffset+7)..w32(correction)..output:sub(headOffset+12)
        if checksum(output)~=0xB1B0AFBA then error('Checksum final incorreto') end
        local temp=target..'.tmp'
        local dest=assert(io.open(temp,'wb'))
        assert(dest:write(output),'Falha ao escrever a fonte normalizada')
        assert(dest:close(),'Falha ao fechar o ficheiro')
        assert(os.rename(temp,target),'Falha ao instalar a fonte normalizada')
    end)
    if not ok then os.remove(target..'.tmp');return false,tostring(err) end
    return true
end
return M
