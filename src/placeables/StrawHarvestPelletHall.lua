---
-- StrawHarvestPelletHall
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Base placeable class for the pellet hall that supports the palletizer and crane.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestPelletHall
StrawHarvestPelletHall = {}

local StrawHarvestPelletHall_mt = Class(StrawHarvestPelletHall, Placeable)

InitObjectClass(StrawHarvestPelletHall, "StrawHarvestPelletHall")

function StrawHarvestPelletHall:new(isServer, isClient, mt)
    self = Placeable:new(isServer, isClient, mt or StrawHarvestPelletHall_mt)

    registerObjectClassName(self, "StrawHarvestPelletHall")
    self.savegameData = nil

    return self
end

function StrawHarvestPelletHall:delete()
    if self.palletizer ~= nil then
        self.palletizer:delete()
    end

    if self.vehicle ~= nil then
        g_currentMission:removeVehicle(self.vehicle, false)
        self.vehicle:delete()
    end

    unregisterObjectClassName(self)
    StrawHarvestPelletHall:superClass().delete(self)
end

function StrawHarvestPelletHall:load(xmlFilename, x, y, z, rx, ry, rz, initRandom)
    if not StrawHarvestPelletHall:superClass().load(self, xmlFilename, x, y, z, rx, ry, rz, initRandom) then
        return false
    end

    local xmlFile = loadXMLFile("TempXML", xmlFilename)
    local xmlVehicleFilename = getXMLString(xmlFile, "placeable.vehicle#xmlFilename")

    if xmlVehicleFilename ~= nil then
        if self.isServer then
            self.vehicle = g_currentMission:loadVehicle(Utils.getFilename(xmlVehicleFilename, self.baseDirectory), x, y, z, 0, ry, true, 0, Vehicle.PROPERTY_STATE_NONE, self:getOwnerFarmId(), nil, self.savegameData)

            if self.vehicle == nil then
                g_logManager:xmlWarning(self.configFileName, "Could not create placeable vehicle!")
                return false
            end

            -- We do our own save action
            self.vehicle.isVehicleSaved = false
            self.vehicle:removeFromPhysics()
        end
    end

    local xmlPelletizerFilename = getXMLString(xmlFile, "placeable.palletizer#xmlFilename")

    if xmlPelletizerFilename ~= nil then
        self.palletizer = StrawHarvestPalletizer:new(self.isServer, self.isClient)
        if not self.palletizer:load(Utils.getFilename(xmlPelletizerFilename, self.baseDirectory), x, y, z, rx, ry, rz, "palletizer") then
            g_logManager:xmlWarning(self.configFileName, "Could not create palletizer!")
            return false
        end
    end

    self.disableStorageBoxes = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "placeable.disableStorageBoxes#node"))

    if self.disableStorageBoxes ~= nil then
        self.storageVisuals = {}
        local i = 0
        while true do
            local visualKey = ("placeable.disableStorageBoxes.visual(%d)"):format(i)
            if not hasXMLProperty(xmlFile, visualKey) then break end
            local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, visualKey .. "#node"))
            if node ~= nil then
                table.insert(self.storageVisuals, node)
            end
            i = i + 1
        end
    end

    self:updateStorageBoxes()
    delete(xmlFile)

    return true
end

function StrawHarvestPelletHall:readStream(streamId, connection)
    StrawHarvestPelletHall:superClass().readStream(self, streamId, connection)

    if connection:getIsServer() then
        if self.palletizer ~= nil then
            local palletizerId = NetworkUtil.readNodeObjectId(streamId)
            self.palletizer:readStream(streamId, connection)
            g_client:finishRegisterObject(self.palletizer, palletizerId)
        end
    end
end

function StrawHarvestPelletHall:writeStream(streamId, connection)
    StrawHarvestPelletHall:superClass().writeStream(self, streamId, connection)

    if not connection:getIsServer() then
        if self.palletizer ~= nil then
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.palletizer))
            self.palletizer:writeStream(streamId, connection)
            g_server:registerObjectInStream(connection, self.palletizer)
        end
    end
end

function StrawHarvestPelletHall:readUpdateStream(streamId, timestamp, connection)
    StrawHarvestPelletHall:superClass().readUpdateStream(self, streamId, timestamp, connection)
end

function StrawHarvestPelletHall:writeUpdateStream(streamId, connection, dirtyMask)
    StrawHarvestPelletHall:superClass().writeUpdateStream(self, streamId, connection, dirtyMask)
end

function StrawHarvestPelletHall:loadFromXMLFile(xmlFile, key, resetVehicles)
    if hasXMLProperty(xmlFile, key .. ".vehicle") then
        self.savegameData = { xmlFile = xmlFile, key = key .. ".vehicle", resetVehicles = resetVehicles }
    end

    if not StrawHarvestPelletHall:superClass().loadFromXMLFile(self, xmlFile, key, resetVehicles) then
        return false
    end

    if self.palletizer ~= nil then
        if not self.palletizer:loadFromXMLFile(xmlFile, key .. ".pelletizer") then
            return false
        end
    end

    return true
end

function StrawHarvestPelletHall:onPreSaveToXMLFile()
    if self.vehicle ~= nil then
        self.vehicle:onPreSaveToXMLFile()
    end
end

function StrawHarvestPelletHall:saveToXMLFile(xmlFile, key, usedModNames)
    StrawHarvestPelletHall:superClass().saveToXMLFile(self, xmlFile, key, usedModNames)

    if self.palletizer ~= nil then
        self.palletizer:saveToXMLFile(xmlFile, key .. ".pelletizer", usedModNames)
    end

    if self.vehicle ~= nil then
        self.vehicle:saveToXMLFile(xmlFile, key .. ".vehicle", usedModNames)
    end
end

function StrawHarvestPelletHall:finalizePlacement()
    StrawHarvestPelletHall:superClass().finalizePlacement(self)

    if self.palletizer ~= nil then
        self.palletizer:setOwnerFarmId(self:getOwnerFarmId(), true)
        self.palletizer:register(true)
        self.palletizer:finalizePlacement()

        local missionInfo = g_currentMission.missionInfo
        if self.isServer then
            if not self.isLoadedFromSavegame or
                    (missionInfo.isValid and not (missionInfo:getIsTipCollisionValid(g_currentMission) and missionInfo:getIsPlacementCollisionValid(g_currentMission))) then
                self:setTipOcclusionAreaDirty()
            end
        end
    end

    if self.vehicle ~= nil then
        self.vehicle:addToPhysics()
    end

    self:updateStorageBoxes()
end

function StrawHarvestPelletHall:onDeleteObject(object)
    if self.vehicle == object then
        self.vehicle = nil
        self:delete()
    end
end

function StrawHarvestPelletHall:updateStorageBoxes()
    if self.disableStorageBoxes ~= nil then
        for _, node in ipairs(self.storageVisuals) do
            setVisibility(node, false)
        end

        setVisibility(self.disableStorageBoxes, false)
        removeFromPhysics(self.disableStorageBoxes)
        setRigidBodyType(self.disableStorageBoxes, "NoRigidBody")
        setCollisionMask(self.disableStorageBoxes, 0)
    end
end
