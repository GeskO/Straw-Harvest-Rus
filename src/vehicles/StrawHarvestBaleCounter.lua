---
-- StrawHarvestBaleCounter
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Counts bales.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestBaleCounter
StrawHarvestBaleCounter = {}
StrawHarvestBaleCounter.MOD_NAME = g_currentModName

function StrawHarvestBaleCounter.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Baler, specializations)
end

function StrawHarvestBaleCounter.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setBalerCurrentBalesCount", StrawHarvestBaleCounter.setBalerCurrentBalesCount)
    SpecializationUtil.registerFunction(vehicleType, "getBalerCurrentBalesCount", StrawHarvestBaleCounter.getBalerCurrentBalesCount)
    SpecializationUtil.registerFunction(vehicleType, "setBalerLifetimeBalesCount", StrawHarvestBaleCounter.setBalerLifetimeBalesCount)
    SpecializationUtil.registerFunction(vehicleType, "getBalerLifetimeBalesCount", StrawHarvestBaleCounter.getBalerLifetimeBalesCount)
    SpecializationUtil.registerFunction(vehicleType, "resetBalerCurrentBalesCount", StrawHarvestBaleCounter.resetBalerCurrentBalesCount)
    SpecializationUtil.registerFunction(vehicleType, "canCountBales", StrawHarvestBaleCounter.canCountBales)
    SpecializationUtil.registerFunction(vehicleType, "isRoundBaler", StrawHarvestBaleCounter.isRoundBaler)
    SpecializationUtil.registerFunction(vehicleType, "onBaleDropped", StrawHarvestBaleCounter.onBaleDropped)
end

function StrawHarvestBaleCounter.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dropBale", StrawHarvestBaleCounter.dropBale)
end

function StrawHarvestBaleCounter.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestBaleCounter)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawHarvestBaleCounter)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestBaleCounter)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestBaleCounter)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", StrawHarvestBaleCounter)
end

function StrawHarvestBaleCounter:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_strawHarvestBaleCounter
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_RESET_BALE_COUNTER, self, StrawHarvestBaleCounter.actionEventResetBaleCount, false, true, false, true, nil)
            g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_resetBaleCounter"))
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_LOW)
        end
    end
end

---Called on load.
function StrawHarvestBaleCounter:onLoad(savegame)
    self.spec_strawHarvestBaleCounter = self[("spec_%s.strawHarvestBaleCounter"):format(StrawHarvestBaleCounter.MOD_NAME)]
    local spec = self.spec_strawHarvestBaleCounter

    spec.currentCount = 0
    spec.lifetimeCount = 0

    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. self:strawHarvest_getModName() .. ".strawHarvestBaleCounter"
        spec.currentCount = Utils.getNoNil(getXMLInt(savegame.xmlFile, key .. "#currentCount"), spec.currentCount)
        spec.lifetimeCount = Utils.getNoNil(getXMLInt(savegame.xmlFile, key .. "#lifetimeCount"), spec.lifetimeCount)
    end
end

function StrawHarvestBaleCounter:onReadStream(streamId, timestamp, connection)
    self:setBalerCurrentBalesCount(streamReadInt16(streamId))
    self:setBalerLifetimeBalesCount(streamReadInt16(streamId))
end

function StrawHarvestBaleCounter:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestBaleCounter
    streamWriteInt16(streamId, spec.currentCount)
    streamWriteInt16(streamId, spec.lifetimeCount)
end

function StrawHarvestBaleCounter:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestBaleCounter
    setXMLInt(xmlFile, key .. "#currentCount", spec.currentCount)
    setXMLInt(xmlFile, key .. "#lifetimeCount", spec.lifetimeCount)
end

---Called on update.
function StrawHarvestBaleCounter:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_strawHarvestBaleCounter

    if self.isClient then
        if spec.actionEvents ~= nil then
            local actionEvent = spec.actionEvents[InputAction.SH_RESET_BALE_COUNTER]
            if actionEvent ~= nil then
                g_inputBinding:setActionEventActive(actionEvent.actionEventId, spec.currentCount > 0)
            end
        end

        local hud = g_strawHarvest.baleCounterHud
        if self:getIsActiveForInput(true, true) then
            if self:getAttacherVehicle() == g_currentMission.controlledVehicle then
                if hud.vehicle ~= self then
                    hud:setVehicle(self)
                end
                hud:drawText()
            else
                if hud.vehicle == self then
                    hud:setVehicle(nil)
                end
            end
        else
            if hud.vehicle == self then
                hud:setVehicle(nil)
            end
        end
    end
end

function StrawHarvestBaleCounter:setBalerCurrentBalesCount(count)
    local spec = self.spec_strawHarvestBaleCounter
    spec.currentCount = math.max(0, count)
end

function StrawHarvestBaleCounter:getBalerCurrentBalesCount()
    return self.spec_strawHarvestBaleCounter.currentCount
end

function StrawHarvestBaleCounter:setBalerLifetimeBalesCount(count)
    local spec = self.spec_strawHarvestBaleCounter
    spec.lifetimeCount = math.max(0, count)
end

function StrawHarvestBaleCounter:getBalerLifetimeBalesCount()
    return self.spec_strawHarvestBaleCounter.lifetimeCount
end

function StrawHarvestBaleCounter:onBaleDropped(increment)
    local spec = self.spec_strawHarvestBaleCounter
    self:setBalerCurrentBalesCount(spec.currentCount + increment)
    self:setBalerLifetimeBalesCount(spec.lifetimeCount + increment)
end

function StrawHarvestBaleCounter:resetBalerCurrentBalesCount(noEventSend)
    if not noEventSend then
        g_client:getServerConnection():sendEvent(StrawHarvestResetBaleCountEvent:new(self))
    end

    self:setBalerCurrentBalesCount(0)
end

function StrawHarvestBaleCounter:canCountBales()
    return self.firstTimeRun and (self.spec_baler.balesToLoad == nil or #self.spec_baler.balesToLoad == 0)
end

function StrawHarvestBaleCounter:isRoundBaler()
    local baleType = self.spec_baler.baleTypes[self.spec_baler.currentBaleTypeId]
    return baleType.isRoundBale
end

function StrawHarvestBaleCounter:dropBale(superFunc, ...)
    if self:canCountBales() then
        self:onBaleDropped(1)
    end

    superFunc(self, ...)
end

-------------------
-- Action events --
-------------------

function StrawHarvestBaleCounter.actionEventResetBaleCount(self, ...)
    self:resetBalerCurrentBalesCount(false)
end