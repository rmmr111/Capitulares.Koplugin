-- Capitulares v1.0 — perfis isolados, sem guardar ajustes temporarios
-- Painel KOReader: tema Editorial Premium. Apenas apresentação; mesmas ações do painel único.
-- Nunca toca no EPUB nem nas fontes originais.
local M={}
local UIManager=require('ui/uimanager')
local InputContainer=require('ui/widget/container/inputcontainer')
local VerticalGroup=require('ui/widget/verticalgroup')
local VerticalSpan=require('ui/widget/verticalspan')
local ButtonTable=require('ui/widget/buttontable')
local Button=require('ui/widget/button')
local HorizontalGroup=require('ui/widget/horizontalgroup')
local HorizontalSpan=require('ui/widget/horizontalspan')
local Blitbuffer=require('ffi/blitbuffer')
local CenterContainer=require('ui/widget/container/centercontainer')
local Geom=require('ui/geometry')
local Slider=require('ci_slider')
local AnchorLayout=require('ci_anchorlayout')
local FrameContainer=require('ui/widget/container/framecontainer')
local LineWidget=require('ui/widget/linewidget')
local TextWidget=require('ui/widget/textwidget')
local Font=require('ui/font')
local Screen=require('device').screen
local catalog=require('font_catalog')
local spacing=require('font_spacing')
local css=require('capitulares_css')
local colors=require('capitulares_colors')
local geometry=require('font_geometry')
local T=require('ci_lang').t

local function faceOf(rec,target)
    if not rec or not rec.path then return Font:getFace('cfont',target or 68) end
    local filename=rec.path:match('([^/\\]+)$')
    local ok,face=pcall(Font.getFace,Font,filename,target or 68,rec.index)
    if ok and face then return face end
    return Font:getFace('cfont',target or 68)
end
local function clamp(v,lo,hi)
    return math.max(lo,math.min(hi,v))
end
local function rounded(v)
    return math.floor(v+0.5)
end
local function button(s,fn)
    return {text=s,callback=fn}
end
local function same(a,b)
    return math.abs((tonumber(a) or 0)-(tonumber(b) or 0))<0.01
end

-- Entry screen when a book has not opted in. Uses the same anchored,
-- double-frame panel and a genuine KOReader CheckButton (not a warning popup).
-- Delay opening the full controls until after the touch callback has ended.
function M.openActivation(plugin)
    if plugin._ci_dialog then return end
    local CheckButton=require('ui/widget/checkbutton')
    local w=math.min(Screen:getWidth()-48, math.max(310,math.floor(Screen:getWidth()*0.54)))
    local inner=w-70
    local title=TextWidget:new{text=T('Capitulares','Capitulares'),face=Font:getFace('tfont',30),bold=true}
    local root,transitioning
    local checkbox
    checkbox=CheckButton:new{
        width=inner,single_line=true,checked=false,
        text=T('Ativar capitulares?','Enable drop caps?'),
        face=Font:getFace('cfont',23),checkmark_face=Font:getFace('cfont',23),
        callback=function()
            if not checkbox.checked or transitioning then return end
            transitioning=true
            UIManager:nextTick(function()
                if plugin._ci_dialog~=root then return end
                UIManager:close(root,'full')
                plugin._ci_dialog=nil
                plugin:setBookEnabled(true)
                M.open(plugin)
            end)
        end,
    }
    local close=Button:new{
        text=T('Fechar','Close'),width=inner,
        height=Screen:scaleBySize(31),bordersize=0,margin=0,padding=0,
        background=Blitbuffer.COLOR_WHITE,text_font_size=20,
        callback=function()
            if transitioning then return end
            transitioning=true
            UIManager:nextTick(function()
                if plugin._ci_dialog~=root then return end
                UIManager:close(root,'full')
                plugin._ci_dialog=nil
                UIManager:setDirty('all','full')
            end)
        end,
    }
    local contents=VerticalGroup:new{align='center',
        CenterContainer:new{dimen=Geom:new{w=inner,h=title:getSize().h},title},
        VerticalSpan:new{width=Screen:scaleBySize(12)},
        checkbox,
        VerticalSpan:new{width=Screen:scaleBySize(15)},
        close,
    }
    local innerFrame=FrameContainer:new{
        background=Blitbuffer.COLOR_WHITE,bordersize=Screen:scaleBySize(1),
        margin=0,padding=Screen:scaleBySize(5),radius=Screen:scaleBySize(10),
        contents,
    }
    local panel=FrameContainer:new{
        background=Blitbuffer.COLOR_WHITE,bordersize=Screen:scaleBySize(1),
        margin=0,padding=Screen:scaleBySize(3),radius=Screen:scaleBySize(14),
        innerFrame,
    }
    root=AnchorLayout:new{panel=panel,modal=true}
    checkbox.parent=root
    plugin._ci_dialog=root
    UIManager:show(root)
