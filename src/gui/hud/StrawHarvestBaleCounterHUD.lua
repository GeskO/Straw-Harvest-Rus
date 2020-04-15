---
-- StrawHarvestBaleCounterHUD
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: HUD to display the current bales.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestBaleCounterHUD
StrawHarvestBaleCounterHUD = {}

local StrawHarvestBaleCounterHUD_mt = Class(StrawHarvestBaleCounterHUD)

---Creates a new instance of the StrawHarvestBaleCounterHUD.
---@return StrawHarvestBaleCounterHUD
function StrawHarvestBaleCounterHUD:new(strawHarvest, fillLevelDisplay)
    local instance = setmetatable({}, StrawHarvestBaleCounterHUD_mt)

    instance.fillLevelDisplay = fillLevelDisplay

    local modDir = strawHarvest.modDirectory
    instance.iconCurrentSquareBales = Utils.getFilename("resources/hud/baleCounterTodaySquarebales.png", modDir)
    instance.iconLifeTimeSquareBales = Utils.getFilename("resources/hud/baleCounterLifetimeSquarebales.png", modDir)
    instance.iconCurrentRoundBales = Utils.getFilename("resources/hud/baleCounterTodayRoundbales.png", modDir)
    instance.iconLifeTimeRoundBales = Utils.getFilename("resources/hud/baleCounterLifetimeRoundbales.png", modDir)

    instance.currentBaleCountText = "0"
    instance.lifeTimeBaleCountText = "0"
    instance.vehicle = nil
    instance.isVehicleDrawSafe = false
    instance.isRoundBaler = false

    return instance
end

function StrawHarvestBaleCounterHUD:delete()
    if self.currentBalesIcon ~= nil then
        self.currentBalesIcon:delete()
    end

    if self.lifetimeBalesIcon ~= nil then
        self.lifetimeBalesIcon:delete()
    end
end

function StrawHarvestBaleCounterHUD:load()
    self:createElements()
end

function StrawHarvestBaleCounterHUD:drawText()
    if self:getCanRender() then
        if self.currentBalesIcon ~= nil then
            local baseX, baseY = self.currentBalesIcon:getPosition()
            local width = self.currentBalesIcon:getWidth()

            setTextBold(false)
            setTextColor(unpack(GameInfoDisplay.COLOR.TEXT))
            setTextAlignment(RenderText.ALIGN_RIGHT)

            self.currentBaleCountText = tostring(self.vehicle:getBalerCurrentBalesCount())
            renderText(baseX + width + self.textXOffset, baseY, self.textSize, self.currentBaleCountText)
        end

        if self.lifetimeBalesIcon ~= nil then
            local baseX, baseY = self.lifetimeBalesIcon:getPosition()
            local width = self.lifetimeBalesIcon:getWidth()

            setTextBold(false)
            setTextColor(unpack(GameInfoDisplay.COLOR.TEXT))
            setTextAlignment(RenderText.ALIGN_RIGHT)

            self.lifeTimeBaleCountText = tostring(self.vehicle:getBalerLifetimeBalesCount())
            renderText(baseX + width + self.textXOffset, baseY, self.textSize, self.lifeTimeBaleCountText)
        end
    end

    self.isVehicleDrawSafe = true
end

function StrawHarvestBaleCounterHUD:getCanRender()
    return self.vehicle ~= nil
            and self.fillLevelDisplay:getVisible()
            and self.currentBalesIcon:getVisible()
            and self.lifetimeBalesIcon:getVisible()
            and self.isVehicleDrawSafe
            and not g_gui:getIsGuiVisible()
end

function StrawHarvestBaleCounterHUD:setVehicle(vehicle)
    self.vehicle = vehicle

    local setVisible = vehicle ~= nil

    if setVisible then
        local isRoundBaler = vehicle:isRoundBaler()
        if isRoundBaler ~= self.isRoundBaler then
            self.isRoundBaler = isRoundBaler
            self.currentBalesIcon:setImage(isRoundBaler and self.iconCurrentRoundBales or self.iconCurrentSquareBales)
            self.lifetimeBalesIcon:setImage(isRoundBaler and self.iconLifeTimeRoundBales or self.iconLifeTimeSquareBales)
        end
    end

    self.currentBalesIcon:setVisible(setVisible)
    self.lifetimeBalesIcon:setVisible(setVisible)

    self.isVehicleDrawSafe = false
end

function StrawHarvestBaleCounterHUD:getVehicle()
    return self.vehicle
end

function StrawHarvestBaleCounterHUD:createElements()
    local baseX, baseY = self.fillLevelDisplay:getPosition()

    self.textSize = self.fillLevelDisplay:scalePixelToScreenHeight(HUDElement.TEXT_SIZE.DEFAULT_TEXT)
    self.textXOffset, self.textYOffset = self.fillLevelDisplay:scalePixelToScreenVector(StrawHarvestBaleCounterHUD.POSITION.TEXT)

    self.currentBalesIcon = self:createIcon(self.iconCurrentSquareBales, baseX, baseY, StrawHarvestBaleCounterHUD.POSITION.CURRENT, StrawHarvestBaleCounterHUD.SIZE.CURRENT)
    self.lifetimeBalesIcon = self:createIcon(self.iconLifeTimeSquareBales, baseX, baseY, StrawHarvestBaleCounterHUD.POSITION.LIFETIME, StrawHarvestBaleCounterHUD.SIZE.LIFETIME)
end

function StrawHarvestBaleCounterHUD:createIcon(imagePath, baseX, baseY, position, size)
    local posX, posY = self.fillLevelDisplay:scalePixelToScreenVector(position)
    local width, height = self.fillLevelDisplay:scalePixelToScreenVector(size)

    baseY = baseY - height

    local iconOverlay = Overlay:new(imagePath, baseX + posX, baseY - posY, width, height)
    local element = HUDElement:new(iconOverlay)

    self.fillLevelDisplay:addChild(element)
    element:setVisible(false)

    return element
end

StrawHarvestBaleCounterHUD.POSITION = {
    CURRENT = { -5, 10 },
    LIFETIME = { 45, 10 },
    TEXT = { 10, 10 }

}

StrawHarvestBaleCounterHUD.SIZE = {
    CURRENT = { 35, 35 },
    LIFETIME = { 35, 35 }
}
