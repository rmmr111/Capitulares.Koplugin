-- Capitulares v1.0 — menu simplificado, perfis por fonte, tamanho seguro.
-- Plugin independente, nao altera os EPUBs nem patches de paginas/estatisticas.
local WidgetContainer=require('ui/widget/container/widgetcontainer')
local Dispatcher=require('dispatcher')
local Screen=require('device').screen
local Event=require('ui/event')
local InfoMessage=require('ui/widget/infomessage')
local UIManager=require('ui/uimanager')
local css=require('capitulares_css')
local colors=require('capitulares_colors')
local fonts=require('font_catalog')
local alias=require('font_alias')
local auto=require('font_auto')
local geometry=require('font_geometry')
local spacing=require('font_spacing')
local frequency=require('capitulares_frequency')
local screenmap=require('capitulares_screenmap')
local lang=require('ci_lang')
local T=lang.t
local PREF='capitulares_v1_'
local BOOK='capitulares_v1_book'
-- Additional drop caps are explicitly configured per book only.
local EXTRA_PREFIX='capitulares_v1_extra_book_'
local BOOK_FONT_PREFIX='capitulares_v1_selected_' -- book-specific applied font
local COLOR_SETTING='capitulares_v1_book_color' -- per-EPUB; default preserves original text color
local BOOK_PROFILE='capitulares_v1_selected_profile' -- applied per-book calibration
local D=css.defaults
local plugin=WidgetContainer:extend{name='capitulares',is_doc_only=true}
local function setting(name)
    local value=G_reader_settings:readSetting(PREF..name)
    if value==nil then return D[name] end
    return value
end
function plugin:current(name)
    if self.temporary and self.temporary[name]~=nil then return self.temporary[name] end
    return setting(name)
end
-- Preferencias antigas com "Estilo: Classica" continuam a funcionar.
-- A categoria nova e persistida so ao aplicar uma selecao no painel.
function plugin:activeSourceGroup()
    if self.temporary and self.temporary.source_group then
        return self.temporary.source_group
    end
    local saved=self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..'source_group')
        or G_reader_settings:readSetting(PREF..'source_group')
    if saved=='book' or saved=='initials' or saved=='reader' then return saved end
    if self:current('style')=='classica' then return 'book' end
    return self._ci_active_preferred and 'initials' or 'reader'
end
function plugin:fontProfileKey(mode)
    return spacing.key(mode or self:activeSourceGroup(),self._ci_source_path,
        self._ci_active_name or self:displayFont(),self._ci_source_index)
end
function plugin:baseFontPx()
    -- Igual ao tamanho base que ReaderFont passa a setFontSize na abertura.
    local cfg=self.ui.document and self.ui.document.configurable
    local fontSize=cfg and tonumber(cfg.font_size) or 22
    local scaled=Screen:scaleBySize(fontSize)
    return math.max(12,math.min(255,tonumber(scaled) or fontSize))
end
-- Ler a entrelinha atual; pode mudar apos onReaderReady sem reabrir o EPUB.
function plugin:currentLeading()
    local cfg=self.ui and self.ui.document and self.ui.document.configurable
    local lead=cfg and tonumber(cfg.line_spacing)
    if lead and lead>=75 and lead<=250 then return lead/100 end
    return self._ci_leading or 1.2
end
-- A color reader must also have color rendering enabled in KOReader.
function plugin:colorSupported()
    if type(Screen.isColorScreen)~='function' then return false end
    local ok,result=pcall(Screen.isColorScreen,Screen)
    return ok and result==true
end
function plugin:colorRenderingEnabled()
    if not self:colorSupported() then return false end
    if type(Screen.isColorEnabled)~='function' then return true end
    local ok,result=pcall(Screen.isColorEnabled,Screen)
    return ok and result==true
end
function plugin:bookColor()
    return colors.normalize(self.ui.doc_settings:readSetting(COLOR_SETTING))
