---
-- StrawHarvestStorageBuffer
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Handle buffer storages.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestStorageBuffer
StrawHarvestStorageBuffer = {}

local StrawHarvestStorageBuffer_mt = Class(StrawHarvestStorageBuffer, Object)

InitObjectClass(StrawHarvestStorageBuffer, "StrawHarvestStorageBuffer")

function StrawHarvestStorageBuffer:new(isServer, isClient, customMt)
    local self = Object:new(isServer, isClient, customMt or StrawHarvestStorageBuffer_mt)

    self.nodeId = 0
    self.listenerFunction = nil
    self.dependingStorageBuffers = {}

    registerObjectClassName(self, "StrawHarvestStorageBuffer")

    return self
end

function StrawHarvestStorageBuffer:load(nodeId, xmlFile, key, i3dMappings, target)
    self.nodeId = nodeId
    self.target = target

    self.capacity = getXMLFloat(xmlFile, key .. "#capacity") or 100000
    self.fillType = FillType.UNKNOWN
    self.lastValidFillType = FillType.UNKNOWN
    self.supportedFillTypes = {}
    self.sortedFillTypes = {}
    self.fillLevel = 0
    self.fillTypeChangeThreshold = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#fillTypeChangeThreshold"), 0.05) -- fill level percentage that still allows overriding with another fill type
    self.fillPlaneNode = I3DUtil.indexToObject(nodeId, getXMLString(xmlFile, key .. "#planeNode"), i3dMappings)

    local fillTypeCategories = getXMLString(xmlFile, key .. "#fillTypeCategories")
    local fillTypeNames = getXMLString(xmlFile, key .. "#fillTypes")
    local fillTypes

    if fillTypeCategories ~= nil and fillTypeNames == nil then
        fillTypes = g_fillTypeManager:getFillTypesByCategoryNames(fillTypeCategories, "Warning: '" .. tostring(key) .. "' has invalid fillTypeCategory '%s'.")
    elseif fillTypeCategories == nil and fillTypeNames ~= nil then
        fillTypes = g_fillTypeManager:getFillTypesByNames(fillTypeNames, "Warning: '" .. tostring(key) .. "' has invalid fillType '%s'.")
    else
        print("Warning: '" .. tostring(key) .. "' a 'Storage' entry needs either the 'fillTypeCategories' or 'fillTypes' attribute.")
        return false
    end

    for _, fillType in pairs(fillTypes) do
        self.supportedFillTypes[fillType] = true
        table.insert(self.sortedFillTypes, fillType)
    end
    table.sort(self.sortedFillTypes)

    self.storageBufferDirtyFlag = self:getNextDirtyFlag()

    self:empty()

    return true
end

function StrawHarvestStorageBuffer:delete()
    unregisterObjectClassName(self)
    StrawHarvestStorageBuffer:superClass().delete(self)
end

function StrawHarvestStorageBuffer:readStream(streamId, connection)
    StrawHarvestStorageBuffer:superClass().readStream(self, streamId, connection)

    local fillLevel = streamReadFloat32(streamId)
    local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self:setFillLevel(fillLevel, fillType)
end

function StrawHarvestStorageBuffer:writeStream(streamId, connection)
    StrawHarvestStorageBuffer:superClass().writeStream(self, streamId, connection)

    streamWriteFloat32(streamId, self.fillLevel)
    streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
end

function StrawHarvestStorageBuffer:readUpdateStream(streamId, timestamp, connection)
    StrawHarvestStorageBuffer:superClass().readUpdateStream(self, streamId, timestamp, connection)

    if connection:getIsServer() then
        if streamReadBool(streamId) then
            local fillLevel = streamReadFloat32(streamId)
            local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
            self:setFillLevel(fillLevel, fillType)
        end
    end
end

function StrawHarvestStorageBuffer:writeUpdateStream(streamId, connection, dirtyMask)
    StrawHarvestStorageBuffer:superClass().writeUpdateStream(self, streamId, connection, dirtyMask)

    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, self.storageBufferDirtyFlag) ~= 0) then
            streamWriteFloat32(streamId, self.fillLevel)
            streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

function StrawHarvestStorageBuffer:loadFromXMLFile(xmlFile, key)
    self:setOwnerFarmId(Utils.getNoNil(getXMLInt(xmlFile, key .. "#farmId"), AccessHandler.EVERYONE), true)

    local fillTypeStr = getXMLString(xmlFile, key .. "#fillType")
    if fillTypeStr ~= nil then
        local fillLevel = math.max(Utils.getNoNil(getXMLFloat(xmlFile, key .. "#fillLevel"), 0), 0)
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeStr)

        if fillTypeIndex ~= nil then
            if self.supportedFillTypes[fillTypeIndex] ~= nil then
                self:setFillLevel(fillLevel, fillTypeIndex, nil)
            else
                print("Warning: Filltype '" .. fillTypeStr .. "' not supported by Storage " .. getName(self.nodeId))
            end
        else
            print("Error: Invalid filltype '" .. fillTypeStr .. "'")
        end
    end

    local lastValidFillTypeStr = getXMLString(xmlFile, key .. "#lastValidFillType")
    if lastValidFillTypeStr ~= nil then
        local lastValidFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(lastValidFillTypeStr)
        self.lastValidFillType = lastValidFillTypeIndex
    end

    return true
end

function StrawHarvestStorageBuffer:saveToXMLFile(xmlFile, key, usedModNames)
    setXMLInt(xmlFile, key .. "#farmId", self:getOwnerFarmId())

    if self.fillLevel > 0 then
        local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(self.fillType)
        setXMLString(xmlFile, key .. "#fillType", fillTypeName)
        setXMLFloat(xmlFile, key .. "#fillLevel", self.fillLevel)
    end

    if self.lastValidFillType ~= FillType.UNKNOWN then
        local lastValidFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(self.lastValidFillType)
        setXMLString(xmlFile, key .. "#lastValidFillType", lastValidFillTypeName)
    end
