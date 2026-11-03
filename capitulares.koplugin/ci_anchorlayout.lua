-- Capitulares v1.0 — painel de definições fixo à direita.
-- Sem controlos ou gestos flutuantes sobre o texto do EPUB.
local InputContainer=require('ui/widget/container/inputcontainer')
local Geom=require('ui/geometry')
local Screen=require('device').screen
local M=InputContainer:extend{}
function M:init()
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local p=self.panel:getSize()
    self.panel_x=math.max(0,sw-p.w-Screen:scaleBySize(6))
    self.panel_y=math.max(0,math.floor((sh-p.h)/2))
    self.dimen=Geom:new{x=0,y=0,w=sw,h=sh}
    self[1]=self.panel
end
function M:onCloseWidget()
    -- Closing this anchored overlay must also invalidate the underlying book.
    -- The top-level reader repaints after this widget has been removed.
    local UIManager=require('ui/uimanager')
    UIManager:setDirty('all','ui')
end
function M:paintTo(bb,x,y)
    self.dimen=Geom:new{x=x,y=y,w=Screen:getWidth(),h=Screen:getHeight()}
    self.panel:paintTo(bb,x+self.panel_x,y+self.panel_y)
end
return M
