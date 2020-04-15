---
-- StrawHarvestBaleCollect
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Allows to collect bales from the bale collect baler.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestBaleCollect
StrawHarvestBaleCollect = {}
StrawHarvestBaleCollect.MOD_NAME = g_currentModName

StrawHarvestBaleCollect.COLLECT_MODE_SINGLE = 1
StrawHarvestBaleCollect.COLLECT_MODE_TWO = 2
StrawHarvestBaleCollect.COLLECT_MODE_THREE = 3

-- Modes based on if place is a side place
StrawHarvestBaleCollect.COLLECT_MODES = {
    [true] = { StrawHarvestBaleCollect.COLLECT_MODE_TWO, StrawHarvestBaleCollect.COLLECT_MODE_THREE },
    [false] = { StrawHarvestBaleCollect.COLLECT_MODE_SINGLE, StrawHarvestBaleCollect.COLLECT_MODE_THREE }
}

StrawHarvestBaleCollect.VISUALS = {
    [StrawHarvestBaleCollect.COLLECT_MODE_SINGLE] = { "-", "x", "-" },
    [StrawHarvestBaleCollect.COLLECT_MODE_TWO] = { "x", "-", "x" },
    [StrawHarvestBaleCollect.COLLECT_MODE_THREE] = { "x", "x", "x" }
}

StrawHarvestBaleCollect.RESET_SCALE = -1
StrawHarvestBaleCollect.SCALE_ANIMATION_TIME_THRESHOLD = 0.5

local function getCollectPlaceVisualText(mode)
    local visuals = StrawHarvestBaleCollect.VISUALS[mode]
    return ("(%s)"):format(table.concat(visuals, "|"))
end

function StrawHarvestBaleCollect.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AnimatedVehicle, specializations)
            and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function StrawHarvestBaleCollect.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "loadCollectPlaceFromXML", StrawHarvestBaleCollect.loadCollectPlaceFromXML)
    SpecializationUtil.registerFunction(vehicleType, "setCollectMode", StrawHarvestBaleCollect.setCollectMode)
    SpecializationUtil.registerFunction(vehicleType, "canToggleCollectMode", StrawHarvestBaleCollect.canToggleCollectMode)
    SpecializationUtil.registerFunction(vehicleType, "updateBaleCollectAttacherJoint", StrawHarvestBaleCollect.updateBaleCollectAttacherJoint)
    SpecializationUtil.registerFunction(vehicleType, "collectBale", StrawHarvestBaleCollect.collectBale)
    SpecializationUtil.registerFunction(vehicleType, "departBale", StrawHarvestBaleCollect.departBale)
    SpecializationUtil.registerFunction(vehicleType, "triggerDepartBales", StrawHarvestBaleCollect.triggerDepartBales)
    SpecializationUtil.registerFunction(vehicleType, "departBales", StrawHarvestBaleCollect.departBales)
    SpecializationUtil.registerFunction(vehicleType, "canDepartBales", StrawHarvestBaleCollect.canDepartBales)
    SpecializationUtil.registerFunction(vehicleType, "setDepartBales", StrawHarvestBaleCollect.setDepartBales)
    SpecializationUtil.registerFunction(vehicleType, "getCollectPlaceByIndex", StrawHarvestBaleCollect.getCollectPlaceByIndex)
    SpecializationUtil.registerFunction(vehicleType, "getActiveCollectPlaces", StrawHarvestBaleCollect.getActiveCollectPlaces)
    SpecializationUtil.registerFunction(vehicleType, "getAvailableActiveCollectPlaceIndex", StrawHarvestBaleCollect.getAvailableActiveCollectPlaceIndex)
    SpecializationUtil.registerFunction(vehicleType, "allowsCollectingBale", StrawHarvestBaleCollect.allowsCollectingBale)
end

function StrawHarvestBaleCollect.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldAllowed", StrawHarvestBaleCollect.getIsFoldAllowed)
end

function StrawHarvestBaleCollect.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onPreAttach", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onPreDetach", StrawHarvestBaleCollect)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", StrawHarvestBaleCollect)
end