end
function plugin:options()
    local opts={}
    for k in pairs(D) do opts[k]=self:current(k) end
    local mode=self:activeSourceGroup()
    opts.source_group=mode
    local chosen=self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..'family')
    if chosen~=nil then opts.font=chosen end
    if mode=='book' then opts.style='classica';opts.font='' end
    if self._ci_invalid_font and mode~='book' then
        -- A previously saved symbol/partial font must not swallow letters.
        opts.source_group='book'
        opts.style='classica'
        opts.font=''
    end
    -- Cada nova fonte parte do valor padrao do motor, mesmo que exista um
    -- tamanho antigo gravado nos ajustes globais. Apenas um perfil guardado
    -- dessa fonte (ou o ensaio enquanto o painel esta aberto) o substitui.
    opts.size=D.size
    opts.gap=D.gap
    opts.vertical_shift=D.vertical_shift
    opts.offset_x=0
    opts.font_metrics=mode=='book' and {height=0.88,width=0.88}
        or (self._ci_font_metrics or {height=0.88,width=0.88})
    opts.leading=self:currentLeading()
    opts.base_font_px=self:baseFontPx()
    opts.paragraphs_per_page=self._ci_paragraphs_per_page or 3
    local key=self:fontProfileKey(mode)
    local local_profile=self.ui.doc_settings:readSetting(BOOK_PROFILE)
    local profile=(self._ci_preview_profile and self._ci_preview_profile.key==key)
        and self._ci_preview_profile
        or (local_profile and local_profile.key==key and local_profile)
        or spacing.get(key)
    if profile then
        local base=self:baseFontPx()
        opts.size=profile.size_px and profile.size_px/base or profile.size
        opts.gap=profile.gap_px and profile.gap_px/base or profile.gap
        opts.vertical_shift=profile.vertical_px and profile.vertical_px/base or (profile.vertical or 0)
        opts.offset_x=profile.offset_x_px and profile.offset_x_px/base or (profile.offset_x or 0)
    end
    -- Opcao avancada temporaria tem precedencia sobre os perfis guardados.
    for _,k in ipairs({'size','gap','vertical_shift'}) do
        if self.temporary and self.temporary[k]~=nil then opts[k]=self.temporary[k] end
    end
    -- Extra drop caps may be overridden only for the current EPUB.
    for _,key in ipairs({'extra_enabled','extra_mode','extra_interval'}) do
        opts[key]=self:extraValue(key)
    end
    opts.override=self:extraValue('override')
    opts.screen_plan=self._ci_screen_plan
    opts.dropcap_color=self:bookColor()
    opts.color_supported=self:colorRenderingEnabled()
    return opts
end
function plugin:extraValue(k)
    -- Do not inherit the old global additional-drop-cap settings. A book
    -- without local choices starts with the plugin defaults.
    local v=self.ui.doc_settings:readSetting(EXTRA_PREFIX..k)
    if v~=nil then return v end
    if k=='override' then return self:current('override') end
    return D[k]
end
function plugin:commitExtra(k,value,menu)
    screenmap.cancel(self)
    self.ui.doc_settings:saveSetting(EXTRA_PREFIX..k,value)
    if self:extraValue('extra_enabled') and (self:extraValue('extra_mode')=='screens' or self:extraValue('extra_mode')=='pages') then
        self._ci_paragraphs_per_page=frequency.estimate(self.ui.document)
    end
    self:refresh()
    if menu and menu.updateItems then menu:updateItems() end
end
function plugin:setBookEnabled(enabled)
    if self:enabledForBook()==(enabled==true) then return end
    self.ui.doc_settings:saveSetting(BOOK,enabled==true)
    -- Disabling removes the injected CSS; enabling prepares the normal chapter
    -- capitals, with page extras loaded/calculated according to book settings.
    if not enabled then screenmap.cancel(self) end
    self:discard(nil)
end
function plugin:bookOverride()
    return self.ui.doc_settings:readSetting(BOOK)==true
end
function plugin:enabledForBook()
    -- Never inherit the legacy GLOBAL setting. Only explicit book opt-in.
    return self:bookOverride()
end
function plugin:screenMode()
    local mode=self:extraValue('extra_mode')
    return self:extraValue('extra_enabled')==true and
        (mode=='screens' or mode=='pages')
