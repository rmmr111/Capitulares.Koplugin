-- Capitulares v1.0: atribuicao unica, condicional e nao invasiva.
-- Usa o estado VIVO do plugin Gestures. Nunca reescreve diretamente gestures.lua.
local M={}
local MARK='capitulares_v1_auto_corner_checked'
local CORNER='hold_top_left_corner'
local ACTION='capitulares_open_panel'
function M.install(gestures)
    if not G_reader_settings or G_reader_settings:readSetting(MARK) then return 'already_checked' end
    if type(gestures)~='table' or type(gestures.gestures)~='table' or
       type(gestures.settings)~='table' or
       type(gestures.settings.flush)~='function' or
       gestures.ges_mode~='gesture_reader' then
        return 'unavailable' -- tentar na abertura de outro livro, sem escrever flag
    end
    -- Se a deteccao de hold nos cantos estiver desligada, respeitar a opcao.
    if G_reader_settings:isTrue('ignore_hold_corners') or gestures.ignore_hold_corners then
        G_reader_settings:saveSetting(MARK,true)
        return 'disabled'
    end
    -- nil = sem acao; uma tabela vazia pode representar uma escolha
    -- intencional do utilizador. Nunca alterar entradas existentes.
    if gestures.gestures[CORNER]~=nil then
        G_reader_settings:saveSetting(MARK,true)
        return 'occupied'
    end
    local mapping={[ACTION]=true}
    gestures.gestures[CORNER]=mapping
    gestures.updated=true
    -- A tabela viva pertence a Gestures.settings.data; gravar com a API
    -- nativa assegura que o mapeamento persiste num reinicio.
    local ok,err=pcall(gestures.settings.flush,gestures.settings)
    if not ok then
        gestures.gestures[CORNER]=nil
        return 'flush_failed'
    end
    G_reader_settings:saveSetting(MARK,true)
    return 'assigned'
end
return M