function StrawHarvestBaleCollect:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_strawHarvestBaleCollect
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionDepartEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_DEPART_BALES, self, StrawHarvestBaleCollect.actionEventDepartBales, false, true, false, true, nil)
            local _, actionToggleEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_TOGGLE_COLLECT_MODE, self, StrawHarvestBaleCollect.actionEventToggleCollectMode, false, true, false, true, nil)

            g_inputBinding:setActionEventText(actionDepartEventId, g_i18n:getText("action_baleloaderUnload"))
            local text = g_i18n:getText("action_collectMode"):format(getCollectPlaceVisualText(spec.collectMode))
            g_inputBinding:setActionEventText(actionToggleEventId, text)
            g_inputBinding:setActionEventTextPriority(actionDepartEventId, GS_PRIO_NORMAL)
            g_inputBinding:setActionEventTextPriority(actionToggleEventId, GS_PRIO_NORMAL)
        end
    end
end

---Called on load.
function StrawHarvestBaleCollect:onLoad(savegame)
    self.spec_strawHarvestBaleCollect = self[("spec_%s.strawHarvestBaleCollect"):format(StrawHarvestBaleCollect.MOD_NAME)]

    local spec = self.spec_strawHarvestBaleCollect

    spec.collectMode = StrawHarvestBaleCollect.COLLECT_MODE_THREE
    spec.baleCollectAxisAnimationName = getXMLString(self.xmlFile, "vehicle.baleCollect#baleCollectAxisAnimationName")
    spec.baleCollectAxisIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.baleCollect#baleCollectAxisIndex"), 1) - 1
    spec.lastRotationLimitScale = StrawHarvestBaleCollect.RESET_SCALE

    spec.departBales = false
    spec.collectDepartBaleTime = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleCollect.collectPlaces#collectDepartBaleTime"), 1) * 1000
    spec.collectDepartBaleTimer = 0
    spec.collectResetGrabberTimer = 0

    spec.fillUnitIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.baleCollect.collectPlaces#fillUnitIndex"), 1)
    local fillUnit = self:getFillUnitByIndex(spec.fillUnitIndex)
    fillUnit.needsSaving = false -- No need to save the fillLevel as it the bales are saved already.

    spec.collectPlacesUnloadAnimationName = getXMLString(self.xmlFile, "vehicle.baleCollect.collectPlaces#unloadAnimationName")
    spec.collectPlaces = {}
    spec.collectPlacesToLoad = {}
    spec.collectPlacesToMount = {}
    spec.collectPlacesByMode = {}

    local i = 0
    while true do
        local key = ("vehicle.baleCollect.collectPlaces.place(%d)"):format(i)
        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local place = {}
        if self:loadCollectPlaceFromXML(place, self.xmlFile, key, i + 1) then
            table.insert(spec.collectPlaces, place)
            for _, mode in pairs(StrawHarvestBaleCollect.COLLECT_MODES[place.isSide]) do
                if spec.collectPlacesByMode[mode] == nil then
                    spec.collectPlacesByMode[mode] = {}
                end
                table.insert(spec.collectPlacesByMode[mode], place)
            end
        end

        i = i + 1
    end

    spec.baleGrabber = {}
    spec.baleGrabber.grabNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleCollect.grabber#node"), self.i3dMappings)
    spec.baleGrabber.orgNearestDistance = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleCollect.grabber#nearestDistance"), 1.5)
    spec.baleGrabber.nearestDistance = spec.baleGrabber.orgNearestDistance
end

function StrawHarvestBaleCollect:onPostLoad(savegame)
    local spec = self.spec_strawHarvestBaleCollect
    spec.collectPlacesToLoad = {}

    if savegame ~= nil and not savegame.resetVehicles then
        local key = ("%s.%s.strawHarvestBaleCollect"):format(savegame.key, self:strawHarvest_getModName())

        local i = 0
        while true do
            local placeKey = ("%s.collectPlaces.place(%d)"):format(key, i)
            if not hasXMLProperty(savegame.xmlFile, placeKey) then
                break
            end

            local placeIndex = getXMLInt(savegame.xmlFile, placeKey .. "#index")
            local baleKey = ("%s.bale"):format(placeKey)
            local filename = NetworkUtil.convertFromNetworkFilename(getXMLString(savegame.xmlFile, baleKey .. "#filename"))
            local translation = { StringUtil.getVectorFromString(getXMLString(savegame.xmlFile, baleKey .. "#position")) }
            local rotation = { StringUtil.getVectorFromString(getXMLString(savegame.xmlFile, baleKey .. "#rotation")) }
            local fillLevel = getXMLFloat(savegame.xmlFile, baleKey .. "#fillLevel")
            local farmId = getXMLInt(savegame.xmlFile, baleKey .. "#farmId")
            table.insert(spec.collectPlacesToLoad, { placeIndex = placeIndex, filename = filename, translation = translation, rotation = rotation, fillLevel = fillLevel, farmId = farmId })
            i = i + 1
        end
    end