end
function M.open(plugin)
    if plugin._ci_dialog then return end
    if not plugin:enabledForBook() then return M.openActivation(plugin) end
    local all=catalog.list(true)
    local groups={initials={},reader={}}
    for _,rec in ipairs(all) do
        local g=rec.preferred and 'initials' or 'reader'
        groups[g][#groups[g]+1]=rec
    end
    local active=plugin:activeSourceGroup()
    if active~='initials' and active~='reader' and active~='book' then active='initials' end
    if active~='book' and #groups[active]==0 then
        active=#groups.initials>0 and 'initials' or (#groups.reader>0 and 'reader' or 'book')
    end
    local previous_mode=plugin:extraValue('extra_mode')
    if previous_mode=='pages' then previous_mode='screens' end
    local state={mode=active,selected={initials=1,reader=1},drafts={},last=nil,
        position_step=1,view='main',
        advanced={extra_enabled=plugin:extraValue('extra_enabled')==true,
            extra_mode=previous_mode=='screens' and 'screens' or 'paragraphs',
            extra_interval=math.max(1,math.floor(tonumber(plugin:extraValue('extra_interval')) or 1)),
            override=plugin:extraValue('override')==true,
            dropcap_color=plugin:bookColor()}}
    local selected=plugin:displayFont()
    for group,list in pairs(groups) do
        for i,rec in ipairs(list) do
            if rec.name==selected then state.selected[group]=i;break end
        end
    end
    -- O mesmo tamanho base usado pelo motor de leitura. O CSS continua em em
    -- para preservar a geometria aprovada; o painel opera em px de ecra.
    local function basePx()
        return plugin:baseFontPx()
    end
    local function currentRecord()
        if state.mode=='book' then return nil end
        return groups[state.mode][state.selected[state.mode]]
    end
    local function profileKey()
        local rec=currentRecord()
        return spacing.key(state.mode,rec and rec.path,rec and rec.name,rec and rec.index)
    end
    local function defaults()
        local b=basePx()
        return {size_px=rounded(css.defaults.size*b),gap_px=rounded(css.defaults.gap*b),vertical_px=0,offset_x_px=0}
    end
    local function fromProfile(p)
        if not p then return nil end
        local b=basePx()
        return {
            size_px=rounded(p.size_px or (p.size or css.defaults.size)*b),
            gap_px=rounded(p.gap_px or (p.gap or css.defaults.gap)*b),
            vertical_px=rounded(p.vertical_px or (p.vertical or 0)*b),
            offset_x_px=rounded(p.offset_x_px or (p.offset_x or 0)*b),
        }
    end
    -- Usar o mesmo calculo de seguranca que a CSS aplica realmente.
    -- Cada fonte/entrelinha/tamanho do corpo/ajuste de margem tem um maximo
    -- proprio. O calculo e optico por fonte, nao uma medicao exata do EPUB.
    local function sizeBounds(v)
        local b=basePx()
        local rec=currentRecord()
        local metrics=state.mode=='book' and {height=0.88,width=0.88}
            or (rec and geometry.measure(rec.path,rec.index))
            or (plugin._ci_font_metrics or {height=0.88,width=0.88})
        local lim=css.sizeLimits{
            font_metrics=metrics,
            leading=plugin:currentLeading(),
            base_font_px=b,
            gap=(v.gap_px or rounded(css.defaults.gap*b))/b,
            vertical_shift=(v.vertical_px or 0)/b,
            offset_x=(v.offset_x_px or 0)/b,
        }
        local lo=math.ceil(lim.minimum*b-0.000001)
        local hi=math.floor(lim.maximum*b+0.000001)
        return lo,math.max(lo+1,hi)
    end
    local function draft()
        local key=profileKey()
        if not state.drafts[key] then
            local p=spacing.get(key)
            local book=plugin.ui.doc_settings:readSetting('capitulares_v1_selected_profile')
            if book and book.key==key then p=book end
            state.drafts[key]=fromProfile(p) or defaults()
        end
        local v=state.drafts[key]
        local lo,hi=sizeBounds(v)
        -- Se um perfil antigo exceder o limite (ou a entrelinha diminuir),
        -- restringir o valor mostrado SEM gravar silenciosamente o perfil.
        v.size_px=clamp(v.size_px,lo,hi)
        return v
    end
    local function bounds(which)
        local b=basePx()
        if which=='size_px' then return sizeBounds(draft()) end
        if which=='gap_px' then return 0,rounded(0.8*b) end
        if which=='offset_x_px' then return -math.min(16,rounded(0.4*b)),math.min(16,rounded(0.4*b)) end
        return -rounded(0.65*b),rounded(0.65*b)
    end
    -- Delay changes of window stack until the current input callback has ended.
    -- Destroying a button while KOReader is still handling its touch event can
    -- leave the native IconButton without a valid dimen (seen in crash.log).
    local window_busy=false
    local redraw_queued=false
    local function closePanel(final)
        local window=plugin._ci_dialog
        if not window then return end
        plugin._ci_dialog=nil
        local region
        if not final then
            local size=window.panel and window.panel:getSize()
            if size and size.w and size.h then
                local margin=Screen:scaleBySize(12)
                local x=math.max(0,(window.panel_x or 0)-margin)
                local y=math.max(0,(window.panel_y or 0)-margin)
                region=Geom:new{x=x,y=y,
                    w=math.max(1,math.min(Screen:getWidth()-x,size.w+2*margin)),
                    h=math.max(1,math.min(Screen:getHeight()-y,size.h+2*margin))}
            end
        end
        -- For final close, do a full repaint: partial refreshes left ghosts
        -- on e-ink when the reader's underlying content was not redrawn.
        local refresh=final and 'full' or 'ui'
        UIManager:close(window,refresh,region)
        UIManager:setDirty('all',refresh,region)
        if final then UIManager:forceRePaint() end
    end
    local function finishPanel()
        if window_busy then return end
        window_busy=true
        UIManager:nextTick(function()
            closePanel(true)
            plugin._ci_preview_profile=nil
            window_busy=false
        end)
    end
    -- Ao escolher outra fonte, descarta SOMENTE o ensaio nao guardado
    -- da anterior; o perfil efetivamente guardado continua intacto.
    local function forgetDraft()
        state.drafts[profileKey()]=nil
        plugin._ci_preview_profile=nil
    end
    local draw -- forward declaration
    local function rebuild()
        if redraw_queued or window_busy then return end
        redraw_queued=true
        UIManager:nextTick(function()
            redraw_queued=false
            closePanel(false)
            draw()
        end)
    end
    -- All browsing/slider changes are in-memory only. One repaint on Apply.
    local function live()
        rebuild()
    end
    local function switchMode(g)
        if state.mode==g then return end
        if g~='book' and #groups[g]==0 then
            UIManager:show(require('ui/widget/infomessage'):new{text=T('Não há fontes nesta categoria.','No fonts in this category.')})
            return
        end
        forgetDraft()
        state.mode=g
        state.last=nil
        live()
    end
    local function move(delta)
        if state.mode=='book' then return end
        local list=groups[state.mode]
        if #list<2 then return end
        forgetDraft()
        state.selected[state.mode]=(state.selected[state.mode]-1+delta+#list)%#list+1
        state.last=nil
        live()
    end
    local function change(which,delta)
        local v=draft()
        local lo,hi=bounds(which)
        local nextValue=clamp(v[which]+delta,lo,hi)
        if nextValue==v[which] then return end
        v[which]=nextValue
        live()
    end
    -- Ajuste direto no slider, com passo de 1 px; sem editor modal atrás
    -- do painel Editorial Premium. O valor aparece no topo do slider.
    local function saveProfile()
        local key=profileKey()
        local v=draft()
        if spacing.set(key,{
            size_px=v.size_px,gap_px=v.gap_px,vertical_px=v.vertical_px,offset_x_px=v.offset_x_px,
            size=v.size_px/basePx(),gap=v.gap_px/basePx(),vertical=v.vertical_px/basePx(),offset_x=v.offset_x_px/basePx(),
        }) then
            -- Continua a usar os novos valores, agora guardados por fonte.
            plugin._ci_preview_profile=nil
            state.last=nil
            live()
        end
    end
    local function resetPosition()
        local v=draft()
        if v.offset_x_px==0 and v.vertical_px==0 then return end
        v.offset_x_px=0
        v.vertical_px=0
        live()
    end
    -- Setas substituem os sliders de espaco. Os ajustes sao temporarios
    -- ate o utilizador clicar explicitamente em 'Guardar ajustes'.
    local function nudge(axis,direction)
        change(axis,state.position_step*direction)
    end
    local function resetProfile()
        local key=profileKey()
        spacing.reset(key)
        state.drafts[key]=defaults()
        draft() -- restringe ao limite atual desta fonte
        state.last=nil
        live()
    end
    local function makeDefault()
        local rec=currentRecord()
        local face,err=plugin:prepareSelection(rec)
        if face==nil then
            UIManager:show(require('ui/widget/infomessage'):new{text=tostring(err)})
            return
        end
        -- Set default only. Do NOT save current temporary adjustments and
        -- do NOT reflow the opened book until the user chooses Apply.
        G_reader_settings:saveSetting('capitulares_v1_font_source',rec and rec.name or '')
        G_reader_settings:saveSetting('capitulares_v1_source_group',state.mode)
        G_reader_settings:saveSetting('capitulares_v1_style',
            state.mode=='book' and 'classica' or 'decorativa')
        G_reader_settings:saveSetting('capitulares_v1_font',face)
        rebuild()
    end
    local function isDefault()
        local savedMode=G_reader_settings:readSetting('capitulares_v1_source_group')
        if savedMode~='initials' and savedMode~='reader' and savedMode~='book' then
            savedMode=plugin:activeSourceGroup()
        end
        if savedMode~=state.mode then return false end
        if state.mode=='book' then return true end
        local rec=currentRecord()
        return rec and G_reader_settings:readSetting('capitulares_v1_font_source')==rec.name
    end
    local function returnToDefault()
        -- Restore the saved selection and its own saved calibration; never
        -- change the default or persist the experimental font on return.
        local mode=G_reader_settings:readSetting('capitulares_v1_source_group')
        if mode~='initials' and mode~='reader' and mode~='book' then
            mode=plugin:activeSourceGroup()
        end
        local name=G_reader_settings:readSetting('capitulares_v1_font_source')
        local index
        if mode~='book' then
            for i,rec in ipairs(groups[mode]) do
                if rec.name==name then index=i;break end
            end
            if not index then
                UIManager:show(require('ui/widget/infomessage'):new{text=T(
                    'A fonte padrão não está disponível nesta sessão.',
                    'The default font is unavailable in this session.')})
                return
            end
        end
        forgetDraft()
        state.mode=mode
        if index then state.selected[mode]=index end
        state.drafts[profileKey()]=fromProfile(spacing.get(profileKey())) or defaults()
        state.last=nil
        live()
    end
    local function applyCurrent()
        local rec=currentRecord()
        local v=draft()
        local profile={key=profileKey(),size_px=v.size_px,gap_px=v.gap_px,
            vertical_px=v.vertical_px,offset_x_px=v.offset_x_px}
        local extras={extra_enabled=state.advanced.extra_enabled,
            extra_mode=state.advanced.extra_mode,
            extra_interval=state.advanced.extra_interval,
            override=state.advanced.override,
            dropcap_color=state.advanced.dropcap_color}
        -- Do not close the panel while its button is still receiving input.
        if window_busy then return end
        window_busy=true
        UIManager:nextTick(function()
            closePanel(true)
            local ran,ok,err=pcall(plugin.applyBookSelection,plugin,state.mode,rec,profile,extras)
            window_busy=false
            if not ran or not ok then
                draw()
                UIManager:show(require('ui/widget/infomessage'):new{
                    text=T('Não foi possível aplicar. Verifica a configuração anterior. ',
                           'Could not apply. Check the previous settings. ')..tostring(ran and err or ok)})
            end
        end)
    end
    draw=function()
        if plugin._ci_dialog then return end
        local rec=currentRecord()
        local v=draft()
        local total=rec and #groups[state.mode] or 1
        local index=rec and state.selected[state.mode] or 1
        -- Mais largura, mas continua no lado direito. Nunca usa um overlay global.
        local sw=Screen:getWidth()
        local w=math.min(sw-48,math.max(310,math.floor(sw*0.54)))
        local inner=w-70
        local name=rec and rec.name or T('Letra do livro','Book font')
        if #name>32 then name=name:sub(1,29)..'...' end
        local function center(widget,interactive)
            if not interactive then widget.not_focusable=true end
            return CenterContainer:new{dimen=Geom:new{w=inner,h=widget:getSize().h},widget}
        end
        -- Amostras maiores; reduzir apenas se a face for demasiado larga.
        local sampleWidget
        local sampleSize=math.min(Screen:getHeight()<=1800 and 74 or 86,
            math.max(56,math.floor(Screen:getHeight()*0.058)))
        for candidate=sampleSize,42,-4 do
            sampleWidget=TextWidget:new{text='A B C',face=faceOf(rec,candidate)}
            if sampleWidget:getSize().w<=inner then break end
        end
        local sample=center(sampleWidget)
        local fontName=center(TextWidget:new{text=name,face=Font:getFace('cfont',22),max_width=inner})
        local count=center(TextWidget:new{
            text=tostring(index)..' / '..tostring(total),
            face=Font:getFace('cfont',18),max_width=inner,
        })
        -- Navegacao compacta: setas ao lado do contador, sem uma linha
        -- separada de botoes "Fonte".
        local arrowWidth=math.max(40,math.floor(inner*0.18))
        local arrows=HorizontalGroup:new{allow_mirroring=false,
            Button:new{text='‹',width=arrowWidth,height=Screen:scaleBySize(30),
                bordersize=0,margin=0,padding=0,background=Blitbuffer.COLOR_WHITE,
                text_font_size=26,callback=function()move(-1)end},
            CenterContainer:new{dimen=Geom:new{w=inner-2*arrowWidth,
                h=Screen:scaleBySize(30)},count},
            Button:new{text='›',width=arrowWidth,height=Screen:scaleBySize(30),
                bordersize=0,margin=0,padding=0,background=Blitbuffer.COLOR_WHITE,
                text_font_size=26,callback=function()move(1)end},
        }
        -- O separador ativo usa fundo cinzento; nunca um ponto selecionado.
        local function sourceButton(mode,pt,en)
            return {text=T(pt,en),font_size=17,
                font_bold=state.mode==mode,
                background=state.mode==mode and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                callback=function()switchMode(mode)end}
        end
        local sources=ButtonTable:new{width=inner,buttons={{
            sourceButton('initials','Initials\n(recomend.)','Initials\n(recommended)'),
            sourceButton('reader','Fontes\ndo leitor','Reader\nfonts'),
            sourceButton('book','Letra\ndo livro','Book\nfont'),
        }}}
        local function track(which,title,left,right,reverse,format)
            local lo,hi=bounds(which)
            return Slider:new{
                width=inner,title=title,
                value=v[which],minimum=lo,maximum=hi,
                step=1,inverted=reverse,
                left_text=left,right_text=right,
                value_text=format and format(v[which]) or tostring(v[which])..' px',
                on_change=function(value)
                    if v[which]~=value then v[which]=value;live() end
                end,
                -- Não definir on_exact: nem tap nem pressão prolongada
                -- podem abrir um SpinWidget atrás do painel.
            }
        end
        local positionValue=TextWidget:new{
            text=string.format(T('Horizontal: %s%d px  ·  Vertical: %s%d px',
                'Horizontal: %s%d px  ·  Vertical: %s%d px'),
                v.offset_x_px>=0 and '+' or '',v.offset_x_px,
                v.vertical_px>=0 and '+' or '',v.vertical_px),
            face=Font:getFace('cfont',16),max_width=inner,
        }
        local title=center(TextWidget:new{
            text=T('Capitulares','Capitulares'),face=Font:getFace('tfont',30),bold=true,
        })
        local ornament=center(TextWidget:new{
            text='◆',face=Font:getFace('cfont',12),
        })
        local function fineRule()
            return CenterContainer:new{dimen=Geom:new{w=inner,h=Screen:scaleBySize(2)},
                LineWidget:new{background=Blitbuffer.COLOR_GRAY,
                    dimen=Geom:new{w=inner,h=Screen:scaleBySize(1)}}}
        end
        -- Botão sem moldura; a área tátil mantém o tamanho aprovado.
        local function cleanButton(label,width,height,callback,fontSize,bold)
            return Button:new{
                text=label,width=width,height=height,
                bordersize=0,radius=0,margin=0,padding=0,
                background=Blitbuffer.COLOR_WHITE,
                text_font_size=fontSize or 22,
                text_font_bold=bold or false,
                callback=callback,
            }
        end
        local function present(contents)
            -- Same anchored double-frame for both views, never a stacked popup.
            local innerFrame=FrameContainer:new{
                background=Blitbuffer.COLOR_WHITE,
                bordersize=Screen:scaleBySize(1),margin=0,
                padding=Screen:scaleBySize(5),radius=Screen:scaleBySize(10),
                contents,
            }
            local panel=FrameContainer:new{
                background=Blitbuffer.COLOR_WHITE,
                bordersize=Screen:scaleBySize(1),margin=0,
                padding=Screen:scaleBySize(3),radius=Screen:scaleBySize(14),
                innerFrame,
            }
            local root=AnchorLayout:new{panel=panel,modal=true}
            plugin._ci_dialog=root
            UIManager:show(root)
        end
        -- Painel único: direção e tamanho na mesma vista, sem submenus
        -- nem camadas flutuantes sobre a página de leitura.
        local vgap=Screen:scaleBySize(1)
        local d=Screen:scaleBySize(28)
        local g=Screen:scaleBySize(2)
        local function directionButton(symbol,axis,sign)
            return cleanButton(symbol,d,d,function() nudge(axis,sign) end,26,true)
        end
        local function padRow(left,mid,right)
            return HorizontalGroup:new{allow_mirroring=false,
                left or HorizontalSpan:new{width=d},
                HorizontalSpan:new{width=g},
                mid or HorizontalSpan:new{width=d},
                HorizontalSpan:new{width=g},
                right or HorizontalSpan:new{width=d},
            }
        end
        local positionPad=VerticalGroup:new{align='center',
            padRow(nil,directionButton('↑','vertical_px',-1),nil),
            VerticalSpan:new{width=g},
            padRow(directionButton('←','offset_x_px',-1),
                cleanButton('0',d,d,resetPosition,19,false),
                directionButton('→','offset_x_px',1)),
            VerticalSpan:new{width=g},
            padRow(nil,directionButton('↓','vertical_px',1),nil),
        }
        local function stepButton(amount)
            local selected=state.position_step==amount
            local action=cleanButton(tostring(amount)..' px',Screen:scaleBySize(88),d,
                function()
                    if state.position_step~=amount then
                        state.position_step=amount
                        rebuild() -- redesenha o painel, sem repaginar o livro
                    end
                end,18,selected)
            local underline=LineWidget:new{
                background=selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                dimen=Geom:new{w=Screen:scaleBySize(50),h=Screen:scaleBySize(2)},
            }
            return VerticalGroup:new{align='center',action,underline}
        end
        local stepColumn=VerticalGroup:new{align='center',
            stepButton(1),VerticalSpan:new{width=g},
            stepButton(2),VerticalSpan:new{width=g},
            stepButton(5),
        }
        local adjustControls=HorizontalGroup:new{allow_mirroring=false,
            positionPad,HorizontalSpan:new{width=Screen:scaleBySize(16)},stepColumn,
        }
        local positionControls=center(adjustControls,true)
        local sizeSlider=track('size_px',T('Tamanho','Size'),
            T('Menor','Smaller'),T('Maior','Larger'),false)
        -- Ações editoriais sem caixas individuais; divisórias subtis.
        local action_h=Screen:scaleBySize(25)
        local function actionLine(pt,en,fn,font_size)
            return cleanButton(T(pt,en),inner,action_h,fn,font_size or 19,true)
        end
        local action_half=math.floor((inner-Screen:scaleBySize(6))/2)
        if state.view=='advanced' then
            local a=state.advanced
            local function toggle(field)
                a[field]=not a[field]
                rebuild()
            end
            local function modeBtn(mode,pt,en)
                return cleanButton((a.extra_mode==mode and '◉  ' or '○  ')..T(pt,en),
                    inner,action_h,function()a.extra_mode=mode;rebuild()end,19,false)
            end
            local function intervalBtn(symbol,delta)
                return cleanButton(symbol,Screen:scaleBySize(53),action_h,function()
                    a.extra_interval=math.max(1,math.min(10000,a.extra_interval+delta))
                    rebuild()
                end,24,true)
            end
            local intervalValue=TextWidget:new{
                text=tostring(a.extra_interval),face=Font:getFace('cfont',22),
            }
            local valueWidth=Screen:scaleBySize(44)
            local intervalBar=HorizontalGroup:new{allow_mirroring=false,
                cleanButton(T('Intervalo:','Interval:'),inner-2*Screen:scaleBySize(53)-valueWidth,
                    action_h,function()end,19,true),
                intervalBtn('‹',-1),
                CenterContainer:new{dimen=Geom:new{w=valueWidth,h=action_h},intervalValue},
                intervalBtn('›',1),
            }
            local content={
                title,ornament,VerticalSpan:new{width=Screen:scaleBySize(8)},
                center(TextWidget:new{text=T('Avançado','Advanced'),face=Font:getFace('cfont',23),bold=true}),
                VerticalSpan:new{width=Screen:scaleBySize(12)},
                fineRule(),
                actionLine((a.extra_enabled and '☑  ' or '☐  ')..'Ativar capitulares adicionais',
                    (a.extra_enabled and '☑  ' or '☐  ')..'Enable additional drop caps',
                    function() toggle('extra_enabled') end,17),
            }
            if a.extra_enabled then
                content[#content+1]=fineRule()
                content[#content+1]=center(TextWidget:new{
                    text=T('Contar por','Count by'),face=Font:getFace('cfont',18)})
                content[#content+1]=modeBtn('paragraphs','Parágrafos','Paragraphs')
                content[#content+1]=modeBtn('screens','Ecrãs reais','Actual screens')
                content[#content+1]=fineRule()
                content[#content+1]=intervalBar
            end
            -- Color is optional, shown ONLY on color-capable screens.
            -- It is local to this EPUB; Original emits no CSS color rule.
            if plugin:colorSupported() then
                content[#content+1]=fineRule()
                content[#content+1]=center(TextWidget:new{
                    text=T('Cor da capitular','Drop cap color'),
                    face=Font:getFace('cfont',18)})
                local item=colors.get(a.dropcap_color)
                local color_name=T(item.pt,item.en)
                local color_middle=TextWidget:new{
                    text=color_name,face=Font:getFace('cfont',19),max_width=inner-Screen:scaleBySize(120)}
                local color_row=HorizontalGroup:new{allow_mirroring=false}
                local color_arr={}
                if item.hex then
                    color_arr[#color_arr+1]=LineWidget:new{
                        background=Blitbuffer.ColorRGB32(item.r,item.g,item.b,255),
                        dimen=Geom:new{w=Screen:scaleBySize(17),h=Screen:scaleBySize(17)}}
                    color_arr[#color_arr+1]=HorizontalSpan:new{width=Screen:scaleBySize(8)}
                end
                color_arr[#color_arr+1]=color_middle
                -- CenterContainer receives a fixed width to preserve the
                -- existing single-panel layout on compact e-ink screens.
                color_row=HorizontalGroup:new{allow_mirroring=false,unpack(color_arr)}
                local arrow_width=Screen:scaleBySize(44)
                content[#content+1]=HorizontalGroup:new{allow_mirroring=false,
                    cleanButton('‹',arrow_width,action_h,function()
                        a.dropcap_color=colors.next(a.dropcap_color,-1);rebuild()
                    end,24,true),
                    CenterContainer:new{dimen=Geom:new{w=inner-2*arrow_width,h=action_h},color_row},
                    cleanButton('›',arrow_width,action_h,function()
                        a.dropcap_color=colors.next(a.dropcap_color,1);rebuild()
                    end,24,true),
                }
                if not plugin:colorRenderingEnabled() then
                    content[#content+1]=center(TextWidget:new{
                        text=T('Ativa a apresentação a cores no KOReader.',
                            'Enable color rendering in KOReader.'),
                        face=Font:getFace('cfont',14),max_width=inner})
                end
            end
            content[#content+1]=fineRule()
            content[#content+1]=actionLine(
                (a.override and '☑  ' or '☐  ')..'Sobrepor formatação do EPUB',
                (a.override and '☑  ' or '☐  ')..'Override EPUB formatting',
                function()toggle('override')end,17)
            if a.extra_enabled and a.extra_mode=='screens' then
                content[#content+1]=center(TextWidget:new{
                    text=T('Ecrãs desde cada capítulo.',
                           'Screens counted from each chapter.'),
                    face=Font:getFace('cfont',15),max_width=inner})
                if plugin._ci_screen_status then
                    content[#content+1]=center(TextWidget:new{
                        text=plugin._ci_screen_status,
                        face=Font:getFace('cfont',14),max_width=inner})
                end
            end
            content[#content+1]=VerticalSpan:new{width=Screen:scaleBySize(15)}
            content[#content+1]=fineRule()
            content[#content+1]=actionLine('Aplicar','Apply',applyCurrent,20)
            content[#content+1]=actionLine('Voltar','Back',function()
                state.view='main';rebuild()
            end,19)
            present(VerticalGroup:new{align='center',unpack(content)})
            return
        end
        local defaultButton
        if isDefault() then
            -- Native KOReader text button, visually muted and not interactive.
            defaultButton=cleanButton(T('★  Capitular padrão','★  Default Drop Cap'),
                inner,action_h,function()end,19,true)
            defaultButton.enabled=false
            defaultButton.background=Blitbuffer.COLOR_LIGHT_GRAY
        else
            defaultButton=actionLine('Escolher como padrão','Set as Default',makeDefault,19)
        end
        local actions=VerticalGroup:new{align='center',
            fineRule(),
            defaultButton,
            isDefault() and VerticalSpan:new{width=0} or
                actionLine('Voltar à capitular padrão','Return to Default Drop Cap',returnToDefault,18),
            fineRule(),
            HorizontalGroup:new{allow_mirroring=false,
                cleanButton(T('Guardar ajustes','Save settings'),action_half,action_h,saveProfile,18,true),
                HorizontalSpan:new{width=Screen:scaleBySize(6)},
                cleanButton(T('Repor ajustes','Reset settings'),action_half,action_h,resetProfile,18,true),
            },
            fineRule(),
            actionLine('Aplicar','Apply',applyCurrent,20),
            actionLine('Avançado','Advanced',function()
                state.view='advanced';rebuild()
            end,18),
            actionLine('Fechar','Close',finishPanel,20),
        }
        local panelContents=VerticalGroup:new{
            align='center',
            title,ornament,VerticalSpan:new{width=vgap},fontName,
            sample,arrows,VerticalSpan:new{width=vgap},sources,
            VerticalSpan:new{width=vgap},sizeSlider,center(positionValue),
            positionControls,VerticalSpan:new{width=vgap},
            actions,
        }
        present(panelContents)
    end
    draw()
end
return M
