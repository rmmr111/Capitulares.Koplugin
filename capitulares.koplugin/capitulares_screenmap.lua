-- Capitulares v1.0: XPointers com parágrafos e spans aninhados
-- Distancias entre capitulares adicionais contadas desde o inicio de CADA
-- capitulo (XPointers/DocFragments), nao desde a pagina 1 do livro.
-- Nao usar first-letter ja renderizado na construcao de novos intervalos:
-- pode pertencer a configuracao ANTERIOR e esconder todos os alvos novos.
-- Um unico ApplyStyleSheet por alteracao explicita; plano guardado por EPUB.
-- O texto e refluivel: frequencia absolutamente exata nao e garantida.
local UIManager=require('ui/uimanager')
local M={}
local dialogue=require('capitulares_dialogue')
local CACHE_KEY='capitulares_v1_screenmap_v29'
local function intervalFor(plugin)
    return math.max(1,math.floor(tonumber(plugin:extraValue('extra_interval')) or 1))
end
local function safePlan(plan)
    if type(plan)~='table' or #plan>1800 then return nil end
    local cleaned={}
    for _,item in ipairs(plan) do
        if type(item)~='table' or type(item.selector)~='string' or
           not item.selector:match('^DocFragment:nth%-of%-type%(%d+%) > body') or
           #item.selector>240 or type(item.page)~='number' then
            return nil
        end
        local alt=type(item.id_selector)=='string' and #item.id_selector<240
            and item.id_selector or nil
        cleaned[#cleaned+1]={page=item.page,selector=item.selector,
            id_selector=alt,xp=type(item.xp)=='string' and item.xp or nil,
            blocked=item.blocked==true}
    end
    return cleaned
