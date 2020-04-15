---
-- StrawHarvestRefillSupplies
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Allow refilling of supplies like twine and netting.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestRefillSupplies
StrawHarvestRefillSupplies = {}
StrawHarvestRefillSupplies.MOD_NAME = g_currentModName

function StrawHarvestRefillSupplies.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations)
            and SpecializationUtil.hasSpecialization(AnimatedVehicle, specializations)
end

function StrawHarvestRefillSupplies.initSpecialization()
    g_configurationManager:addConfigurationType("refillSupplies", g_i18n:getText("configuration_refillSupplies"), nil, nil, nil, nil, ConfigurationUtil.SELECTOR_MULTIOPTION)
end

function StrawHarvestRefillSupplies.registerEvents(vehicleType)
    SpecializationUtil.registerEvent(vehicleType, "onCoverStateChanged")
end

function StrawHarvestRefillSupplies.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setIsRefillCoverOpen", StrawHarvestRefillSupplies.setIsRefillCoverOpen)
    SpecializationUtil.registerFunction(vehicleType, "isRefillCoverOpen", StrawHarvestRefillSupplies.isRefillCoverOpen)
    SpecializationUtil.registerFunction(vehicleType, "loadSupplyFromXML", StrawHarvestRefillSupplies.loadSupplyFromXML)
    SpecializationUtil.registerFunction(vehicleType, "setRefillSupplyAnimationTime", StrawHarvestRefillSupplies.setRefillSupplyAnimationTime)
end

function StrawHarvestRefillSupplies.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitTrigger", StrawHarvestRefillSupplies.addFillUnitTrigger)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", StrawHarvestRefillSupplies.getCanBeTurnedOn)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getTurnedOnNotAllowedWarning", StrawHarvestRefillSupplies.getTurnedOnNotAllowedWarning)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "createBale", StrawHarvestRefillSupplies.createBale)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getDrawFirstFillText", StrawHarvestRefillSupplies.getDrawFirstFillText)
end

function StrawHarvestRefillSupplies.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onCoverStateChanged", StrawHarvestRefillSupplies)
    SpecializationUtil.registerEventListener(vehicleType, "onFillUnitFillLevelChanged", StrawHarvestRefillSupplies)
end

function StrawHarvestRefillSupplies:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_strawHarvestRefillSupplies
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionDropEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_TOGGLE_REFILL_COVER, self, StrawHarvestRefillSupplies.actionEventToggleCover, false, true, false, true, nil)
            local text = spec.isCoverOpen and spec.closeCoverText or spec.openCoverText
            g_inputBinding:setActionEventText(actionDropEventId, g_i18n:getText(text))
            g_inputBinding:setActionEventTextPriority(actionDropEventId, GS_PRIO_NORMAL)
        end
    end
end

---Called on load.
function StrawHarvestRefillSupplies:onLoad(savegame)
    self.spec_strawHarvestRefillSupplies = self[("spec_%s.strawHarvestRefillSupplies"):format(StrawHarvestRefillSupplies.MOD_NAME)]
    local spec = self.spec_strawHarvestRefillSupplies

    spec.fillTriggerDetectedWhileClosed = {}

    spec.isBaler = SpecializationUtil.hasSpecialization(Baler, self.specializations)
    spec.isCoverOpen = false

    local configurationId = Utils.getNoNil(self.configurations["refillSupplies"], 1)
    local baseKey = ("vehicle.refillSuppliesConfigurations.refillSuppliesConfiguration(%d)"):format(configurationId - 1)
    ObjectChangeUtil.updateObjectChanges(self.xmlFile, "vehicle.refillSuppliesConfigurations.refillSuppliesConfiguration", configurationId, self.components, self)

    -- Fallback key
    if not hasXMLProperty(self.xmlFile, baseKey) then
        baseKey = "vehicle"
    end

    spec.supplies = {}
    local i = 0
    while true do
        local key = ("%s.refillSupplies.refillSupply(%d)"):format(baseKey, i)

        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local supply = {}
        if self:loadSupplyFromXML(supply, self.xmlFile, key) then
            table.insert(spec.supplies, supply)
        end

        i = i + 1
    end

    spec.hasCover = Utils.getNoNil(getXMLBool(self.xmlFile, baseKey .. ".refillSupplies#hasCover"), true)
    spec.isActive = Utils.getNoNil(getXMLBool(self.xmlFile, baseKey .. ".refillSupplies#isActive"), true)
    spec.coverAnimationName = getXMLString(self.xmlFile, baseKey .. ".refillSupplies#coverAnimationName")
    spec.openCoverText = Utils.getNoNil(getXMLString(self.xmlFile, baseKey .. ".refillSupplies#openCoverText"), "action_openBaleNetDoor")
    spec.closeCoverText = Utils.getNoNil(getXMLString(self.xmlFile, baseKey .. ".refillSupplies#closeCoverText"), "action_closeBaleNetDoor")
    spec.coverWarningText = getXMLString(self.xmlFile, baseKey .. ".refillSupplies#coverWarningText")
