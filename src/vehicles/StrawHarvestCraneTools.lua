---
-- StrawHarvestCraneTools
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Allow for multiple crane tools with different functionality.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestCraneTools
StrawHarvestCraneTools = {}
StrawHarvestCraneTools.MOD_NAME = g_currentModName

StrawHarvestCraneTools.TYPE_SHOVEL = 1
StrawHarvestCraneTools.TYPE_GRAB = 2
StrawHarvestCraneTools.TYPE_PALLET_GRAB = 3

StrawHarvestCraneTools.STR_TO_TYPE = {
    ["shovel"] = StrawHarvestCraneTools.TYPE_SHOVEL,
    ["grab"] = StrawHarvestCraneTools.TYPE_GRAB,
    ["palletgrab"] = StrawHarvestCraneTools.TYPE_PALLET_GRAB,
}

StrawHarvestCraneTools.SEND_NUM_BITS = 2 -- 2 ^ 2 = 4
StrawHarvestCraneTools.SEND_MOUNTOBJECT_NUM_BITS = 5

function StrawHarvestCraneTools.prerequisitesPresent(specializations)
    return true
end

function StrawHarvestCraneTools.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "loadCraneToolFromXML", StrawHarvestCraneTools.loadCraneToolFromXML)
    SpecializationUtil.registerFunction(vehicleType, "toolMountTriggerCallback", StrawHarvestCraneTools.toolMountTriggerCallback)
    SpecializationUtil.registerFunction(vehicleType, "canMountObject", StrawHarvestCraneTools.canMountObject)
    SpecializationUtil.registerFunction(vehicleType, "addMountedObject", StrawHarvestCraneTools.addMountedObject)
    SpecializationUtil.registerFunction(vehicleType, "removeMountedObject", StrawHarvestCraneTools.removeMountedObject)
    SpecializationUtil.registerFunction(vehicleType, "getCraneTool", StrawHarvestCraneTools.getCraneTool)
    SpecializationUtil.registerFunction(vehicleType, "setCraneTool", StrawHarvestCraneTools.setCraneTool)
    SpecializationUtil.registerFunction(vehicleType, "canSwitchCraneTool", StrawHarvestCraneTools.canSwitchCraneTool)
    SpecializationUtil.registerFunction(vehicleType, "getIsCraneShovelClosing", StrawHarvestCraneTools.getIsCraneShovelClosing)
end

function StrawHarvestCraneTools.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getShovelNodeIsActive", StrawHarvestCraneTools.getShovelNodeIsActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsDischargeNodeActive", StrawHarvestCraneTools.getIsDischargeNodeActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getFillLevelInformation", StrawHarvestCraneTools.getFillLevelInformation)
end

function StrawHarvestCraneTools.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", StrawHarvestCraneTools)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", StrawHarvestCraneTools)
end

function StrawHarvestCraneTools:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_strawHarvestCraneTools
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionGrabEventId = self:addActionEvent(spec.actionEvents, InputAction.SH_TOGGLE_CRANE_TOOL, self, StrawHarvestCraneTools.actionEventToggleTool, false, true, false, true, nil)

            g_inputBinding:setActionEventText(actionGrabEventId, g_i18n:getText("action_toggleCraneTool"))
            g_inputBinding:setActionEventTextPriority(actionGrabEventId, GS_PRIO_NORMAL)
        end
    end
end

---Called on load.
function StrawHarvestCraneTools:onLoad(savegame)
    self.spec_strawHarvestCraneTools = self[("spec_%s.strawHarvestCraneTools"):format(StrawHarvestCraneTools.MOD_NAME)]
    local spec = self.spec_strawHarvestCraneTools

    spec.currentCraneToolIndex = -1
    spec.craneTools = {}

    spec.dischargeThreshold = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.craneTools#dischargeThreshold"), 0)
    spec.shovelThreshold = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.craneTools#shovelThreshold"), 0)

    local i = 0
    while true do
        local key = ("vehicle.craneTools.craneTool(%d)"):format(i)
        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local tool = {}
        if self:loadCraneToolFromXML(tool, self.xmlFile, key, i + 1) then
            table.insert(spec.craneTools, tool)
        end

        i = i + 1
    end

    if self.isServer then
        spec.pendingMountObjects = {}
    end

    spec.mountedObjects = {}
    spec.mountedObjectsDirtyFlag = self:getNextDirtyFlag()

    local currentCraneToolIndex = 1
    if savegame ~= nil then
        local key = ("%s.%s.strawHarvestCraneTools"):format(savegame.key, self:strawHarvest_getModName())
        currentCraneToolIndex = Utils.getNoNil(getXMLInt(savegame.xmlFile, key .. "#currentCraneToolIndex"), currentCraneToolIndex)
    end

    self:setCraneTool(currentCraneToolIndex, true)