end
function plugin:refresh()
    if not self.style or not self.style.updateCssText then return end
    if self:enabledForBook() and self:screenMode() and
       not self._ci_screen_busy and self._ci_screen_plan==nil then
        -- Only the FIRST request (or an explicit invalidation) builds a map.
        -- A restored map must never be recalculated on ordinary refresh.
        screenmap.request(self)
        return
    end
    if not self:enabledForBook() or not self:screenMode() then
        if self._ci_screen_plan~=nil or self._ci_screen_busy then
            screenmap.cancel(self)
        end
    end
    self.style:updateCssText(true)
end
function plugin:temporaryChange(k,v,menu,defer_refresh)
    self.temporary=self.temporary or {}
    self.temporary[k]=v
    if not defer_refresh then self:refresh() end
    if menu then menu:updateItems() end
end
function plugin:saveAll(menu)
    if self.temporary and (self.temporary.extra_enabled ~= nil or
       self.temporary.extra_mode ~= nil) then
        local enabled=self:current('extra_enabled')
        local mode=self:current('extra_mode')
        if enabled and (mode=='screens' or mode=='pages') then
            self._ci_paragraphs_per_page=frequency.estimate(self.ui.document)
        end
    end
    for key in pairs(D) do
        if self.temporary and self.temporary[key]~=nil then
            G_reader_settings:saveSetting(PREF..key,self.temporary[key])
        end
    end
    if self.temporary and self.temporary.font_source then
        G_reader_settings:saveSetting(PREF..'font_source',self.temporary.font_source)
    end
    if self.temporary and self.temporary.source_group then
        G_reader_settings:saveSetting(PREF..'source_group',self.temporary.source_group)
    end
    self.temporary={}
    self:refresh()
    if menu then menu:updateItems() end
end
function plugin:discard(menu)
    self.temporary={}
    self._ci_preview_profile=nil
    self:refresh()
    if menu then menu:updateItems() end
end
function plugin:hasPending()
    return self.temporary and next(self.temporary)~=nil
end
local function radioMenu(self,key,choices,defer_refresh)
    local m={max_per_page=8}
    for _,item in ipairs(choices) do
        local value,label=item[1],item[2]
        m[#m+1]={text=label,radio=true,
            checked_func=function() return self:current(key)==value end,
            callback=function(menu) self:temporaryChange(key,value,menu,defer_refresh) end,
            keep_menu_open=true}
    end
    return m
end
function plugin:spin(key,title,min,max,step,default,menu)
    local SpinWidget=require('ui/widget/spinwidget')
    local spin=SpinWidget:new{
        title_text=title,
        info_text=key=='extra_interval' and T('Aceita valores a partir de 1. No modo páginas, o intervalo é aproximado. Valores baixos podem tornar a paginação mais lenta.','Values start at 1. Page mode is approximate. Low values may slow down pagination.') or T('As alterações ficam temporariamente no livro. Seleciona Guardar ajustes para as manter.','Changes apply temporarily to the book. Select Save adjustments to keep them.'),
        value=self:current(key),value_min=min,value_max=max,
        value_step=step,value_hold_step=step*5,
        precision=key=='extra_interval' and '%.0f' or '%.2f',default_value=default,
        ok_text=T('Usar agora','Use now'),
        callback=function(w) self:temporaryChange(key,w.value,menu,key=='extra_interval') end,
    }
    UIManager:show(spin)
end
-- Fonte original com glifos completos: usa-a diretamente.
-- Fonte com acentos em falta: normaliza so essas entradas na copia e
-- regista-a nesta sessao, sem popups de reinicio.
function plugin:chooseFont(rec,menu,defer_refresh)
    local prepared,err=auto.prepareAndRegister(rec)
    if not prepared then
        self._ci_font_error=tostring(err)
        self:temporaryChange('font',rec.name,menu,defer_refresh)
    else
        self._ci_font_error=prepared.failed_registration and
            T('A fonte não ficou disponível nesta sessão; foi usada a original.',
              'Font unavailable in this session; the original was used.') or nil
        self:temporaryChange('font',prepared.name,menu,defer_refresh)
    end
    self.temporary.font_source=rec.name
    self._ci_invalid_font=false
    self._ci_source_path=rec.path
    self._ci_source_index=rec.index or 0
    self._ci_active_name=rec.name
    self._ci_active_preferred=rec.preferred
    self._ci_font_metrics=geometry.measure(rec.path,rec.index)
