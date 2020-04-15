---
-- StrawHarvestVariableBaleSizeBaler
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Allows variable bale sizes.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestVariableBaleSizeBaler
StrawHarvestVariableBaleSizeBaler = {}
StrawHarvestVariableBaleSizeBaler.MOD_NAME = g_currentModName

StrawHarvestVariableBaleSizeBaler.INITIAL_SIZE_INDEX = 1
StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS = 3 -- 2 ^ 3 = 8

function StrawHarvestVariableBaleSizeBaler.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Baler, specializations)
end

function StrawHarvestVariableBaleSizeBaler.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getBaleSize", StrawHarvestVariableBaleSizeBaler.getBaleSize)
    SpecializationUtil.registerFunction(vehicleType, "isBaleSizeSwitchAllowed", StrawHarvestVariableBaleSizeBaler.isBaleSizeSwitchAllowed)
    SpecializationUtil.registerFunction(vehicleType, "getNextBaleSizeUnitIndex", StrawHarvestVariableBaleSizeBaler.getNextBaleSizeUnitIndex)
    SpecializationUtil.registerFunction(vehicleType, "getBaleSizeUnit", StrawHarvestVariableBaleSizeBaler.getBaleSizeUnit)
    SpecializationUtil.registerFunction(vehicleType, "setBaleSizeUnit", StrawHarvestVariableBaleSizeBaler.setBaleSizeUnit)
    SpecializationUtil.registerFunction(vehicleType, "updateCurrentBale", StrawHarvestVariableBaleSizeBaler.updateCurrentBale)
    SpecializationUtil.registerFunction(vehicleType, "loadBaleUnitFromXML", StrawHarvestVariableBaleSizeBaler.loadBaleUnitFromXML)
end

function StrawHarvestVariableBaleSizeBaler.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setIsUnloadingBale", StrawHarvestVariableBaleSizeBaler.setIsUnloadingBale)
end

function StrawHarvestVariableBaleSizeBaler.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestVariableBaleSizeBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", StrawHarvestVariableBaleSizeBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestVariableBaleSizeBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestVariableBaleSizeBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", StrawHarvestVariableBaleSizeBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onFillUnitFillLevelChanged", StrawHarvestVariableBaleSizeBaler)
end

function StrawHarvestVariableBaleSizeBaler:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_strawHarvestVariableBaleSizeBaler
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionDropEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_TOGGLE_BALE_SIZE, self, StrawHarvestVariableBaleSizeBaler.actionEventToggleBaleSize, false, true, false, true, nil)

            g_inputBinding:setActionEventText(actionDropEventId, g_i18n:getText("action_baleUnitSize"):format(self:getBaleSize(spec.currentBaleSizeUnitIndex)))
            g_inputBinding:setActionEventTextPriority(actionDropEventId, GS_PRIO_NORMAL)
        end
    end
end

---Called on load.
function StrawHarvestVariableBaleSizeBaler:onLoad(savegame)
    self.spec_strawHarvestVariableBaleSizeBaler = self[("spec_%s.strawHarvestVariableBaleSizeBaler"):format(StrawHarvestVariableBaleSizeBaler.MOD_NAME)]
    local spec = self.spec_strawHarvestVariableBaleSizeBaler

    spec.fillUnitIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.baleSize#fillUnitIndex"), 1)
    spec.growAnimationName = getXMLString(self.xmlFile, "vehicle.baleSize#growAnimationName")
    spec.pressureNeedleAnimationName = getXMLString(self.xmlFile, "vehicle.baleSize#pressureNeedleAnimationName")
    spec.baleSizeUnits = {}
    spec.baleSizeCapacities = {}
    spec.currentBaleSizeUnitIndex = 0 -- in sync with baler spec.

    local i = 0
    while i <= 2 ^ StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS do
        local key = ("vehicle.baleSize.units.unit(%d)"):format(i)

        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        if #spec.baleSizeUnits == 2 ^ StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS then
            g_logManager:xmlError(self.configFileName, "Max amount of bale sizes reached!")
            break
        end

        local unit = {}
        if self:loadBaleUnitFromXML(unit, self.xmlFile, key) then
            table.insert(spec.baleSizeUnits, unit)
            table.insert(spec.baleSizeCapacities, unit.capacity)
        end

        i = i + 1
    end

    spec.maxBaleSizeCapacity = math.max(unpack(spec.baleSizeCapacities))