end

function StrawHarvestCraneTools:onDelete()
    local spec = self.spec_strawHarvestCraneTools
    for object, _ in pairs(spec.mountedObjects) do
        self:removeMountedObject(object, true)
    end

    for _, tool in ipairs(spec.craneTools) do
        if self.isServer then
            for _, trigger in ipairs(tool.mountTriggers) do
                removeTrigger(trigger.triggerId)
            end
        end
    end
end

function StrawHarvestCraneTools:onReadStream(streamId, connection)
    local index = streamReadUIntN(streamId, StrawHarvestCraneTools.SEND_NUM_BITS) + 1
    self:setCraneTool(index, true)
end

function StrawHarvestCraneTools:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestCraneTools
    streamWriteUIntN(streamId, spec.currentCraneToolIndex - 1, StrawHarvestCraneTools.SEND_NUM_BITS)
end

function StrawHarvestCraneTools:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            local spec = self.spec_strawHarvestCraneTools
            local tool = self:getCraneTool(spec.currentCraneToolIndex)
            local amount = streamReadUIntN(streamId, StrawHarvestCraneTools.SEND_MOUNTOBJECT_NUM_BITS)

            for object, _ in pairs(spec.mountedObjects) do
                self:removeMountedObject(object, false)
            end

            spec.mountedObjects = {}
            for i = 1, amount do
                local object = NetworkUtil.readNodeObject(streamId)
                if object ~= nil then
                    if self:canMountObject(object) then
                        self:addMountedObject(object, tool.jointNode)
                    end
                end
            end
        end
    end
end