end

function StrawHarvestRefillSupplies:onPostLoad(savegame)
    local spec = self.spec_strawHarvestRefillSupplies

    for _, supply in ipairs(spec.supplies) do
        if spec.isActive then
            self:setRefillSupplyAnimationTime(supply)
        end

        local fillUnit = self:getFillUnitByIndex(supply.fillUnitIndex)
        fillUnit.showOnHud = spec.isActive
    end

    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. self:strawHarvest_getModName() .. ".strawHarvestRefillSupplies"
        local isCoverOpen = Utils.getNoNil(getXMLBool(savegame.xmlFile, key .. "#isCoverOpen"), spec.isCoverOpen)
        self:setIsRefillCoverOpen(isCoverOpen, true)
    end
end

function StrawHarvestRefillSupplies:onReadStream(streamId, timestamp, connection)
    self:setIsRefillCoverOpen(streamReadBool(streamId), true)
end

function StrawHarvestRefillSupplies:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestRefillSupplies
    streamWriteBool(streamId, spec.isCoverOpen)
end

function StrawHarvestRefillSupplies:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestRefillSupplies
    setXMLBool(xmlFile, key .. "#isCoverOpen", spec.isCoverOpen)
end

function StrawHarvestRefillSupplies:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_strawHarvestRefillSupplies

    if self.isClient then
        if spec.actionEvents ~= nil then
            local actionEvent = spec.actionEvents[InputAction.SH_TOGGLE_REFILL_COVER]
            if actionEvent ~= nil then
                g_inputBinding:setActionEventActive(actionEvent.actionEventId, spec.hasCover and not self:getIsTurnedOn())
            end
        end
    end
end

function StrawHarvestRefillSupplies:onCoverStateChanged(isCoverOpen)
    local spec = self.spec_strawHarvestRefillSupplies
    local spec_fillUnit = self.spec_fillUnit
    local mission = g_currentMission

    if not isCoverOpen then
        mission:removeActivatableObject(spec_fillUnit.fillTrigger.activatable)

        if self.isServer and spec_fillUnit.fillTrigger.currentTrigger ~= nil then
            self:setFillUnitIsFilling(false)
        end
    else
        for _, desc in ipairs(spec.fillTriggerDetectedWhileClosed) do
            self:addFillUnitTrigger(desc.trigger, desc.fillTypeIndex, desc.fillUnitIndex)
        end

        spec.fillTriggerDetectedWhileClosed = {}
        mission:removeActivatableObject(spec_fillUnit.fillTrigger.activatable)
        mission:addActivatableObject(spec_fillUnit.fillTrigger.activatable)
    end
end

function StrawHarvestRefillSupplies:onFillUnitFillLevelChanged(fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData, appliedDelta)
    local spec = self.spec_strawHarvestRefillSupplies

    if spec.isActive then
        for _, supply in ipairs(spec.supplies) do
            -- Consume supplies
            if fillLevelDelta > 0 then
                if supply.sourceFillUnitIndex ~= nil and supply.sourceFillUnitIndex == fillUnitIndex then
                    self:addFillUnitFillLevel(self:getOwnerFarmId(), supply.fillUnitIndex, -fillLevelDelta * supply.usagePerLiter, self:getFillUnitFirstSupportedFillType(supply.fillUnitIndex), ToolType.UNDEFINED, nil)
                end
            end

            if fillUnitIndex == supply.fillUnitIndex then
                self:setRefillSupplyAnimationTime(supply)

                if self:getFillUnitFillLevel(supply.fillUnitIndex) <= 0 then
                    self:setIsTurnedOn(false)
                end
            end
        end
    end
end

---Returns true when the cover is open, false otherwise.
function StrawHarvestRefillSupplies:isRefillCoverOpen()
    return self.spec_strawHarvestRefillSupplies.isCoverOpen
end

---Sets the cover state and raises the event.
function StrawHarvestRefillSupplies:setIsRefillCoverOpen(state, noEventSend)
    local spec = self.spec_strawHarvestRefillSupplies
    if spec.hasCover and spec.isCoverOpen ~= state then
        StrawHarvestCoverEvent.sendEvent(self, state, noEventSend)

        if spec.coverAnimationName ~= nil then
            local dir = state and 1 or -1
            self:playAnimation(spec.coverAnimationName, dir, nil, true)
        end

        local actionEvent = spec.actionEvents[InputAction.SH_TOGGLE_REFILL_COVER]
        if actionEvent ~= nil then
            local text = state and spec.closeCoverText or spec.openCoverText
            g_inputBinding:setActionEventText(actionEvent.actionEventId, g_i18n:getText(text))
        end

        spec.isCoverOpen = state

        SpecializationUtil.raiseEvent(self, "onCoverStateChanged", state)
    end
end