end

function StrawHarvestVariableBaleSizeBaler:onPostLoad(savegame)
    local index = StrawHarvestVariableBaleSizeBaler.INITIAL_SIZE_INDEX
    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. self:strawHarvest_getModName() .. ".strawHarvestVariableBaleSizeBaler"
        index = Utils.getNoNil(getXMLInt(savegame.xmlFile, key .. "#currentBaleSizeUnitIndex"), index)
    end

    self:setBaleSizeUnit(index, true)
end

function StrawHarvestVariableBaleSizeBaler:onReadStream(streamId, timestamp, connection)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    local index = streamReadUIntN(streamId, StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS) + 1
    self:setBaleSizeUnit(index, true)
    local unit = self:getBaleSizeUnit(spec.currentBaleSizeUnitIndex)
    self:setAnimationTime(unit.baleGuideAnimationName, streamReadFloat32(streamId))
end

function StrawHarvestVariableBaleSizeBaler:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    streamWriteUIntN(streamId, spec.currentBaleSizeUnitIndex - 1, StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS)
    local unit = self:getBaleSizeUnit(spec.currentBaleSizeUnitIndex)
    streamWriteFloat32(streamId, self:getRealAnimationTime(unit.baleGuideAnimationName))
end

function StrawHarvestVariableBaleSizeBaler:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    setXMLInt(xmlFile, key .. "#currentBaleSizeUnitIndex", spec.currentBaleSizeUnitIndex)
end

---Returns true when the fill level is smaller than the next capacity, false otherwise.
function StrawHarvestVariableBaleSizeBaler:isBaleSizeSwitchAllowed()
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    local fillLevel = self:getFillUnitFillLevel(spec.fillUnitIndex)
    local nextUnitIndex = self:getNextBaleSizeUnitIndex(spec.currentBaleSizeUnitIndex)
    local nextUnitCapacity = spec.baleSizeCapacities[nextUnitIndex]

    return fillLevel <= nextUnitCapacity
end

---Gets the bale size at the given index.
function StrawHarvestVariableBaleSizeBaler:getBaleSize(index)
    local unit = self:getBaleSizeUnit(index)
    local type = self.spec_baler.baleTypes[unit.baleTypeIndex]
    return type.isRoundBale and type.diameter or type.length
end

---Gets the next valid bale size units table index.
function StrawHarvestVariableBaleSizeBaler:getNextBaleSizeUnitIndex(index)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler

    local nextUnitIndex = index + 1
    if nextUnitIndex > #spec.baleSizeUnits then
        nextUnitIndex = StrawHarvestVariableBaleSizeBaler.INITIAL_SIZE_INDEX
    end

    local capacity = spec.baleSizeCapacities[nextUnitIndex]
    local fillLevel = self:getFillUnitFillLevel(spec.fillUnitIndex)
    if capacity < fillLevel then
        return self:getNextBaleSizeUnitIndex(nextUnitIndex)
    end

    return nextUnitIndex
end

---Gets the bale size unit at the given unit.
function StrawHarvestVariableBaleSizeBaler:getBaleSizeUnit(index)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    return spec.baleSizeUnits[index]
end

