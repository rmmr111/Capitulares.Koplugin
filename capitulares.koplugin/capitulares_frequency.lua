-- Capitulares v1.0 / Teste 7
-- Frequencia por paragrafo ou estimativa por pagina refluivel.
-- A CSS nao permite escolher diretamente o paragrafo na pagina N.
local M={}
function M.estimate(document)
    if not document or type(document.getPageXPointer)~='function'
        or type(document.getTextFromXPointers)~='function' then return 3 end
    local ok,result=pcall(function()
        local count=document:getPageCount()
        if type(count)~='number' or count<3 then return 3 end
        local total,seen=0,0
        for _,ratio in ipairs({0.25,0.55,0.80}) do
            local page=math.max(1,math.min(count-1,math.floor(count*ratio)))
            local a,b=document:getPageXPointer(page),document:getPageXPointer(page+1)
            if a and b then
                local txt=document:getTextFromXPointers(a,b)
                if type(txt)=='string' and #txt>0 and #txt<60000 then
                    local _,n=txt:gsub('\n','')
                    total=total+math.max(1,math.min(12,n+1));seen=seen+1
                end
            end
        end
        if seen==0 then return 3 end
        return math.max(1,math.min(12,math.floor(total/seen+0.5)))
    end)
    if ok and type(result)=='number' then return result end
    return 3
end
-- Pure function for validation and for CSS generation.
function M.interval(mode,quantity,paragraphs_per_page)
    local n=tonumber(quantity) or 1
    n=math.floor(n+0.5)
    n=math.max(1,math.min(n,10000))
    if mode=='screens' or mode=='pages' then
        local pp=tonumber(paragraphs_per_page) or 3
        pp=math.max(1,math.min(12,math.floor(pp+0.5)))
        return math.max(1,math.min(120000,n*pp))
    end
    return n
end
return M
