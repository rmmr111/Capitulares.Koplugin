-- Capitulares v1.0 / Teste 11: slider e-ink compacto, marcador grande.
-- Pan atualiza apenas o marcador. Repaginacao uma unica vez ao largar.
local InputContainer=require('ui/widget/container/inputcontainer')
local HorizontalGroup=require('ui/widget/horizontalgroup')
local VerticalGroup=require('ui/widget/verticalgroup')
local HorizontalSpan=require('ui/widget/horizontalspan')
local VerticalSpan=require('ui/widget/verticalspan')
local TextWidget=require('ui/widget/textwidget')
local Widget=require('ui/widget/widget')
local GestureRange=require('ui/gesturerange')
local Geom=require('ui/geometry')
local Font=require('ui/font')
local UIManager=require('ui/uimanager')
local Blitbuffer=require('ffi/blitbuffer')
local Screen=require('device').screen
local M=InputContainer:extend{}
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function label(txt,face) return TextWidget:new{text=txt,face=face} end
local Track=Widget:extend{}
function Track:getSize() return {w=self.width,h=self.height} end
function Track:paintTo(bb,x,y)
    local w,h=self.width,self.height
    local thick=math.max(2,Screen:scaleBySize(3))
    local ty=y+math.floor((h-thick)/2)
    local range=self.maximum-self.minimum
    local pc=range>0 and (self.current-self.minimum)/range or 0
    if self.inverted then pc=1-pc end
    local thumb=math.max(22,math.min(42,math.floor(h*0.88)))
    local cx=x+math.floor(thumb/2+pc*(w-thumb))
    -- Trilho estreito e tonalidades suaves, desenhados em e-ink nativo.
    if bb.paintRoundedRect then
        bb:paintRoundedRect(x,ty,w,thick,Blitbuffer.COLOR_LIGHT_GRAY,math.floor(thick/2))
    else
        bb:paintRect(x,ty,w,thick,Blitbuffer.COLOR_LIGHT_GRAY)
    end
    local progress=math.max(0,math.min(w,math.floor(cx-x)))
    if progress>0 then bb:paintRect(x,ty,progress,thick,Blitbuffer.COLOR_GRAY) end
    -- Anel, sem o antigo marcador rectangular com contorno grosso.
    local cy=y+math.floor(h/2)
    local r=math.max(8,math.floor(thumb*0.44))
    if bb.paintCircle then
        bb:paintCircle(cx,cy,r,Blitbuffer.COLOR_BLACK)
        bb:paintCircle(cx,cy,r-2,Blitbuffer.COLOR_WHITE)
    else
        bb:paintRect(cx-r,cy-r,2*r,2*r,Blitbuffer.COLOR_WHITE)
        bb:paintBorder(cx-r,cy-r,2*r,2*r,1,Blitbuffer.COLOR_BLACK)
    end
    self.dimen=Geom:new{x=x,y=y,w=w,h=h}
end
function M:init()
    self.minimum=assert(tonumber(self.minimum))
    self.maximum=assert(tonumber(self.maximum))
    assert(self.maximum>self.minimum)
    self.value=clamp(tonumber(self.value) or self.minimum,self.minimum,self.maximum)
    self.step=math.max(1,tonumber(self.step) or 1)
    self.width=assert(tonumber(self.width))
    local small=Font:getFace('cfont',15)
    local normal=Font:getFace('cfont',20)
    local headingTitle=label(self.title or '',normal)
    local headingValue=label(self.value_text or (tostring(self.value)..' px'),normal)
    local gap=math.max(4,self.width-headingTitle:getSize().w-headingValue:getSize().w)
    self.heading=HorizontalGroup:new{allow_mirroring=false,
        headingTitle,HorizontalSpan:new{width=gap},headingValue}
    self.track=Track:new{width=self.width,height=Screen:scaleBySize(28),
        minimum=self.minimum,maximum=self.maximum,current=self.value,inverted=self.inverted}
    local left=label(self.left_text or '',small)
    local right=label(self.right_text or '',small)
    local between=math.max(0,self.width-left:getSize().w-right:getSize().w)
    local dirs=HorizontalGroup:new{allow_mirroring=false,left,
        HorizontalSpan:new{width=between},right}
    self[1]=VerticalGroup:new{align='left',
        self.heading,VerticalSpan:new{width=Screen:scaleBySize(2)},
        self.track,VerticalSpan:new{width=Screen:scaleBySize(1)},
        dirs,VerticalSpan:new{width=Screen:scaleBySize(5)},
    }
    self.dimen=Geom:new{x=0,y=0,w=self.width,h=self[1]:getSize().h}
    self.ges_events={
        TapSlider={GestureRange:new{ges='tap',range=self.dimen}},
        SwipeSlider={GestureRange:new{ges='swipe',range=self.dimen}},
        PanSlider={GestureRange:new{ges='pan',range=self.dimen}},
        PanReleaseSlider={GestureRange:new{ges='pan_release',range=self.dimen}},
        HoldSlider={GestureRange:new{ges='hold',range=self.dimen}},
    }
end
function M:_read(ges)
    local pos=ges and ges.pos or nil
    if not (pos and self.track and self.track.dimen) then return nil end
    local d=self.track.dimen
    local hit=Screen:scaleBySize(10)
    if pos.y < d.y-hit or pos.y > d.y+d.h+hit then return nil end
    local thumb=math.max(22,math.min(42,math.floor(d.h*0.88)))
    local f=clamp((pos.x-d.x-thumb/2)/math.max(1,d.w-thumb),0,1)
    if self.inverted then f=1-f end
    local val=self.minimum+f*(self.maximum-self.minimum)
    return clamp(math.floor(val/self.step+0.5)*self.step,self.minimum,self.maximum)
end
function M:_commit(ges)
    local v=self:_read(ges)
    if v==nil then return false end
    self.track.current=v
    if v~=self.value and self.on_change then
        self.value=v
        self.on_change(v)
    end
    return true
end
function M:onTapSlider(_,ges) return self:_commit(ges) end
function M:onSwipeSlider(_,ges) return self:_commit(ges) end
function M:onPanReleaseSlider(_,ges) return self:_commit(ges) end
function M:onPanSlider(_,ges)
    local v=self:_read(ges)
    if v==nil then return false end
    if v~=self.track.current then
        self.track.current=v
        if self.show_parent then
            UIManager:setDirty(self.show_parent,'fast',self.track.dimen)
        end
    end
    return true
end
function M:onHoldSlider(_,ges)
    local pos=ges and ges.pos
    if self.on_exact and pos and self.dimen and
       pos.x>=self.dimen.x and pos.x<=self.dimen.x+self.dimen.w and
       pos.y>=self.dimen.y and pos.y<=self.dimen.y+self.dimen.h then
        self.on_exact()
        return true
    end
    return false
end
return M