---Sets the animation time based on the fill level factor, if the animation is presents.
function StrawHarvestRefillSupplies:setRefillSupplyAnimationTime(supply)
    if supply.usageAnimationName ~= nil then
        local fillLevel = self:getFillUnitFillLevel(supply.fillUnitIndex)
        local animationTime = 1 - (fillLevel / self:getFillUnitCapacity(supply.fillUnitIndex))
        self:setAnimationTime(supply.usageAnimationName, animationTime, true)
    end
end

---Loads the supply from the XML.
function StrawHarvestRefillSupplies:loadSupplyFromXML(supply, xmlFile, key)
    supply.sourceFillUnitIndex = getXMLInt(xmlFile, key .. "#sourceFillUnitIndex")
    supply.fillUnitIndex = Utils.getNoNil(getXMLInt(xmlFile, key .. "#fillUnitIndex"), 1)

    supply.usageAnimationName = getXMLString(xmlFile, key .. "#usageAnimationName")
    supply.usagePerLiter = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#usagePerLiter"), 0)
    supply.usageFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#usageFactor"), 1)

    return true
end

----------------
-- Overwrites --
----------------

---Handle fill triggers that are detected by the collision when the cover is closed.
function StrawHarvestRefillSupplies:addFillUnitTrigger(superFunc, trigger, fillTypeIndex, fillUnitIndex)
    local spec = self.spec_strawHarvestRefillSupplies
    if spec.hasCover and not self:isRefillCoverOpen() then
        local entry = { trigger = trigger, fillTypeIndex = fillTypeIndex, fillUnitIndex = fillUnitIndex }
        if not ListUtil.hasListElement(spec.fillTriggerDetectedWhileClosed, entry) then
            ListUtil.addElementToList(spec.fillTriggerDetectedWhileClosed, entry)
        end

        -- Make sure to remove the trigger if not already added.
        self:removeFillUnitTrigger(trigger)

        return
    end

    return superFunc(self, trigger, fillTypeIndex, fillUnitIndex)
end

---Overwrites the can be turned on check on the current cover state.
---Returns false when cover is open, true otherwise.
function StrawHarvestRefillSupplies:getCanBeTurnedOn(superFunc)
    local spec = self.spec_strawHarvestRefillSupplies
    if spec.hasCover and self:isRefillCoverOpen() then
        return false
    end

    if spec.isActive then
        for _, supply in ipairs(spec.supplies) do
            if self:getFillUnitFillLevel(supply.fillUnitIndex) <= 0 then
                return false
            end
        end
    end

    return superFunc(self)
end

---Returns cover warning text when the player try's to turn on the vehicle while the cover is open.
function StrawHarvestRefillSupplies:getTurnedOnNotAllowedWarning(superFunc)
    local spec = self.spec_strawHarvestRefillSupplies
    if spec.hasCover and self:isRefillCoverOpen() then
        if spec.coverWarningText ~= nil then
            return g_i18n:getText(spec.coverWarningText)
        end
    end

    if spec.isActive then
        for _, supply in ipairs(spec.supplies) do
            if self:getFillUnitFillLevel(supply.fillUnitIndex) <= 0 then
                local fillType = self:getFillUnitFirstSupportedFillType(supply.fillUnitIndex)
                return g_i18n:getText("warning_refillSuppliesFirst"):format(g_fillTypeManager:getFillTypeByIndex(fillType).title)
            end
        end
    end

    return superFunc(self)
end

function StrawHarvestRefillSupplies:createBale(superFunc, baleFillType, fillLevel)
    local spec = self.spec_strawHarvestRefillSupplies

    if spec.isBaler and spec.isActive and self.isServer then
        local spec_baler = self.spec_baler
        local type = spec_baler.baleTypes[spec_baler.currentBaleTypeId]

        for _, supply in ipairs(spec.supplies) do
            local baleUsage = type.isRoundBale and type.diameter * math.pi or type.height * 2 + type.length * 2
            local supplyUsage = supply.usagePerLiter + baleUsage * supply.usageFactor * 0.001
            local fillType = self:getFillUnitFirstSupportedFillType(supply.fillUnitIndex)

            self:addFillUnitFillLevel(self:getOwnerFarmId(), supply.fillUnitIndex, -supplyUsage, fillType, ToolType.UNDEFINED, nil)
        end
    end

    return superFunc(self, baleFillType, fillLevel)
end

---Checks weather we should draw the "Fill tool first" text in the HUD.
function StrawHarvestRefillSupplies:getDrawFirstFillText(superFunc)
    local spec = self.spec_strawHarvestRefillSupplies
    if spec.isActive then
        for _, supply in ipairs(spec.supplies) do
            if self:getFillUnitFillLevel(supply.fillUnitIndex) <= 0 then
                return true
            end
        end

        return superFunc(self)
    end

    return false
end

-------------------
-- Action events --
-------------------

function StrawHarvestRefillSupplies.actionEventToggleCover(self, ...)
    if not self:getIsTurnedOn() then
        local spec = self.spec_strawHarvestRefillSupplies
        self:setIsRefillCoverOpen(not spec.isCoverOpen)
    end
end