end
-- Validate the selected face before exposing it to the book's CSS.
-- Never change the active face on a failed font registration.
function plugin:prepareSelection(rec)
    if not rec then return '' end
    if not fonts.usable(rec) then
        return nil,T('Esta fonte não contém letras utilizáveis.','This font has no usable letters.')
    end
    local ok,prepared,err=pcall(auto.prepareAndRegister,rec)
    if not ok or not prepared or prepared.failed_registration then
        return nil,err or T('Não foi possível carregar esta fonte.','Could not load this font.')
    end
    return prepared.name
end
-- Commit one selection per EPUB; global default remains independent.
local function sameProfile(a,b)
    if not a and not b then return true end
    if type(a)~='table' or type(b)~='table' then return false end
    for _,k in ipairs({'key','size_px','gap_px','vertical_px','offset_x_px'}) do
        if a[k]~=b[k] then return false end
    end
    return true
end
function plugin:applyBookSelection(group,rec,profile,extras)
    local face,err=self:prepareSelection(rec)
    if face==nil then return false,err end
    local old={}
    for _,k in ipairs({'source_group','source','family'}) do
        old[k]=self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..k)
    end
    local previous={path=self._ci_source_path,index=self._ci_source_index,
        name=self._ci_active_name,preferred=self._ci_active_preferred,metrics=self._ci_font_metrics,
        invalid=self._ci_invalid_font}
    local settings=self.ui.doc_settings
    local previous_profile=settings:readSetting(BOOK_PROFILE)
    local previous_extras={}
    local layout_same=old.source_group==group and
        old.source==(rec and rec.name or '') and old.family==face and
        sameProfile(previous_profile,profile)
    for _,k in ipairs({'extra_enabled','extra_mode','extra_interval','override'}) do
        previous_extras[k]=settings:readSetting(EXTRA_PREFIX..k)
        if extras and extras[k]~=nil and extras[k]~=self:extraValue(k) then
            layout_same=false
        end
    end
    local previous_color=settings:readSetting(COLOR_SETTING)
    settings:saveSetting(BOOK_FONT_PREFIX..'source_group',group)
    settings:saveSetting(BOOK_FONT_PREFIX..'source',rec and rec.name or '')
    settings:saveSetting(BOOK_FONT_PREFIX..'family',face)
    if profile then settings:saveSetting(BOOK_PROFILE,profile) end
    if extras then
        for _,k in ipairs({'extra_enabled','extra_mode','extra_interval','override'}) do
            if extras[k]~=nil then settings:saveSetting(EXTRA_PREFIX..k,extras[k]) end
        end
    end
    if extras and extras.dropcap_color~=nil then
        settings:saveSetting(COLOR_SETTING,colors.normalize(extras.dropcap_color))
    end
    -- Changing only the drop-cap color cannot alter line wrapping.
    -- Reuse the existing screen map and avoid a second pagination request.
    if not layout_same then screenmap.cancel(self) end
    self._ci_source_path=rec and rec.path or nil
    self._ci_source_index=rec and (rec.index or 0) or 0
    self._ci_active_name=rec and rec.name or nil
    self._ci_active_preferred=rec and rec.preferred or false
    self._ci_font_metrics=rec and geometry.measure(rec.path,rec.index) or {height=0.88,width=0.88}
    self._ci_invalid_font=false
    local ok,reason=pcall(function() self:refresh() end)
    if not ok then
        for _,k in ipairs({'source_group','source','family'}) do
            if old[k]==nil then settings:delSetting(BOOK_FONT_PREFIX..k)
            else settings:saveSetting(BOOK_FONT_PREFIX..k,old[k]) end
        end
        if previous_profile==nil then settings:delSetting(BOOK_PROFILE)
        else settings:saveSetting(BOOK_PROFILE,previous_profile) end
        for _,k in ipairs({'extra_enabled','extra_mode','extra_interval','override'}) do
            if previous_extras[k]==nil then settings:delSetting(EXTRA_PREFIX..k)
            else settings:saveSetting(EXTRA_PREFIX..k,previous_extras[k]) end
        end
        if previous_color==nil then settings:delSetting(COLOR_SETTING)
        else settings:saveSetting(COLOR_SETTING,previous_color) end
        self._ci_source_path=previous.path
        self._ci_source_index=previous.index
        self._ci_active_name=previous.name
        self._ci_active_preferred=previous.preferred
        self._ci_font_metrics=previous.metrics
        self._ci_invalid_font=previous.invalid
        pcall(function() self:refresh() end)
        return false,tostring(reason)
    end
    return true