function StrawHarvestCraneTools:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then

        local spec = self.spec_strawHarvestCraneTools

        if streamWriteBool(streamId, bitAND(dirtyMask, spec.mountedObjectsDirtyFlag) ~= 0) then
            local objects = {}
            for object, _ in pairs(spec.mountedObjects) do
                table.insert(objects, object)
            end

            streamWriteUIntN(streamId, #objects, StrawHarvestCraneTools.SEND_MOUNTOBJECT_NUM_BITS)
            for i = 1, #objects do
                local object = objects[i]
                NetworkUtil.writeNodeObject(streamId, object)
            end
        end
    end
end

function StrawHarvestCraneTools:onPreSaveToXMLFile()
    -- Unmount objects in order to save them.
    local spec = self.spec_strawHarvestCraneTools
    for object, _ in pairs(spec.mountedObjects) do
        self:removeMountedObject(object, false)
    end
end

function StrawHarvestCraneTools:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestCraneTools
    setXMLInt(xmlFile, key .. "#currentCraneToolIndex", spec.currentCraneToolIndex)
end

function StrawHarvestCraneTools:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if not self.isServer then
        return
    end

    local spec = self.spec_strawHarvestCraneTools
    local tool = self:getCraneTool(spec.currentCraneToolIndex)

    local removeMountedObjects = not (tool.type ~= StrawHarvestCraneTools.TYPE_SHOVEL)

    if not removeMountedObjects then
        local dischargeNode = self:getCurrentDischargeNode()
        if dischargeNode ~= nil and dischargeNode.movingToolActivation ~= nil then
            local didMove, canAddMountedObjects = self:getIsCraneShovelClosing(dischargeNode, 0)
            if didMove then
                removeMountedObjects = not canAddMountedObjects

                if canAddMountedObjects then
                    for object, _ in pairs(spec.pendingMountObjects) do
                        if spec.mountedObjects[object] == nil then
                            if self:canMountObject(object) then
                                self:addMountedObject(object, tool.jointNode)
                            else
                                spec.pendingMountObjects[object] = nil
                            end
                        end
                    end
                end
            end
        end
    end

    if removeMountedObjects then
        for object, _ in pairs(spec.mountedObjects) do
            self:removeMountedObject(object, true)
        end
    end
end

function StrawHarvestCraneTools:canMountObject(object)
    local objectId = object.nodeId or object.rootNode
    if objectId ~= nil then
        if object.getCanByMounted ~= nil then
            return object:getCanByMounted()
        end

        return entityExists(objectId)
    end

    return false
end

function StrawHarvestCraneTools:addMountedObject(object, jointNode)
    local spec = self.spec_strawHarvestCraneTools
    local objectId = object.nodeId or object.rootNode

    -- If its attached to something dynamically remove it.
    if object.dynamicMountObject ~= nil then
        object.dynamicMountObject:removeDynamicMountedObject(object, true)
    end

    -- Adjust the Y translation so it does not jump objects.
    local _, y, _ = localToLocal(objectId, jointNode, 0, 0, 0)
    local rx, ry, rz = localRotationToLocal(objectId, jointNode, 0, 0, 0)
    object:mount(self, jointNode, 0, y, 0, rx, ry, rz)

    spec.mountedObjects[object] = object

    -- Fix to notify the palletizer that we removed the object from physics.
    if object.strawHarvestPalletizer ~= nil then
        object.strawHarvestPalletizer:onObjectRemovedFromPhysics(object)
    end

    self:raiseDirtyFlags(spec.mountedObjectsDirtyFlag)
end

function StrawHarvestCraneTools:removeMountedObject(object, isDeleting)
    local spec = self.spec_strawHarvestCraneTools

    spec.mountedObjects[object] = nil
    if isDeleting then
        spec.pendingMountObjects[object] = nil
    end

    object:unmount()

    self:raiseDirtyFlags(spec.mountedObjectsDirtyFlag)
end

function StrawHarvestCraneTools:onEnterVehicle()
    self:setBeaconLightsVisibility(true, true, true)
end

function StrawHarvestCraneTools:onLeaveVehicle()
    self:setBeaconLightsVisibility(false, true, true)
end

---Gets the crane tool object on the given index.
function StrawHarvestCraneTools:getCraneTool(index)
    return self.spec_strawHarvestCraneTools.craneTools[index]
end

---Sets the current crane tool and enables the object changes.
function StrawHarvestCraneTools:setCraneTool(index, noEventSend)
    local spec = self.spec_strawHarvestCraneTools
    if spec.currentCraneToolIndex ~= index then
        StrawHarvestCraneToolsEvent.sendEvent(self, index, noEventSend)

        StrawHarvestCraneTools.removeCraneFromPhysics(self)

        local function showFillUnitOnHud(fillUnitIndex, showOnHud)
            if fillUnitIndex ~= nil then
                local fillUnit = self:getFillUnitByIndex(fillUnitIndex)
                fillUnit.showOnHud = showOnHud
            end
        end

        local lastTool = self:getCraneTool(spec.currentCraneToolIndex)
        if lastTool ~= nil then
            showFillUnitOnHud(lastTool.fillUnitIndex, false)
            ObjectChangeUtil.setObjectChanges(lastTool.objectChanges, false, self)
        end

        local tool = self:getCraneTool(index)
        showFillUnitOnHud(tool.fillUnitIndex, true)
        ObjectChangeUtil.setObjectChanges(tool.objectChanges, true, self)

        if tool.movingToolNode ~= nil then
            local movingTool = self:getMovingToolByNode(tool.movingToolNode)
            if movingTool ~= nil then
                movingTool.animMaxTime = tool.animMaxTime
            end
        end

        spec.currentCraneToolIndex = index
        StrawHarvestCraneTools.addCraneToPhysics(self)
    end
end

function StrawHarvestCraneTools:canSwitchCraneTool()
    local spec = self.spec_strawHarvestCraneTools
    local tool = self:getCraneTool(spec.currentCraneToolIndex)

    if tool.fillUnitIndex ~= nil then
        local fillLevel = self:getFillUnitFillLevel(tool.fillUnitIndex)
        if fillLevel > 0 then
            return false
        end
    end

    return true
end

function StrawHarvestCraneTools:getIsCraneShovelClosing(node, activeThreshold)
    local movingToolActivation = node.movingToolActivation
    local movingTool = self.spec_cylindered.nodesToMovingTools[movingToolActivation.node]
    local state = Cylindered.getMovingToolState(self, movingTool)
    local previousState = movingToolActivation.lastState or state

    local activeState = state
    if movingToolActivation.isInverted then
        activeState = math.abs(state - 1)
    end

    local factor = movingToolActivation.openFactor
    local didMove = math.abs(previousState - state) > 0.001
    local isClosing = (state - factor) > (previousState - factor)
    movingToolActivation.lastState = state

    return didMove, isClosing and activeState >= activeThreshold
end

function StrawHarvestCraneTools:loadCraneToolFromXML(tool, xmlFile, key, index)
    tool.index = index

    local typeStr = Utils.getNoNil(getXMLString(xmlFile, key .. "#type"), "shovel")

    tool.type = StrawHarvestCraneTools.STR_TO_TYPE[typeStr:lower()]
    tool.fillUnitIndex = getXMLInt(xmlFile, key .. "#fillUnitIndex")
    if tool.fillUnitIndex ~= nil then
        local fillUnit = self:getFillUnitByIndex(tool.fillUnitIndex)
        fillUnit.showOnHud = false
    end

    tool.movingToolNode = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, key .. "#movingToolNode"), self.i3dMappings)
    tool.animMaxTime = math.min(Utils.getNoNil(getXMLFloat(xmlFile, key .. "#movingToolMaxAnimationTime"), 1.0), 1.0)

    tool.jointNode = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, key .. "#jointNode"), self.i3dMappings)
    if self.isServer then
        tool.mountTriggerToEntry = {}
        tool.mountTriggers = {}

        local i = 0
        while true do
            local triggerKey = ("%s.mount.trigger(%d)"):format(key, i)
            if not hasXMLProperty(xmlFile, triggerKey) then break end

            local entry = {}
            entry.triggerId = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, triggerKey .. "#node"), self.i3dMappings)

            if entry.triggerId ~= nil then
                addTrigger(entry.triggerId, "toolMountTriggerCallback", self)
                table.insert(tool.mountTriggers, entry)
                tool.mountTriggerToEntry[entry.triggerId] = entry
            end

            i = i + 1
        end
    end

    tool.objectChanges = {}
    ObjectChangeUtil.loadObjectChangeFromXML(xmlFile, key, tool.objectChanges, self.components, self)
    ObjectChangeUtil.setObjectChanges(tool.objectChanges, false)

    return true