end

function StrawHarvestBaleCollect:onDelete()
    local spec = self.spec_strawHarvestBaleCollect

    -- Avoid the bale nodes to be deleted twice
    for i, place in ipairs(spec.collectPlaces) do
        if place.baleNetworkId ~= nil then
            local bale = NetworkUtil.getObject(place.baleNetworkId)
            if bale ~= nil then
                self:departBale(i)

                -- if the vehicle is reloaded we remove the bale since it will be regenerated on load
                if self.isReconfigurating ~= nil and self.isReconfigurating then
                    bale:delete()
                end
            end
        end
    end
end

function StrawHarvestBaleCollect:onReadStream(streamId, timestamp, connection)
    self:setCollectMode(streamReadInt8(streamId), true)

    local spec = self.spec_strawHarvestBaleCollect
    spec.collectPlacesToMount = {}

    for _, place in ipairs(spec.collectPlaces) do
        if streamReadBool(streamId) then
            local placeIndex = place.index
            local baleObjectId = NetworkUtil.readNodeObjectId(streamId)
            spec.collectPlacesToMount[baleObjectId] = { placeIndex = placeIndex, baleNetworkId = baleObjectId }
        end
    end
end

function StrawHarvestBaleCollect:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestBaleCollect
    streamWriteInt8(streamId, spec.collectMode)

    for _, place in ipairs(spec.collectPlaces) do
        if streamWriteBool(streamId, place.baleNetworkId ~= nil) then
            NetworkUtil.writeNodeObjectId(streamId, place.baleNetworkId)
        end
    end
end

function StrawHarvestBaleCollect:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestBaleCollect

    for i, place in ipairs(spec.collectPlaces) do
        local placeKey = ("%s.collectPlaces.place(%d)"):format(key, i - 1)
        if place.baleNetworkId ~= nil then
            local bale = NetworkUtil.getObject(place.baleNetworkId)
            if bale ~= nil then
                setXMLInt(xmlFile, placeKey .. "#index", i)
                local baleKey = ("%s.bale"):format(placeKey)
                bale:saveToXMLFile(xmlFile, baleKey)
            end
        end
    end
end

---Called on update frame.
function StrawHarvestBaleCollect:onUpdate(dt)
    local spec = self.spec_strawHarvestBaleCollect

    if self.firstTimeRun then
        for i, v in ipairs(spec.collectPlacesToLoad) do
            local bale = Bale:new(self.isServer, self.isClient)
            local x, y, z = unpack(v.translation)
            local rx, ry, rz = unpack(v.rotation)
            bale:load(v.filename, x, y, z, rx, ry, rz, v.fillLevel)
            bale.ownerFarmId = Utils.getNoNil(v.farmId, AccessHandler.EVERYONE)
            bale:register()

            self:collectBale(v.placeIndex, NetworkUtil.getObjectId(bale), false)
            spec.collectPlacesToLoad[i] = nil
        end

        for i, v in pairs(spec.collectPlacesToMount) do
            self:collectBale(v.placeIndex, v.baleNetworkId, false)
        end
    end

    if self.isClient then
        if spec.actionEvents ~= nil then
            local actionDepartEvent = spec.actionEvents[InputAction.SH_DEPART_BALES]
            if actionDepartEvent ~= nil then
                g_inputBinding:setActionEventActive(actionDepartEvent.actionEventId, self:getFillUnitFillLevel(spec.fillUnitIndex) ~= 0)
            end
        end
    end
end