end
function M.restore(plugin)
    if not plugin:screenMode() then return false end
    local saved=plugin.ui.doc_settings:readSetting(CACHE_KEY)
    if type(saved)~='table' or saved.revision~=29 or saved.interval~=intervalFor(plugin) then
        return false
    end
    local plan=safePlan(saved.plan)
    if not plan then return false end
    plugin._ci_screen_plan=plan
    plugin._ci_screen_status=string.format('%d adicionais guardadas (sem novo recarregamento)',#plan)
    return true
end
local function store(plugin,plan)
    local safe=safePlan(plan)
    if not safe then return false end
    plugin.ui.doc_settings:saveSetting(CACHE_KEY,{
        revision=29,interval=intervalFor(plugin),plan=safe,
    })
    return true
end
local function get(doc,key,...)
    if not doc or type(doc[key])~='function' then return nil end
    local ok,result=pcall(doc[key],doc,...)
    if ok then return result end
    return nil
end
local function parse(xp)
    if type(xp)~='string' then return nil end
    local frag=xp:match('/DocFragment%[(%d+)%]')
    local base=xp:match('^(.-/DocFragment%[%d+%]/body)')
    if not frag or not base then return nil end
    local segments={}
    for item in xp:sub(#base+2):gmatch('[^/]+') do
        if item:match('^text%(') then break end
        local tag,index=item:match('^([%a][%w_-]*)%[(%d+)%]$')
        if not tag then tag=item:match('^([%a][%w_-]*)$');index='1' end
        if not tag then return nil end
        segments[#segments+1]={tag=tag,index=tonumber(index)}
    end
    local leaf=segments[#segments]
    return {fragment=tonumber(frag),base=base,segments=segments,
        offset=tonumber(xp:match('%.(%d+)$')) or 0,
        first_text=not xp:match('/text%(%)[[]([2-9]%d*)[]]'),
        chapter=leaf and leaf.tag:match('^h[1-6]$')~=nil,
        heading_tag=leaf and leaf.tag or nil}
end
-- As paginas podem apontar para /p/span/text().N, nunca para /p/text().N.
-- A deteção inicial assumia texto direto e ignorava muitos parágrafos deste
-- EPUB (mais de 700 paginas). Os XPointers sao usados somente em memoria.
local function pNodeKey(info,at)
    if not info or not at then return nil end
    local keys={tostring(info.fragment)}
    for i=1,at do
        local part=info.segments[i]
        keys[#keys+1]=part.tag..'['..tostring(part.index)..']'
    end
    return table.concat(keys,'/')
end
local function findP(info)
    if not info then return nil end
    for i=#info.segments,1,-1 do
        if info.segments[i].tag=='p' then return i end
    end
end
local function firstXPointer(doc,stem,inline_suffix)
    -- Tentar primeiramente o percurso inline REAL observado na pagina.
    -- Para paragrafos seguintes, aproveitar o mesmo tipo de estrutura.
    local tries={}
    local seen={}
    local function add(xp)
        if xp and not seen[xp] then tries[#tries+1]=xp;seen[xp]=true end
    end
    local suffixes={inline_suffix,'', '/span', '/span[1]',
        '/em','/em[1]','/strong','/strong[1]','/i','/i[1]',
        '/b','/b[1]','/a','/a[1]', '/span[1]/span[1]'}
    for _,suffix in ipairs(suffixes) do
        for _,node in ipairs({'/text().0','/text()[1].0'}) do
            add(stem..suffix..node)
        end
    end
    -- Os ponteiros sem texto também são válidos em algumas versões do CREngine.
    -- Só se usam após tentar as formas textuais, e sempre validados.
    add(stem)
    for _,xp in ipairs(tries) do
        local valid=get(doc,'isXPointerInDocument',xp)
        if valid and valid~=0 then
            local page=tonumber(get(doc,'getPageFromXPointer',xp))
            if page then return xp,page end
        end
    end
    return nil,nil
end
local function makeItem(info,parts,page,xp)
    local selector={'DocFragment:nth-of-type('..info.fragment..')','body'}
    local id_selector={'DocFragment#_doc_fragment_'..(info.fragment-1),'body'}
    for _,part in ipairs(parts) do
        local item=part.tag..':nth-of-type('..part.index..')'
        selector[#selector+1]=item
        id_selector[#id_selector+1]=item
    end
    return {page=page,xp=xp,selector=table.concat(selector,' > '),
        id_selector=table.concat(id_selector,' > ')}
end
-- Alguns EPUBs representam titulos como <p class="capitulo"> em vez de h1.
-- So consultar HTML estrutural nas paginas de inicio de capitulo; o conteudo
-- nunca e guardado nem exportado. O seletor correspondente ja existe no CSS.
local function isChapterTitleParagraph(doc,stem)
    local html=get(doc,'getHTMLFromXPointer',stem)
    if type(html)~='string' then return false end
    local attrs=html:lower():match('^%s*<p%s+([^>]*)>')
    if not attrs then return false end
    local classes=attrs:match('class%s*=%s*"([^"]*)"') or
        attrs:match("class%s*=%s*'([^']*)'")
    return classes~=nil and
        (classes:find('chapter',1,true)~=nil or
         classes:find('capitulo',1,true)~=nil or
         classes:find('chapitre',1,true)~=nil)
end
function M.choose(doc,page,skip_title)
    local initial=get(doc,'getPageXPointer',page)
    local info=parse(initial)
    if not info then return nil end
    local parts={}
    for i,seg in ipairs(info.segments) do
        parts[i]={tag=seg.tag,index=seg.index}
    end
    local index=findP(info)
    local inline_suffix=nil
    local blocked={}
    if index then
        local suffix={}
        for i=index+1,#parts do
            suffix[#suffix+1]='/'..parts[i].tag..'['..parts[i].index..']'
        end
        inline_suffix=table.concat(suffix)
        -- Uma pagina iniciada num span nao implica que o seu paragrafo
        -- esteja a meio: pode ser o primeiro texto da primeira linha.
        -- Verificar onde começa verdadeiramente o paragrafo.
        while #parts>index do parts[#parts]=nil end
        local stem=info.base
        for _,part in ipairs(parts) do
            stem=stem..'/'..part.tag..'['..part.index..']'
        end
        local _,first_page=firstXPointer(doc,stem,inline_suffix)
        local previous=parse(get(doc,'getPageXPointer',page-1))
        local previous_same=pNodeKey(previous,findP(previous))==pNodeKey(info,index)
        local is_continuation=(first_page and first_page<page) or
            (info.offset>0) or (not info.first_text) or previous_same
        if is_continuation then parts[index].index=parts[index].index+1 end
    else
        local leaf=parts[#parts]
        if leaf and (leaf.tag:match('^h[1-6]$') or leaf.tag=='header') then
            -- h1 e p sao normalmente IRMAOS, nao p dentro de h1.
            parts[#parts]={tag='p',index=1}
        elseif #parts==0 then
            parts[1]={tag='p',index=1}
        else
            return nil
        end
    end
    for _=1,12 do
        local stem=info.base
        for _,part in ipairs(parts) do
            stem=stem..'/'..part.tag..'['..part.index..']'
        end
        local xp,actual=firstXPointer(doc,stem,inline_suffix)
        if actual==page then
            local item=makeItem(info,parts,page,xp)
            if skip_title and isChapterTitleParagraph(doc,stem) then
                -- Titulo em p: tentar o primeiro p de prosa a seguir.
            elseif dialogue.isDialogue(doc,stem,xp) then
                -- Nao deslocar o travessao nem produzir uma capitular gigante.
                -- A pagina pode ainda ter um paragrafo narrativo elegivel.
                item.blocked=true
                blocked[#blocked+1]=item
            else
                return item,blocked
            end
        end
        if actual and actual>page then break end
        parts[#parts].index=parts[#parts].index+1
    end
    return nil,blocked
end
-- Lê o HTML de um único ecrã na paginação de referência (só capítulos).
-- Se já houver uma capitular visível, não acrescentar outra à mesma página.
-- Falha conservadora: quando o motor não disponibiliza HTML, preservamos
-- a deteção normal de capítulos e evitamos apenas os inícios de cabeçalho.
function M.hasInitial(doc,page)
    local a=get(doc,'getPageXPointer',page)
    local b=get(doc,'getPageXPointer',page+1)
    if not a or not b then return false end
    local html=get(doc,'getHTMLFromXPointers',a,b,0,false)
    if type(html)~='string' then return false end
    return html:find('<pseudoElem FirstLetter',1,true)~=nil or
        html:find('<pseudoelem firstletter',1,true)~=nil
end
-- Only look for structural headings: not pseudoElem/HasFirstLetter.
-- The latter are based on CSS that may still be active from interval 1.
function M.pageHasChapterHeading(doc,page)
    local a=get(doc,'getPageXPointer',page)
    local b=get(doc,'getPageXPointer',page+1)
    if not a or not b then return false end
    local current=parse(a)
    -- A pagina que COMECA pelo titulo pertence ao inicio de capitulo.
    if current and current.chapter then return true end
    local following=parse(b)
    -- CREngine getHTMLFromXPointers(a,b) pode incluir o h1 situado
    -- EXATAMENTE no limite b: o primeiro titulo da pagina seguinte.
    -- Nao o interpretar como um titulo visivel na ultima pagina atual.
    -- Quando a pagina seguinte inicia um novo titulo, o HTML pode inclui-lo;
    -- a extracao HTML da 12 inclui esse h1 fora do seu ecra.
    if following and following.chapter and following.heading_tag=='h1' then return false end
    local html=get(doc,'getHTMLFromXPointers',a,b,0,false)
    if type(html)~='string' then return false end
    return html:find('<h[1-6][%s>]',1)~=nil or
        html:find('<H[1-6][%s>]',1)~=nil
end
function M.isChapterStart(info,previous_fragment)
    if not info then return false end
    if previous_fragment==nil or info.fragment~=previous_fragment then return true end
    return info.chapter and info.heading_tag=='h1' or false
end
-- The final physical screen of a chapter does not necessarily land on an
-- interval mark. Make it eligible independently, but never decorate a
-- continuation or an empty page just to force an initial.
function M.isChapterLastPage(doc,page,count,info)
    if not info then return false end
    if page==count then return true end
    local following=parse(get(doc,'getPageXPointer',page+1))
    if not following then return false end
    return following.fragment~=info.fragment or
        (following.chapter and following.heading_tag=='h1') or false
end
function M.signature(plugin)
    local doc=plugin.ui and plugin.ui.document
    local cfg=doc and doc.configurable or {}
    local vals={tostring(plugin:baseFontPx()),tostring(plugin:currentLeading()),
        tostring(get(doc,'getVisiblePageCount') or 1)}
    for _,key in ipairs({'font_size','font_face','font_weight','line_spacing',
        'h_page_margins','t_page_margin','b_page_margin','word_spacing',
        'render_dpi','embedded_css','embedded_fonts'}) do
        vals[#vals+1]=tostring(cfg[key])
    end
    local margins=get(doc,'getPageMargins') or {}
    for _,k in ipairs({'left','right','top','bottom'}) do
        vals[#vals+1]=tostring(margins[k])
    end
    return table.concat(vals,'|')
end
function M.cancel(plugin,keep_cache)
    plugin._ci_screen_generation=(plugin._ci_screen_generation or 0)+1
    plugin._ci_screen_busy=nil
    plugin._ci_screen_plan=nil
    if not keep_cache and plugin.ui and plugin.ui.doc_settings then
        plugin.ui.doc_settings:delSetting(CACHE_KEY)
    end
end
-- Apply only ONCE, at the end of scanning. The previous implementation
-- applied a baseline, then a map, sometimes then a correction. On KOReader
-- this marks the built DOM stale and produces repeated reload confirmations.
function M.request(plugin)
    if not plugin:enabledForBook() or not plugin:screenMode() or plugin._ci_screen_busy then return end
    local doc=plugin.ui and plugin.ui.document
    if not doc or type(doc.getPageXPointer)~='function' or
        type(doc.getPageFromXPointer)~='function' then
        plugin._ci_screen_status='API de paginação indisponível: capítulos preservados'
        return
    end
    plugin._ci_screen_generation=(plugin._ci_screen_generation or 0)+1
    local epoch=plugin._ci_screen_generation
    local interval=intervalFor(plugin)
    plugin._ci_screen_busy=true
    plugin._ci_screen_status='A calcular sem alterar estilos intermédios'
    local selected,seen,missing,decorated,skipped_dialogue={}, {}, 0,0,0
    local page,count=1,nil
    local chapter_page,previous_fragment=nil,nil
    local function alive()
        return plugin._ci_screen_generation==epoch and
            plugin.ui and plugin.ui.document==doc and plugin:screenMode() and
            plugin:enabledForBook()
    end
    local function finish()
        if not alive() then return end
        local old_plan=plugin._ci_screen_plan
        plugin._ci_screen_plan=selected
        -- Save BEFORE applying the stylesheet. If the CREngine subsequently
        -- requires a full reload, the next Reader instance restores the map
        -- before the initial render, instead of starting another scan.
        if not store(plugin,selected) then
            plugin._ci_screen_plan=old_plan
            plugin._ci_screen_busy=nil
            plugin._ci_screen_status='Falhou a gravação do mapa; estilos mantidos'
            return
        end
        local applied,reason=pcall(function()plugin:refresh()end)
        if not applied then
            plugin._ci_screen_plan=old_plan
            plugin.ui.doc_settings:delSetting(CACHE_KEY)
            plugin._ci_screen_status='Falhou a aplicação: '..tostring(reason)
            plugin._ci_screen_busy=nil
            return
        end
        plugin._ci_screen_signature=M.signature(plugin)
        plugin._ci_screen_status=string.format('Intervalo %d + fecho de capítulo: %d adicionais; %d sem alvo',
            interval,decorated,missing)
        plugin._ci_screen_busy=nil
        -- No follow-up CSS correction. It would restart the stale DOM cycle.
    end
    local function step()
        if not alive() then return end
        if not count then
            count=tonumber(get(doc,'getPageCount'))
            if not count or count<1 or count>900 then
                plugin._ci_screen_busy=nil
                plugin._ci_screen_plan=nil
                plugin._ci_screen_status='Livro fora do limite: capítulos preservados'
                -- Empty cached plan avoids another automatic scan after reload.
                store(plugin,{})
                return
            end
        end
        local stop=math.min(count,page+23)
        for p=page,stop do
            local xp=get(doc,'getPageXPointer',p)
            local info=parse(xp)
            if info then
                -- Primeiro ecrã do EPUB ou primeiro ecrã de um novo capítulo:
                -- a capitular estrutural está sempre a distância zero.
                local starts_chapter=M.isChapterStart(info,previous_fragment)
                if starts_chapter then
                    chapter_page=p
                end
                previous_fragment=info.fragment
                -- Ex.: capítulo no ecrã 3, intervalo 2 => adicionais 5,7,9...
                -- No capítulo seguinte, o contador é reiniciado.
                local due=chapter_page and p>chapter_page and
                    (p-chapter_page)%interval==0
                local last=chapter_page and p>chapter_page and
                    M.isChapterLastPage(doc,p,count,info)
                -- Na pagina final, nao deixar que o h1 da PAGINA SEGUINTE
                -- contamine a decisao sobre o primeiro paragrafo atual.
                local target=(due or last) and not info.chapter and
                    not M.pageHasChapterHeading(doc,p)
                -- Incluir as paginas de inicio de capitulo na inspecao:
                -- uma regra estrutural h1+p pode atingir um dialogo.
                if target or starts_chapter then
                    local item,blocked=M.choose(doc,p,starts_chapter)
                    -- Nas paginas adicionais os dialogos nao receberam CSS,
                    -- por isso so e preciso neutralizar seletores de dialogo
                    -- quando as regras normais de capitulo os atingiriam.
                    for _,excluded in ipairs(starts_chapter and blocked or {}) do
                        if not seen[excluded.selector] then
                            seen[excluded.selector]=true
                            selected[#selected+1]=excluded
                            skipped_dialogue=skipped_dialogue+1
                        end
                    end
                    -- Nos capitulos preservar a capitular estrutural normal.
                    -- Nas paginas adicionais escolher o primeiro p narrativo.
                    if target then
                        if item and not seen[item.selector] then
                            seen[item.selector]=true
                            selected[#selected+1]=item
                            decorated=decorated+1
                        else
                            missing=missing+1
                        end
                    end
                end
            end
        end
        page=stop+1
        if page<=count then UIManager:nextTick(step) else finish() end
    end
    UIManager:nextTick(step)
end
return M