end

function StrawHarvestStorageBuffer:addDependingStorageBuffer(buffer)
    assert(buffer.getIsFillTypeAllowed ~= nil)
    assert(buffer.getIsToolTypeAllowed ~= nil)
    table.insert(self.dependingStorageBuffers, buffer)
end

function StrawHarvestStorageBuffer:setFillProgressListenerFunction(func)
    self.listenerFunction = func
    -- Do initial state sync
    if func ~= nil then
        func(self:getFillProgress())
    end
end

function StrawHarvestStorageBuffer:isEmpty()
    return self.fillLevel == 0
end

function StrawHarvestStorageBuffer:empty()
    self.fillLevel = 0
    self.fillType = FillType.UNKNOWN

    if self.listenerFunction ~= nil then
        self.listenerFunction(self:getFillProgress())
    end

    if self.isServer then
        self:raiseDirtyFlags(self.storageBufferDirtyFlag)
    end
end

function StrawHarvestStorageBuffer:getIsToolTypeAllowed(toolType)
    for _, dependingStorageBuffer in ipairs(self.dependingStorageBuffers) do
        if not dependingStorageBuffer:getIsToolTypeAllowed(toolType) then
            return false
        end
    end

    return true
end

function StrawHarvestStorageBuffer:getIsFillTypeAllowed(fillType)
    if not self:getIsFillTypeSupported(fillType) then
        return false
    end

    for _, dependingStorageBuffer in ipairs(self.dependingStorageBuffers) do
        local fillLevel = dependingStorageBuffer:getFillLevel()
        if fillLevel > 0 then
            if not dependingStorageBuffer:getIsFillTypeAllowed(fillType) then
                return false
            end
        end
    end

    return fillType == self.fillType
            or (fillType ~= FillType.UNKNOWN and self.fillType == FillType.UNKNOWN)
            or self.fillLevel <= self:getFillTypeChangeThreshold()
end

function StrawHarvestStorageBuffer:getIsFillTypeSupported(fillType)
    return self.supportedFillTypes[fillType] == true
end

function StrawHarvestStorageBuffer:getFillType()
    return self.fillType
end

function StrawHarvestStorageBuffer:getLastValidFillType()
    return self.lastValidFillType
end

function StrawHarvestStorageBuffer:getFillLevel()
    return self.fillLevel
end

function StrawHarvestStorageBuffer:setFillLevel(fillLevel, fillType)
    fillLevel = MathUtil.clamp(fillLevel, 0, self.capacity)

    if self.fillLevel <= self:getFillTypeChangeThreshold() then
        self:setFillType(fillType)
    end

    if self:getIsFillTypeSupported(fillType)
            and self.fillType == fillType
            and self.fillLevel ~= fillLevel then
        self.fillLevel = fillLevel

        if self.listenerFunction ~= nil then
            self.listenerFunction(self:getFillProgress())
        end

        if self.target ~= nil then
            self.target:raiseActive()
        end

        if self.isServer then
            self:raiseDirtyFlags(self.storageBufferDirtyFlag)
        end
    end

    if self.fillLevel > 0 then
        self.lastValidFillType = fillType
    end
end

function StrawHarvestStorageBuffer:setFillType(fillType)
    if self.fillPlaneNode ~= nil then
        if fillType ~= FillType.UNKNOWN and self.fillType ~= fillType then
            local material = g_materialManager:getMaterial(fillType, "BELT", 1)
            if material ~= nil then
                setMaterial(self.fillPlaneNode, material, 0)
            end
        end
    end

    self.fillType = fillType
end

function StrawHarvestStorageBuffer:getCapacity()
    return self.capacity
end

function StrawHarvestStorageBuffer:getFreeCapacity()
    local fillLevel = self:getFillLevel()
    local capacity = self:getCapacity()
    return math.max(capacity - fillLevel, 0)
end

function StrawHarvestStorageBuffer:getFillTypeChangeThreshold()
    local capacity = self:getCapacity()
    return capacity * self.fillTypeChangeThreshold
end

function StrawHarvestStorageBuffer:getFillProgress()
    local capacity = self:getCapacity()

    if capacity > 0 then
        local progress = self:getFillLevel() / capacity
        return MathUtil.clamp(progress, 0, 1)
    end

    return 0
end

function StrawHarvestStorageBuffer:addFillLevelFromTool(farmId, deltaFillLevel, fillType, fillInfo, toolType)
    assert(deltaFillLevel >= 0)

    local movedFillLevel = 0
    if self:getIsFillTypeAllowed(fillType) and self:getIsToolTypeAllowed(toolType) then
        if self:hasFarmAccessToStorage(farmId) then
            if self:getFreeCapacity(fillType) > 0 then
                local oldFillLevel = self:getFillLevel(fillType)
                self:setFillLevel(oldFillLevel + deltaFillLevel, fillType)
                local newFillLevel = self:getFillLevel(fillType)

                movedFillLevel = movedFillLevel + (newFillLevel - oldFillLevel)
            end

            if movedFillLevel >= deltaFillLevel - 0.001 then
                movedFillLevel = deltaFillLevel
            end
        end
    end

    return movedFillLevel
end

function StrawHarvestStorageBuffer:hasFarmAccessToStorage(farmId)
    if not farmId == self:getOwnerFarmId() then
        return g_currentMission.accessHandler:canFarmAccess(farmId, self)
    end
    return true
end