---Called on update tick frame.
function StrawHarvestBaleCollect:onUpdateTick(dt)
    local spec = self.spec_strawHarvestBaleCollect

    if self.isServer then
        if self:getIsInWorkPosition() then
            if self:canDepartBales() then
                self:triggerDepartBales()
                self:setDepartBales(false)
            end

            if spec.collectResetGrabberTimer ~= 0 and spec.collectResetGrabberTimer < g_currentMission.time then
                spec.baleGrabber.nearestDistance = spec.baleGrabber.orgNearestDistance
                spec.collectResetGrabberTimer = 0
            end

            if self:allowsCollectingBale() then
                local nearestBale = StrawHarvestBaleCollect.getBaleInRange(spec.baleGrabber.grabNode, spec.baleGrabber.nearestDistance)
                if nearestBale ~= nil then
                    local placeIndex, doDepart = self:getAvailableActiveCollectPlaceIndex()
                    self:collectBale(placeIndex, NetworkUtil.getObjectId(nearestBale), doDepart)
                end
            end
        end

        if spec.collectDepartBaleTimer ~= 0 and spec.collectDepartBaleTimer < g_currentMission.time then
            self:departBales()
            spec.collectDepartBaleTimer = 0
        end

        local animationTime = self:getAnimationTime(spec.baleCollectAxisAnimationName)
        local scale = math.max(0, (animationTime - StrawHarvestBaleCollect.SCALE_ANIMATION_TIME_THRESHOLD) * 2)
        self:updateBaleCollectAttacherJoint(scale)
    end
end

---Gets the nearest bale in range.
function StrawHarvestBaleCollect.getBaleInRange(refNode, distance)
    local nearestDistance = distance
    local nearestBale

    for _, item in pairs(g_currentMission.itemsToSave) do
        local bale = item.item
        if bale:isa(Bale) and entityExists(bale.nodeId) and not bale.isAttachedToBaleHook then
            local maxDist
            if bale.baleDiameter ~= nil then
                maxDist = math.min(bale.baleDiameter, bale.baleWidth)
            else
                maxDist = math.min(bale.baleLength, bale.baleHeight, bale.baleWidth)
            end
            local _, _, z = localToLocal(bale.nodeId, refNode, 0, 0, 0)
            if math.abs(z) < maxDist and calcDistanceFrom(refNode, bale.nodeId) < nearestDistance then
                nearestDistance = distance
                nearestBale = bale
            end
        end
    end

    return nearestBale
end

---Checks if the collector can collect another bale.
function StrawHarvestBaleCollect:allowsCollectingBale()
    local spec = self.spec_strawHarvestBaleCollect
    return spec.collectDepartBaleTimer == 0 and spec.baleGrabber.nearestDistance ~= 0 and spec.baleGrabber.grabNode ~= nil
end

---Collects bale on the given place index.
function StrawHarvestBaleCollect:collectBale(index, baleObjectId, doDepart)
    local spec = self.spec_strawHarvestBaleCollect

    if index ~= nil then
        local bale = NetworkUtil.getObject(baleObjectId)
        if bale ~= nil then
            local place = self:getCollectPlaceByIndex(index)
            place.baleNetworkId = baleObjectId

            bale.isCollectedByBaleCollect = true
            bale:mount(self, place.node, 0, 0, 0, 0, 0, 0)

            if place.moveAnimationName ~= nil then
                self:playAnimation(place.moveAnimationName, 1, nil, true)
            end

            self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, 1, self:getFillUnitFirstSupportedFillType(spec.fillUnitIndex), ToolType.UNDEFINED)
            spec.collectPlacesToMount[baleObjectId] = nil
        else
            spec.collectPlacesToMount[baleObjectId] = { placeIndex = index, baleNetworkId = baleObjectId }
        end
    end

    -- Collected bale
    if self.isServer then
        if doDepart then
            self:setDepartBales(true)
        end

        g_server:broadcastEvent(StrawHarvestCollectBaleEvent:new(self, index, baleObjectId), nil, nil, self)
    end
end

