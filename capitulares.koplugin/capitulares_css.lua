-- Capitulares v1.0: stable drop-cap CSS (no ineffective bottom-fit control).
-- Nao altera o EPUB nem o tamanho normal do livro.
local frequency=require('capitulares_frequency')
local colors=require('capitulares_colors')
local M={}
M.defaults={
    font='',style='decorativa',detection='capitulos',
    size=3.50,gap=0.12,top=-0.05,box=0.82,vertical_shift=0,
    override=false,lines=3, -- chaves antigas conservadas para preferencias existentes
    extra_enabled=false,extra_mode='paragraphs',extra_interval=1,
}
local D=M.defaults
local function bounded(v,default,lo,hi)
    v=tonumber(v)
    if not v or v~=v or v==math.huge or v==-math.huge then return default end
    return math.max(lo,math.min(hi,v))
end
local function quoteFont(face)
    if type(face)~='string' or face=='' then return 'inherit' end
    face=face:gsub('\\','\\\\'):gsub('"','\\"'):gsub('[%c]',' ')
    return '"'..face..'", serif'
end
local wrappers={'body','body > section','body > article','body > div','body > section > div','body > div > div'}
local headings={'h1','h2','h3','h4','h5','h6'}
local function build(detection,extra_enabled,every)
    local selectors,seen={},{ }
    local function add(s)
        if not seen[s] then seen[s]=true;selectors[#selectors+1]=s end
    end
    for _,wrap in ipairs(wrappers) do
        for _,h in ipairs(headings) do
            add(wrap..' > '..h..' + p')
            add(wrap..' > '..h..' + div > p:first-child')
            add(wrap..' > '..h..' + section > p:first-child')
        end
        add(wrap..' > header + p')
        add(wrap..' > header + div > p:first-child')
    end
    -- Alguns EPUBs têm títulos codificados como <p class="capitulo">,
    -- seguidos por outro <p> de titulo e só depois o primeiro paragrafo.
    -- Não exigir h1/h2 nem limitar a 2 níveis de div: a condição apenas
    -- decorará o primeiro parágrafo não marcado como título do capítulo.
    for _,marker in ipairs({'chapter','capitulo','chapitre'}) do
        add('p[class*="'..marker..'"] + p:not([class*="'..marker..'"])')
    end
    if detection=='seccoes' or detection=='alargada' then
        for _,wrap in ipairs(wrappers) do
            add(wrap..' > p:first-of-type')
            add(wrap..' > div:first-child > p:first-of-type')
            add(wrap..' > section:first-child > p:first-of-type')
            add(wrap..' > hr + p')
            add(wrap..' > [class*="pagebreak"] + p')
            add(wrap..' > [class*="page-break"] + p')
            add(wrap..' > [style*="page-break-after"] + p')
            add(wrap..' > p[style*="page-break-before"]')
        end
    end
    if detection=='alargada' then
        add('body > p:first-of-type')
        add('body > div:first-child p:first-of-type')
        add('body > section:first-child p:first-of-type')
    end
    if extra_enabled then
        -- Conta elementos p por contentor HTML, NAO todos os paragrafos de um
        -- livro, nem detecta paginas exatas; titulos em p podem afetar a contagem.
        for _,wrap in ipairs(wrappers) do
            add(wrap..' > p:nth-of-type('..tostring(every)..'n)')
        end
    end
    return selectors
end
-- Limite unico utilizado pelo CSS e pelo slider; evita uma zona morta no
-- extremo direito do controlo. Nao e uma medicao exata da inicial do EPUB:
-- ::first-letter nao disponibiliza a identidade nem a bounding box do glifo.
function M.sizeLimits(opts)
    opts=opts or D
    local profile=opts.font_metrics or {}
    local leading=bounded(opts.leading,1.20,1.0,2.3)
    local ink_h=bounded(profile.height,0.88,0.42,2.2)
    local ink_w=bounded(profile.width,0.88,0.30,2.2)
    local font_px=bounded(opts.base_font_px,32,12,255)
    local guard=math.max(0.018,math.min(0.055,2/font_px))
    local gap=bounded(opts.gap,D.gap,0,0.8)
    local shift=bounded(opts.vertical_shift,0,-0.65,0.65)
    local xshift=bounded(opts.offset_x,0,-0.40,0.40)
    -- A folga horizontal e o deslocamento vertical consomem parte do espaco.
    -- O limite de 8 linhas e a largura conservadora da geometria T7 mantem-se.
    local height_budget=8*leading-guard-math.max(0,shift)
    local width_budget=7.0-gap-math.abs(xshift)
    local safe=math.min(8.5,height_budget/ink_h,width_budget/ink_w)
    safe=math.max(1.5,safe)
    return {minimum=1.5,maximum=safe,guard=guard,leading=leading,
        ink_h=ink_h,ink_w=ink_w}
end
function M.geometry(opts)
    opts=opts or D
    local profile=opts.font_metrics or {}
    local lim=M.sizeLimits(opts)
    local leading,ink_h=lim.leading,lim.ink_h
    local desired=bounded(opts.size,D.size,lim.minimum,8.5)
    local safe=lim.maximum
    local size=math.min(desired,safe)
    local guard=lim.guard
    local ink_height=size*ink_h
    local lines=math.max(1,math.ceil((ink_height+guard-0.00001)/leading))
    local fit=(lines*leading-guard)/ink_h
    -- Crescimento otico conservador: nao ultrapassar o maximo
    -- que o slider apresenta. Mantem o comportamento das fontes ja afinadas.
    local max_growth=profile.measured==true and 1.30 or 1.08
    if fit>size and fit<=size*max_growth and fit<=safe then
        size=fit
        ink_height=size*ink_h
    end
    local box=ink_height+guard
    local line_height=math.max(0.56,math.min(2.25,box/size))
    return {
        size=size,desired=desired,maximum=safe,
        box=box,lines=lines,leading=leading,ink_height=ink_height,
        float_line_height=line_height,guard=guard,
        fitted=size>desired+0.0001,limited=size+0.001<desired,
    }
end
function M.generate(opts)
    opts=opts or D
    local screen_mode=opts.extra_enabled==true and
        (opts.extra_mode=='screens' or opts.extra_mode=='pages')
    -- In screen mode, ONE family of selectors is permitted. Never combine
    -- chapter CSS with unrelated nth-of-type rules on the same page.
    local plan=screen_mode and opts.screen_plan or nil
    local extra=opts.extra_enabled==true and not screen_mode
    local every=extra and frequency.interval('paragraphs',opts.extra_interval,1) or nil
    -- Nunca deixar um livro sem as suas capitulares de capítulo.
    -- A distribuição adicional por ecrãs é uma camada opcional que só se
    -- acrescenta a estes seletores, sem os substituir durante o cálculo.
    local sels=build(opts.detection or D.detection,extra,every)
    local blocked={}
    if screen_mode and type(plan)=='table' then
        local present={}
        for _,sel in ipairs(sels) do present[sel]=true end
        for _,item in ipairs(plan) do
            local dest=item.blocked and blocked or sels
            if type(item.selector)=='string' and #item.selector<240 and
                (item.blocked or not present[item.selector]) then
                if not item.blocked then present[item.selector]=true end
                dest[#dest+1]=item.selector
            end
            -- Identificador sintetico alternativo do CREngine.
            if type(item.id_selector)=='string' and #item.id_selector<240 and
                (item.blocked or not present[item.id_selector]) then
                if not item.blocked then present[item.id_selector]=true end
                dest[#dest+1]=item.id_selector
            end
        end
    end
    if #sels==0 then return '/* Capitulares: sem parágrafos elegíveis */' end
    -- Evitar notas e indices diretamente marcados. A detecao de elementos
    -- aninhados depende das classes reais do EPUB e nao e universal.
    local exclusion=':not([class*="footnote"]):not([class*="endnote"]):not([class*="note"]):not([class*="toc"]):not([class*="index"])'
    local first={}
    for _,sel in ipairs(sels) do first[#first+1]=sel..exclusion..'::first-letter' end
    local important=opts.override and ' !important' or ''
    local mandatory=' !important' -- protect weight/font against book-level rules
    local face=(opts.source_group=='book' or opts.style=='classica') and 'inherit' or quoteFont(opts.font)
    local geo=M.geometry(opts)
    -- A pseudo-letra flutuante nao expoe o contorno do glifo ao CREngine.
    -- Evitar compensacoes inferiores negativas que podem esconder o inicial.
    local bottom_initial=0
    local gap=bounded(opts.gap,D.gap,0,0.8)
    -- Ajuste vertical apenas da capitular; nao altera o entrelinhamento do livro.
    local shift=bounded(opts.vertical_shift,0,-0.65,0.65)
    -- margin-top/right usam 'em' da PROPRIA capitular; converter
    -- a partir dos em do corpo, para que os valores escolhidos nao
    -- fiquem multiplicados pelo fator de ampliacao da capitular.
    local shift_initial=shift/math.max(geo.size,0.001)
    -- Para mover apenas a letra e preservar a largura total do bloco float,
    -- compensar a margem esquerda com a margem direita. Conservador: o CREngine
    -- pode refluír o texto mesmo com margens que se compensam.
    local offset_x=bounded(opts.offset_x,0,-0.40,0.40)
    local offset_initial=offset_x/math.max(geo.size,0.001)
    -- Evitar margin-right negativa: uma deslocacao grande para a direita
    -- deve afastar o texto em vez de o sobrepor.
    local right_initial=math.max(0,gap-offset_x)/math.max(geo.size,0.001)
    M._last_geometry=geo
    -- With default colors, no custom color declaration is emitted.
    -- Never tint the body, headings or subsequent letters.
    local color_rule=colors.css(opts.dropcap_color,opts.color_supported)
    local rules={
        '/* Capitulares v1.0 - dynamic size cap; EPUB intacto */',
        table.concat(sels,',\n')..'{text-indent:0'..important..';}',
        table.concat(first,',\n')..'{',
        'float:left'..important..';',
        'font-family:'..face..mandatory..';',
        string.format('font-size:%.3fem%s;',geo.size,important),
        string.format('line-height:%.4f%s;',geo.float_line_height,important),
        string.format('margin-top:%.4fem%s;',shift_initial,important),
        string.format('margin-left:%.4fem%s;',offset_initial,important),
        string.format('margin-right:%.4fem%s;',right_initial,important),
        string.format('margin-bottom:%.4fem%s;',bottom_initial,important),
        'padding:0;',
        'font-weight:400'..mandatory..';',
        'font-style:normal'..mandatory..';',
        'text-transform:uppercase'..important..';',
        '}',
    }
    if color_rule then
        -- Keep the same CSS selectors: apply color to each first-letter only.
        table.insert(rules,#rules,'color:'..color_rule..mandatory..';')
    end
    -- A regra estrutural de capitulo pode coincidir com um dialogo.
    -- Neutralizar SO nesses paragrafos, mesmo quando selecionados por h1+p.
    -- A regra esta DEPOIS do bloco principal e tem seletor mais especifico.
    if #blocked>0 then
        local blocked_first={}
        for _,sel in ipairs(blocked) do
            blocked_first[#blocked_first+1]=sel..'::first-letter'
        end
        rules[#rules+1]=table.concat(blocked_first,',\n')..'{\n'..
            'float:none !important; font-family:inherit !important; '..
            'font-size:1em !important; line-height:normal !important; '..
            'margin:0 !important; padding:0 !important; '..
            'font-style:inherit !important; font-weight:inherit !important; '..
            'text-transform:none !important; color:inherit !important; }'
    end
    return table.concat(rules,'\n')
end
return M