---Sets the current bale size index and updates the baler spec upon that.
function StrawHarvestVariableBaleSizeBaler:setBaleSizeUnit(index, noEventSend)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    if spec.currentBaleSizeUnitIndex ~= index then
        StrawHarvestVariableBaleSizeEvent.sendEvent(self, index, noEventSend)

        spec.currentBaleSizeUnitIndex = index

        local unit = self:getBaleSizeUnit(index)
        self:setFillUnitCapacity(spec.fillUnitIndex, unit.capacity)
        self.spec_baler.currentBaleTypeId = unit.baleTypeIndex

        self:updateCurrentBale(unit)

        local actionEvent = spec.actionEvents[InputAction.SH_TOGGLE_BALE_SIZE]
        if actionEvent ~= nil then
            g_inputBinding:setActionEventText(actionEvent.actionEventId, g_i18n:getText("action_baleUnitSize"):format(self:getBaleSize(spec.currentBaleSizeUnitIndex)))
        end
    end
end

function StrawHarvestVariableBaleSizeBaler:updateCurrentBale(unit)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    local fillLevel = self:getFillUnitFillLevel(spec.fillUnitIndex)

    -- Recreate bale when the bale has been removed when switching between bale sizes.
    if fillLevel == unit.capacity then
        if self.isServer then
            self:finishBale()
        end
    else
        -- Remove current bales in the camber.
        for i, bale in ipairs(self.spec_baler.bales) do
            if bale.id ~= nil and entityExists(bale.id) then
                delete(bale.id)
                bale.id = nil
                g_i3DManager:releaseSharedI3DFile(bale.filename, nil, true)
            end
            table.remove(self.spec_baler.bales, i)
        end
    end
end

function StrawHarvestVariableBaleSizeBaler:loadBaleUnitFromXML(unit, xmlFile, key)
    unit.baleTypeIndex = Utils.getNoNil(getXMLInt(xmlFile, key .. "#baleTypeIndex"), 1)
    unit.capacity = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#capacity"), math.huge)
    unit.baleGuideAnimationName = getXMLString(xmlFile, key .. "#baleGuideAnimationName")

    return true
end

function StrawHarvestVariableBaleSizeBaler:onFillUnitFillLevelChanged(fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler

    if fillUnitIndex == spec.fillUnitIndex then
        local capacity = self:getFillUnitCapacity(fillUnitIndex)
        local fillLevel = self:getFillUnitFillLevel(fillUnitIndex)
        local animationTime = fillLevel / capacity * (capacity / spec.maxBaleSizeCapacity)
        if spec.growAnimationName ~= nil and fillLevel < capacity and fillLevel > 0 then
            -- When bale chamber is full, our baleGuideAnim takes over the bale
            self:setAnimationTime(spec.growAnimationName, animationTime, true)
        end

        if spec.pressureNeedleAnimationName ~= nil then
            self:setAnimationTime(spec.pressureNeedleAnimationName, animationTime, true)
        end
    end
end

----------------
-- Overwrites --
----------------

function StrawHarvestVariableBaleSizeBaler:setIsUnloadingBale(superFunc, isUnloadingBale, noEventSend)
    superFunc(self, isUnloadingBale, noEventSend)

    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    local specBaler = self.spec_baler

    if isUnloadingBale and specBaler.unloadingState == Baler.UNLOADING_OPENING then
        local unit = self:getBaleSizeUnit(spec.currentBaleSizeUnitIndex)
        self:playAnimation(unit.baleGuideAnimationName, specBaler.baleUnloadAnimationSpeed, 0, true)
    end
end

-------------------
-- Action events --
-------------------

function StrawHarvestVariableBaleSizeBaler.actionEventToggleBaleSize(self, ...)
    local spec = self.spec_strawHarvestVariableBaleSizeBaler
    local index = self:getNextBaleSizeUnitIndex(spec.currentBaleSizeUnitIndex)

    if self:isBaleSizeSwitchAllowed() then
        if self.spec_baler.unloadingState == Baler.UNLOADING_CLOSED then
            self:setBaleSizeUnit(index)
        end
    else
        local size = self:getBaleSize(index)
        g_currentMission:showBlinkingWarning(g_i18n:getText("warning_baleTooSmall"):format(size), 2000)
    end
end