---Departs bale on the given place index.
function StrawHarvestBaleCollect:departBale(index)
    local spec = self.spec_strawHarvestBaleCollect

    if index ~= nil then
        local place = self:getCollectPlaceByIndex(index)
        local bale = NetworkUtil.getObject(place.baleNetworkId)

        if bale ~= nil then
            bale.isCollectedByBaleCollect = false
            bale:unmount()
            spec.collectPlacesToMount[place.baleNetworkId] = nil
            place.baleNetworkId = nil
        end

        if place.moveAnimationName ~= nil then
            self:setAnimationTime(place.moveAnimationName, 0, true)
        end
    end
end

---Departs all bales in the collect places.
function StrawHarvestBaleCollect:departBales()
    local spec = self.spec_strawHarvestBaleCollect
    for _, place in ipairs(spec.collectPlaces) do
        self:departBale(place.index)
    end

    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, -self:getFillUnitCapacity(spec.fillUnitIndex), self:getFillUnitFirstSupportedFillType(spec.fillUnitIndex), ToolType.UNDEFINED)

    if self.isServer then
        g_server:broadcastEvent(StrawHarvestDepartBalesEvent:new(self, false, true), nil, nil, self)
    end
end

---Triggers the depart timers and plays the unloading animation.
function StrawHarvestBaleCollect:triggerDepartBales()
    local spec = self.spec_strawHarvestBaleCollect
    self:playAnimation(spec.collectPlacesUnloadAnimationName, 1, nil, false)
    spec.collectDepartBaleTimer = g_currentMission.time + spec.collectDepartBaleTime
    spec.collectResetGrabberTimer = g_currentMission.time + (spec.collectDepartBaleTime * 2)
    spec.baleGrabber.nearestDistance = 0
end

---Sets the current depart state.
function StrawHarvestBaleCollect:setDepartBales(depart, doForceDepart, noEventSend)
    if doForceDepart == nil then
        doForceDepart = false
    end

    local spec = self.spec_strawHarvestBaleCollect
    if spec.departBales ~= depart or doForceDepart then
        StrawHarvestDepartBalesEvent.sendEvent(self, depart, doForceDepart, noEventSend)
        spec.departBales = depart
    end
end

---Check whether or not the bale collect can depart bales.
function StrawHarvestBaleCollect:canDepartBales()
    for _, place in pairs(self:getActiveCollectPlaces()) do
        if place.moveAnimationName ~= nil and self:getIsAnimationPlaying(place.moveAnimationName) then
            return false
        end
    end

    return self.spec_strawHarvestBaleCollect.departBales
end

---Gets an available index and determines if the available places are full.
function StrawHarvestBaleCollect:getAvailableActiveCollectPlaceIndex()
    local places = self:getActiveCollectPlaces()
    for index, place in pairs(self:getActiveCollectPlaces()) do
        if place.baleNetworkId == nil then
            return place.index, index == #places
        end
    end

    return nil, false
end

---Returns the collect place for the given index.
function StrawHarvestBaleCollect:getCollectPlaceByIndex(index)
    return self.spec_strawHarvestBaleCollect.collectPlaces[index]
end

---Gets the active collect places based on the current active collect mode.
function StrawHarvestBaleCollect:getActiveCollectPlaces()
    local spec = self.spec_strawHarvestBaleCollect
    local places = spec.collectPlacesByMode[spec.collectMode]
    return places or {}
end

function StrawHarvestBaleCollect:onPreAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_strawHarvestBaleCollect
    if attacherVehicle.isBaleCollectActive ~= nil and attacherVehicle:isBaleCollectActive() then
        local jointDesc = attacherVehicle:getAttacherJointByJointDescIndex(jointDescIndex)
        spec.attacherJoint = jointDesc
    else
        -- Depart bales when we get attached by vehicle that does not support the baleCollect.
        if self:getFillUnitFillLevel(spec.fillUnitIndex) ~= 0 then
            self:triggerDepartBales()
            self:setDepartBales(false)
        end

        if self:getIsInWorkPosition() then
            self:setFoldDirection(1, true)
        end
    end
end

function StrawHarvestBaleCollect:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_strawHarvestBaleCollect
    spec.lastRotationLimitScale = StrawHarvestBaleCollect.RESET_SCALE
end

function StrawHarvestBaleCollect:onPreDetach(attacherVehicle, implement)
    local spec = self.spec_strawHarvestBaleCollect
    spec.attacherJoint = nil

    if attacherVehicle.setIsTurnedOn ~= nil and attacherVehicle:getIsTurnedOn() then
        attacherVehicle:setIsTurnedOn(false)
    end