end

---Adds the dynamic components to physics
function StrawHarvestCraneTools.addCraneToPhysics(self)
    if not self.isAddedToPhysics then
        for _, component in pairs(self.components) do
            if not component.isStatic then
                addToPhysics(component.node)
            end
        end

        self.isAddedToPhysics = true

        if self.isServer then
            for _, jointDesc in pairs(self.componentJoints) do
                self:createComponentJoint(self.components[jointDesc.componentIndices[1]], self.components[jointDesc.componentIndices[2]], jointDesc)
            end

            -- if rootnode is sleeping all other components are sleeping as well
            addWakeUpReport(self.rootNode, "onVehicleWakeUpCallback", self)
        end

        for _, collisionPair in pairs(self.collisionPairs) do
            setPairCollision(collisionPair.component1.node, collisionPair.component2.node, collisionPair.enabled)
        end

        self:setMassDirty()
    end

    return true
end

---Removes the dynamic components from physics
function StrawHarvestCraneTools.removeCraneFromPhysics(self)
    for _, component in pairs(self.components) do
        if not component.isStatic then
            removeFromPhysics(component.node)
        end
    end

    if self.isServer then
        for _, jointDesc in pairs(self.componentJoints) do
            jointDesc.jointIndex = 0
        end
        removeWakeUpReport(self.rootNode)
    end

    self.isAddedToPhysics = false

    return true
end