end
function plugin:displayFont()
    local source=self.temporary and self.temporary.font_source
    source=source or self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..'source')
    source=source or G_reader_settings:readSetting(PREF..'font_source')
    if source and source~='' then return source end
    local used=self:current('font')
    return used:gsub('^CI2 ', ''):gsub('^CI ','')
end
-- Seletores diretos: uma pequena janela de escolha, sem navegar para outro menu.
local function showChoice(title,entries)
    local ButtonDialog=require('ui/widget/buttondialog')
    local dialog
    local buttons={}
    for _,item in ipairs(entries) do
        buttons[#buttons+1]={{text=item[1],callback=function()
            UIManager:close(dialog)
            item[2]()
        end}}
    end
    dialog=ButtonDialog:new{title=title,shrink_unneeded_width=true,buttons=buttons}
    UIManager:show(dialog)
end
function plugin:commitOption(key,value,menu)
    -- Alterações deste menu são intencionais e ficam gravadas imediatamente.
    -- Ao contrário do painel de personalização, não há aqui ajustes provisórios.
    if self.temporary then self.temporary[key]=nil end
    G_reader_settings:saveSetting(PREF..key,value)
    if (key=='extra_mode' or key=='extra_enabled') and
       self:current('extra_enabled') and (self:current('extra_mode')=='screens' or self:current('extra_mode')=='pages') then
        self._ci_paragraphs_per_page=frequency.estimate(self.ui.document)
    end
    self:refresh()
    if menu then menu:updateItems() end
end
function plugin:chooseDetection(menu)
    local current=self:current('detection')
    local choices={
       {'capitulos',T('Capítulos e subcapítulos','Chapters and subchapters')},
       {'seccoes',T('Secções e quebras estruturais','Sections and structural breaks')},
       {'alargada',T('Deteção alargada','Broad detection')},
    }
    local options={}
    for _,row in ipairs(choices) do
        local value,label=row[1],row[2]
        options[#options+1]={ (current==value and '✓ ' or '')..label,
            function() self:commitOption('detection',value,menu) end }
    end
    showChoice(T('Deteção','Detection'),options)
end
-- Both counting modes are native, direct menu choices, not popups.
function plugin:extraMenu()
    local items={{ci_extra_toggle=true,
        text_func=function() return T('Ativar capitulares adicionais','Enable additional drop caps') end,
        checked_func=function() return self:extraValue('extra_enabled')==true end,
        callback=function(menu)
            self:commitExtra('extra_enabled',not self:extraValue('extra_enabled'),menu)
            self:refreshExtraRows(menu)
        end,keep_menu_open=true,
    }}
    if not self:extraValue('extra_enabled') then return items end
    for _,choice in ipairs({
        {'paragraphs',T('Contar por parágrafos','Count by paragraphs')},
        {'pages',T('Contar por páginas (aproximado)','Count by pages (approximate)')},
    }) do
        local mode,label=choice[1],choice[2]
        items[#items+1]={text=label,radio=true,
            checked_func=function() return self:extraValue('extra_mode')==mode end,
            callback=function(menu) self:commitExtra('extra_mode',mode,menu) end,
            keep_menu_open=true}
    end
    -- Increment/decrement directly, avoiding a nested number-entry dialog.
    -- Hold +/- to change by ten. Interval is unrestricted from 1 upwards.
    local function adjust(delta,menu)
        local current=tonumber(self:extraValue('extra_interval')) or D.extra_interval
        self:commitExtra('extra_interval',math.max(1,math.floor(current+delta)),menu)
    end
    items[#items+1]={
        text_func=function() return T('Intervalo atual: ','Current interval: ')..
            tostring(self:extraValue('extra_interval')) end,
        enabled_func=function() return false end,
    }
    items[#items+1]={text=T('− Diminuir intervalo (1; manter: 10)','− Decrease interval (1; hold: 10)'),
        callback=function(menu) adjust(-1,menu) end,
        hold_callback=function(menu) adjust(-10,menu) end,keep_menu_open=true}
    items[#items+1]={text=T('+ Aumentar intervalo (1; manter: 10)','+ Increase interval (1; hold: 10)'),
        callback=function(menu) adjust(1,menu) end,
        hold_callback=function(menu) adjust(10,menu) end,keep_menu_open=true}
    return items