end

function StrawHarvestBaleCollect:updateBaleCollectAttacherJoint(scale)
    if self.isServer then
        local spec = self.spec_strawHarvestBaleCollect
        local jointDesc = spec.attacherJoint
        if jointDesc ~= nil and scale ~= spec.lastRotationLimitScale then
            local axisIndex = spec.baleCollectAxisIndex
            setJointRotationLimit(jointDesc.jointIndex, axisIndex, true, -jointDesc.lowerRotLimit[axisIndex + 1] * scale, jointDesc.lowerRotLimit[axisIndex + 1] * scale)
            spec.lastRotationLimitScale = scale
        end
    end
end

function StrawHarvestBaleCollect:setCollectMode(mode, noEventSend)
    local spec = self.spec_strawHarvestBaleCollect

    if mode ~= spec.collectMode then
        StrawHarvestCollectModeEvent.sendEvent(self, mode, noEventSend)

        local actionEvent = spec.actionEvents[InputAction.SH_TOGGLE_COLLECT_MODE]
        local text = g_i18n:getText("action_collectMode"):format(getCollectPlaceVisualText(mode))
        if actionEvent ~= nil then
            g_inputBinding:setActionEventText(actionEvent.actionEventId, text)
        end

        spec.collectMode = mode

        local index = self:getAvailableActiveCollectPlaceIndex()
        if index == nil then
            self:setDepartBales(true)
        end
    end
end

---Checks whether or not we can toggle the collect mode.
function StrawHarvestBaleCollect:canToggleCollectMode()
    -- Don't allow switching when the move animation is playing.
    for _, place in pairs(self:getActiveCollectPlaces()) do
        if place.moveAnimationName ~= nil and self:getIsAnimationPlaying(place.moveAnimationName) then
            return false
        end
    end

    local spec = self.spec_strawHarvestBaleCollect
    -- Don't allow switching when the depart animation is playing.
    return not self:getIsAnimationPlaying(spec.collectPlacesUnloadAnimationName)
end

---Load collect place from the XML.
function StrawHarvestBaleCollect:loadCollectPlaceFromXML(place, xmlFile, key, index)
    place.index = index
    place.isSide = Utils.getNoNil(getXMLBool(xmlFile, key .. "#isSide"), false)
    place.node = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, key .. "#node"), self.i3dMappings)
    place.moveAnimationName = getXMLString(xmlFile, key .. "#moveAnimationName")
    place.baleNetworkId = nil

    return true
end

----------------
-- Overwrites --
----------------

---Checks whether fold is allowed or not.
---Returns false when the bale collect is attached, false otherwise.
function StrawHarvestBaleCollect:getIsFoldAllowed(superFunc, direction, onAiTurnOn)
    local spec = self.spec_strawHarvestBaleCollect

    -- When there's no baler attached disable folding.
    if spec.attacherJoint == nil then
        return false
    end

    if self:getFillUnitFillLevel(spec.fillUnitIndex) ~= 0 then
        return false
    end

    local attacherVehicle = self:getAttacherVehicle()
    if attacherVehicle ~= nil then
        if attacherVehicle.getIsTurnedOn ~= nil and attacherVehicle:getIsTurnedOn() then
            return false
        end
    end

    return superFunc(self, direction, onAiTurnOn)
end

-------------------
-- Action events --
-------------------

function StrawHarvestBaleCollect.actionEventDepartBales(self, ...)
    local spec = self.spec_strawHarvestBaleCollect
    if self:getFillUnitFillLevel(spec.fillUnitIndex) ~= 0 then
        self:setDepartBales(true, true)
    end
end

function StrawHarvestBaleCollect.actionEventToggleCollectMode(self, ...)
    if self:canToggleCollectMode() then
        local spec = self.spec_strawHarvestBaleCollect
        local mode = spec.collectMode + 1
        if mode > StrawHarvestBaleCollect.COLLECT_MODE_THREE then
            mode = StrawHarvestBaleCollect.COLLECT_MODE_SINGLE
        end

        self:setCollectMode(mode)
    end
end