function StrawHarvestCraneTools:toolMountTriggerCallback(triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    local spec = self.spec_strawHarvestCraneTools
    local tool = self:getCraneTool(spec.currentCraneToolIndex)

    if tool.mountTriggerToEntry[triggerId] ~= nil then
        if onEnter then
            local object = g_currentMission:getNodeObject(otherActorId)
            if object == nil then
                object = g_currentMission.nodeToObject[otherActorId]
            end
            if object == self:getRootVehicle() or (self.spec_attachable ~= nil and self.spec_attachable.attacherVehicle == object) then
                object = nil
            end
            if object ~= nil and object ~= self then
                -- is a mountable object (e.g. bales)
                local isObject = object.getSupportsMountDynamic ~= nil and object:getSupportsMountDynamic() and object.lastMoveTime ~= nil

                -- is a mountable vehicle (e.g. pallets)
                local isVehicle = object.getSupportsTensionBelts ~= nil and object:getSupportsTensionBelts() and object.lastMoveTime ~= nil

                if isObject or isVehicle then
                    spec.pendingMountObjects[object] = Utils.getNoNil(spec.pendingMountObjects[object], 0) + 1
                end
            end
        elseif onLeave then
            local object = g_currentMission:getNodeObject(otherActorId)
            if object == nil then
                object = g_currentMission.nodeToObject[otherActorId]
            end
            if object ~= nil then
                if spec.pendingMountObjects[object] ~= nil then
                    local count = spec.pendingMountObjects[object] - 1
                    if count == 0 then
                        spec.pendingMountObjects[object] = nil

                        if spec.mountedObjects[object] ~= nil then
                            self:removeMountedObject(object, false)
                        end
                    else
                        spec.pendingMountObjects[object] = count
                    end
                end
            end
        end
    end
end

-------------------
-- Overwrites --
-------------------

function StrawHarvestCraneTools:getIsDischargeNodeActive(superFunc, dischargeNode)
    local spec = self.spec_strawHarvestCraneTools
    local tool = self:getCraneTool(spec.currentCraneToolIndex)
    if tool.type ~= StrawHarvestCraneTools.TYPE_SHOVEL then
        return false
    end

    if dischargeNode.movingToolActivation ~= nil then
        local _, isClosing = self:getIsCraneShovelClosing(dischargeNode, spec.dischargeThreshold)
        if isClosing then
            return false
        end
    end

    return superFunc(self, dischargeNode)
end

function StrawHarvestCraneTools:getShovelNodeIsActive(superFunc, shovelNode)
    local spec = self.spec_strawHarvestCraneTools
    local tool = self:getCraneTool(spec.currentCraneToolIndex)
    if tool.type ~= StrawHarvestCraneTools.TYPE_SHOVEL then
        return false
    end

    if shovelNode.movingToolActivation ~= nil then
        local didMove, isClosing = self:getIsCraneShovelClosing(shovelNode, spec.shovelThreshold)
        if didMove and isClosing then
            return true
        end
    end

    return superFunc(self, shovelNode)
end

function StrawHarvestCraneTools:getFillLevelInformation(superFunc, fillLevelInformations)
    superFunc(self, fillLevelInformations)

    local spec = self.spec_strawHarvestCraneTools
    for object, _ in pairs(spec.mountedObjects) do
        if object.getFillLevelInformation ~= nil then
            object:getFillLevelInformation(fillLevelInformations)
        else
            if object.getFillLevel ~= nil and object.getFillType ~= nil then
                local added = false
                for _, fillLevelInformation in pairs(fillLevelInformations) do
                    if fillLevelInformation.fillType == object:getFillType() then
                        fillLevelInformation.fillLevel = fillLevelInformation.fillLevel + object:getFillLevel()
                        if object.getCapacity ~= nil then
                            fillLevelInformation.capacity = fillLevelInformation.capacity + object:getCapacity()
                        else
                            fillLevelInformation.capacity = fillLevelInformation.capacity + object:getFillLevel() -- bale
                        end
                        added = true
                        break
                    end
                end
                if not added then
                    if object.getCapacity ~= nil then
                        table.insert(fillLevelInformations, { fillType = object:getFillType(), fillLevel = object:getFillLevel(), capacity = object:getCapacity() })
                    else
                        table.insert(fillLevelInformations, { fillType = object:getFillType(), fillLevel = object:getFillLevel(), capacity = object:getFillLevel() })
                    end
                end
            end
        end
    end
end

-------------------
-- Action events --
-------------------

function StrawHarvestCraneTools.actionEventToggleTool(self, ...)
    local spec = self.spec_strawHarvestCraneTools

    if self:canSwitchCraneTool() then
        local index = spec.currentCraneToolIndex + 1
        if index > #spec.craneTools then
            index = 1
        end

        self:setCraneTool(index)
    end
end