end
-- Disponibiliza a acao a QUALQUER gesto do utilizador no Gestor de gestos.
-- Sem gesto predefinido; nunca altera as atribuicoes guardadas nem cria atalho em L.
function plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction('capitulares_open_panel',{
        category='none',event='OpenCapitularesPanel',
        title=T('Abrir painel de capitulares','Open Capitulares panel'),
        general=true,
    })
end
function plugin:onOpenCapitularesPanel()
    self:openCustomizer()
    return true
end
function plugin:openCustomizer()
    -- When disabled, the same right panel starts with a native activation
    -- checkbox; ticking it reveals the normal controls immediately.
    -- Remove both menu layers, leaving the book uncovered behind the right panel.
    if self.ui.menu and self.ui.menu.onTapCloseMenu then
        self.ui.menu:onTapCloseMenu()
    end
    UIManager:nextTick(function()
        require('capitulares_customizer').open(self)
    end)
end
-- Refresh the currently open additional-drop-cap submenu without reopening it.
function plugin:refreshExtraRows(menu)
    if not menu then return end
    if type(menu.item_table)=='table' then
        local items=menu.item_table
        local found=false
        for _,item in ipairs(items) do
            if item.ci_extra_toggle then found=true;break end
        end
        if found then
            local fresh=self:extraMenu()
            for i=#items,1,-1 do items[i]=nil end
            for _,item in ipairs(fresh) do items[#items+1]=item end
        end
    end
    if menu.updateItems then menu:updateItems() end
end
function plugin:configMenu()
    return {
        {text_func=function() return T('Ativar neste livro','Enable for this book') end,
         checked_func=function() return self:enabledForBook() end,
         callback=function(menu)
             self:setBookEnabled(not self:enabledForBook())
             if menu then menu:updateItems() end
         end,keep_menu_open=true},
        {text_func=function() return T('Personalizar capitular','Customize drop cap') end,
         callback=function() self:openCustomizer() end,separator=true,keep_menu_open=false},
        {text_func=function()
             local v=self:current('detection')
             local label=v=='capitulos' and T('capítulos e subcapítulos','chapters and subchapters') or
                 (v=='seccoes' and T('secções','sections') or T('alargada','broad'))
             return T('Deteção: ','Detection: ')..label
         end,callback=function(menu) self:chooseDetection(menu) end,keep_menu_open=true},
    }
end
-- Registo nativo no menu principal do leitor (Ferramentas), sem inserção
-- em Tipografia ou nos ajustes do texto. Respeita a ordem de menus KOReader.
function plugin:addToMainMenu(menu_items)
    menu_items.capitulares={
        sorting_hint='tools', -- entrada direta em Ferramentas, não em Tipografia
        -- Símbolo Unicode padrão BLACK NIB (U+2712): pena de escrita, sem PUA/Nerd Fonts.
        -- Não exige instalar letras nem alterar o TouchMenu nativo.
        text_func=function()return '✒  Capitulares' end,
        sub_item_table_func=function()return self:configMenu()end,
    }
end
-- Never reapply the map in response to a CSS-triggered rerender.
-- The user may explicitly press Aplicar in the panel to remap after changing
-- KOReader font size or margins. Automatic rebuilds caused reload loops.
function plugin:onDocumentRerendered()
    if self._ci_screen_busy or not self:enabledForBook() or not self:screenMode() then return end
    if self._ci_screen_signature and self._ci_screen_signature~=screenmap.signature(self) then
        self._ci_screen_status='Disposição alterada: Aplicar recalcula as capitulares'
    end
end
function plugin:onCloseDocument()
    -- A cache must SURVIVE the full reload requested by CREngine.
    screenmap.cancel(self,true)
end
function plugin:onReaderReady()
    if self.style then
        if self:enabledForBook() and self:screenMode() and self._ci_screen_plan==nil then
            screenmap.request(self)
        end
        local cfg=self.ui.document and self.ui.document.configurable
        local lead=cfg and tonumber(cfg.line_spacing)
        if lead and lead>=75 and lead<=250 then self._ci_leading=lead/100 end
        UIManager:nextTick(function()
            -- Sem atribuir gestos se Gestures estiver indisponivel/desativado.
            require('capitulares_autogesture').install(self.ui and self.ui.gestures)
            auto.prewarm(fonts.list())
        end)
    end
end
function plugin:init()
    local doc=self.ui.document or self.document
    local file=doc and doc.file
    if type(file)~='string' or not file:lower():match('%.epub$') then return end
    local style=self.ui.styletweak
    if not style or type(style.updateCssText)~='function' then return end
    self.style=style
    self:onDispatcherRegisterActions()
    self.temporary={}
    self._ci_paragraphs_per_page=3
    self._ci_screen_plan=nil
    self._ci_screen_busy=nil
    self._ci_screen_generation=0
    self._ci_leading=1.2
    self._ci_font_metrics={height=0.88,width=0.88}
    self._ci_source_path=nil
    self._ci_invalid_font=false
    self._ci_source_index=0
    self._ci_active_name=nil
    self._ci_active_preferred=false
    self._ci_preview_profile=nil
    -- Restore the last page plan before ReaderStyleTweak generates the CSS
    -- for the first document render. This is what breaks the reload loop.
    if self:enabledForBook() and self:screenMode() then
        screenmap.restore(self)
    end
    local source=self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..'source')
        or G_reader_settings:readSetting(PREF..'font_source')
    if source then
        for _,rec in ipairs(fonts.list()) do
            if rec.name==source then
                if not fonts.usable(rec) then
                    self._ci_invalid_font=true
                    break
                end
                -- A selected CI2 face must be registered before this book's
                -- first render. Otherwise a delayed registration can make the
                -- initial disappear until the document is reopened.
                if self:enabledForBook() then
                    local face=self:prepareSelection(rec)
                    if face==nil then
                        self._ci_invalid_font=true -- fall back to book lettering
                    elseif self.ui.doc_settings:readSetting(BOOK_FONT_PREFIX..'source') then
                        self.ui.doc_settings:saveSetting(BOOK_FONT_PREFIX..'family',face)
                    end
                end
                self._ci_source_path=rec.path
                self._ci_source_index=rec.index or 0
                self._ci_active_name=rec.name
                self._ci_active_preferred=rec.preferred
                self._ci_font_metrics=geometry.measure(rec.path,rec.index)
                break
            end
        end
    end
    -- Retira qualquer pendente antigo: a selecao atual e direta, sem reboot.
    self.ui.doc_settings:delSetting('capitulares_v1_pending_font')
    -- Acrescenta CSS apenas à instância do livro aberto. Nunca modifica a classe.
    local original=style.updateCssText
    local host=self.ui
    style.updateCssText=function(instance,apply)
        local previous_css=instance.css_text
        original(instance,false)
        if self:enabledForBook() then
            instance.css_text=(instance.css_text or '')..'\n'..css.generate(self:options())
        end
        -- If the exact same CSS is already installed, do not ask KOReader
        -- to reapply it: that can provoke a stale-DOM reload confirmation.
        if apply and instance.css_text~=previous_css then
            host:handleEvent(Event:new('ApplyStyleSheet'))
        end
    end
    if self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end
return plugin
