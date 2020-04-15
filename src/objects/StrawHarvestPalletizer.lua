---
-- StrawHarvestPalletizer
--
-- Author: Stijn Wopereis (Wopster) and rafftnix (FS17)
-- Purpose: Convert pellets to pallets.
--
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestPalletizer
StrawHarvestPalletizer = {}
StrawHarvestPalletizer.BAG_LIFTER_MAX_BAG_ROWS = 6
StrawHarvestPalletizer.BAGS_PER_ROW = 5

local StrawHarvestPalletizer_mt = Class(StrawHarvestPalletizer, Object)

InitObjectClass(StrawHarvestPalletizer, "StrawHarvestPalletizer")

function StrawHarvestPalletizer:onCreate()
    log("StrawHarvestPalletizer onCreate is not supported!")
end

function StrawHarvestPalletizer:new(isServer, isClient, customMt)
    local self = Object:new(isServer, isClient, customMt or StrawHarvestPalletizer_mt)
    self.nodeId = 0

    self.activeDirtyFlag = self:getNextDirtyFlag()
    self.statsDirtyFlag = self:getNextDirtyFlag()
    self.syncDirtyFlag = self:getNextDirtyFlag()

    registerObjectClassName(self, "StrawHarvestPalletizer")

    return self
end

function StrawHarvestPalletizer:load(xmlFilename, x, y, z, rx, ry, rz, key)
    self.configFileName = xmlFilename
    self.customEnvironment, self.baseDirectory = Utils.getModNameAndBaseDirectory(xmlFilename)

    local xmlFile = loadXMLFile("TempXML", xmlFilename)
    if xmlFile == 0 then
        g_logManager:error("Filename (xml) of the palletizer cannot be nil!")
        return false
    end

    local i3dFilename = getXMLString(xmlFile, key .. ".filename")
    if i3dFilename == nil then
        g_logManager:error("Filename (i3d) of the palletizer cannot be nil!")
        delete(xmlFile)
        return false
    end

    self.i3dFilename = Utils.getFilename(i3dFilename, self.baseDirectory)
    if not self:createNode(self.i3dFilename) then
        g_logManager:error("Failed to load i3d file: [%s]", self.i3dFilename)
        delete(xmlFile)
        return false
    end

    self:loadI3dMapping(xmlFile)
    self:initPose(x, y, z, rx, ry, rz)

    self.isActive = false
    self.isActiveNextFrame = false
    self.isFillingActive = false
    self.litersPerSecond = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".litersPerSecond"), 10)

    local bunkerBuffer = self:createBufferStorage(self.nodeId, xmlFile, ("%s.bunkerBuffer"):format(key))
    if bunkerBuffer ~= nil then
        self.bunkerBuffer = bunkerBuffer
    end

    local pelletizerBuffer = self:createBufferStorage(self.nodeId, xmlFile, ("%s.pelletizerBuffer"):format(key))
    if pelletizerBuffer ~= nil then
        self.pelletizerBuffer = pelletizerBuffer
        self.pelletizerBuffer:addDependingStorageBuffer(self.bunkerBuffer)
    end

    local unloadKey = ("%s.unloadTrigger"):format(key)
    local unloadPlace = UnloadTrigger:new(self.isServer, self.isClient)
    if unloadPlace:load(self.nodeId, xmlFile, unloadKey, self.bunkerBuffer) then
        unloadPlace:register(true)
        self.unloadPlace = unloadPlace
    else
        unloadPlace:delete()
    end

    local triggerNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. ".playerTrigger#node"), self.i3dMappings)
    if triggerNode == nil then
        g_logManager:error("Error: StrawHarvestPalletizer could not load player trigger.")
        return false
    end

    self.playerTriggerNode = triggerNode
    self.playerInRange = false
    addTrigger(triggerNode, "playerTriggerCallback", self)

    self.animationUtil = StrawHarvestAnimationUtil:new(self.isServer, self.isClient, self.baseDirectory)

    self:loadBagCreations(xmlFile)

    self.samples = {}
    if self.isClient then
        self.effects = g_effectManager:loadEffect(xmlFile, key .. ".effect", self.nodeId, self, self.i3dMappings)
        self.samples.work = g_soundManager:loadSampleFromXML(xmlFile, key .. ".sounds", "work", self.baseDirectory, self.nodeId, 0, AudioGroup.ENVIRONMENT, self.i3dMappings, nil)
    end

    -- Animation for the loading from bunker to the pelletizer
    self.unloadAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.unloadAnimationPackage"):format(key), self.i3dMappings)
    self.loadAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.loadAnimationPackage"):format(key), self.i3dMappings)
    self.beltBunkerAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.beltBunkerAnimationPackage"):format(key), self.i3dMappings)

    -- Add listener to the bunkerBuffer
    self.bunkerBuffer:setFillProgressListenerFunction(function(progress)
        self.animationUtil:setAnimationPackageTime(self.unloadAnimationPackage, progress)
    end)

    -- Add listener to the pelletizerBuffer
    self.pelletizerBuffer:setFillProgressListenerFunction(function(progress)
        self.animationUtil:setAnimationPackageTime(self.loadAnimationPackage, progress)
    end)

    -- Animation for bags
    self.beltBagAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.beltBagAnimationPackage"):format(key), self.i3dMappings)
    self.bagFillAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.bagFillAnimationPackage"):format(key), self.i3dMappings)
    self.bagDropAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.bagDropAnimationPackage"):format(key), self.i3dMappings)

    self.conveyorBeltGhostAnimationPackage = self.animationUtil:loadGhostAnimation(xmlFile, self.nodeId, ("%s.animationPackages.ghostAnimation"):format(key), self.i3dMappings)
    self.currentConveyorBeltGhostAnimationPackage = nil

    self.rotatoryBeltAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.animationPackages.rotatoryBeltAnimationPackage"):format(key), self.i3dMappings)

    if self.isServer then
        g_currentMission.environment:addHourChangeListener(self)
        g_currentMission.environment:addDayChangeListener(self)
    end

    delete(xmlFile)

    return true
end

function StrawHarvestPalletizer:delete()
    if self.i3dFilename ~= nil then
        g_i3DManager:releaseSharedI3DFile(self.i3dFilename, nil, true)
    end

    if self.unloadPlace ~= nil then
        self.unloadPlace:delete()
    end

    if self.bunkerBuffer ~= nil then
        self.bunkerBuffer:delete()
    end

    if self.pelletizerBuffer ~= nil then
        self.pelletizerBuffer:delete()
    end

    if self.isClient then
        g_effectManager:deleteEffects(self.effects)
        g_soundManager:deleteSamples(self.samples)
    end

    self.animationUtil:delete()

    removeTrigger(self.playerTriggerNode)
    for _, place in pairs(self.palletOutputPlaces) do
        removeTrigger(place.triggerId)
    end

    if self.nodeId ~= 0 and entityExists(self.nodeId) then
        delete(self.nodeId)
        self.nodeId = 0
    end

    if self.isServer then
        g_currentMission.environment:removeHourChangeListener(self)
        g_currentMission.environment:removeDayChangeListener(self)
    end

    unregisterObjectClassName(self)
    StrawHarvestPalletizer:superClass().delete(self)
end

function StrawHarvestPalletizer:readPositionInStream(streamId)
    local x = streamReadFloat32(streamId)
    local y = streamReadFloat32(streamId)
    local z = streamReadFloat32(streamId)
    local rx = NetworkUtil.readCompressedAngle(streamId)
    local ry = NetworkUtil.readCompressedAngle(streamId)
    local rz = NetworkUtil.readCompressedAngle(streamId)
    return x, y, z, rx, ry, rz
end

function StrawHarvestPalletizer:writePositionInStream(node, streamId)
    local x, y, z = getTranslation(node)
    local rx, ry, rz = getRotation(node)
    streamWriteFloat32(streamId, x)
    streamWriteFloat32(streamId, y)
    streamWriteFloat32(streamId, z)
    NetworkUtil.writeCompressedAngle(streamId, rx)
    NetworkUtil.writeCompressedAngle(streamId, ry)
    NetworkUtil.writeCompressedAngle(streamId, rz)
end

function StrawHarvestPalletizer:readStream(streamId, connection)
    StrawHarvestPalletizer:superClass().readStream(self, streamId, connection)

    if connection:getIsServer() then
        local i3dFilename = NetworkUtil.convertFromNetworkFilename(streamReadString(streamId))
        if self.nodeId == 0 then
            self:createNode(i3dFilename)
        end

        local bunkerId = NetworkUtil.readNodeObjectId(streamId)
        self.bunkerBuffer:readStream(streamId, connection)
        g_client:finishRegisterObject(self.bunkerBuffer, bunkerId)

        local pelletizerId = NetworkUtil.readNodeObjectId(streamId)
        self.pelletizerBuffer:readStream(streamId, connection)
        g_client:finishRegisterObject(self.pelletizerBuffer, pelletizerId)

        local unloadPlaceId = NetworkUtil.readNodeObjectId(streamId)
        self.unloadPlace:readStream(streamId, connection)
        g_client:finishRegisterObject(self.unloadPlace, unloadPlaceId)

        local animationId = NetworkUtil.readNodeObjectId(streamId)
        g_client:finishRegisterObject(self.animationUtil, animationId)

        local isActive = streamReadBool(streamId)
        self.isFillingActive = streamReadBool(streamId)
        self.animationUtil:setIsActive(self.isActive)

        local bagsToday = streamReadInt32(streamId)
        local palletsToday = streamReadInt32(streamId)
        self:setStatistics(bagsToday, palletsToday)

        -- Bag synchronisation
        self.isActive = false -- disable active state.
        self.animationUtil:setIsActive(false) -- disable animation state.

        -- Sync animation time
        --self.animationUtil:readStream(streamId, connection)

        self.currentRotatoryPattern = streamReadInt8(streamId)
        self.currentPusherPattern = streamReadInt8(streamId)
        self.currentLifterPattern = streamReadInt8(streamId)

        -- Fix initial position of first bags on the line.
        local pattern = self.bagPatterns[self.currentPusherPattern]
        local animationTime = streamReadFloat32(streamId)
        self.animationUtil:setAnimationPackageTime(pattern.pusherFirstAnimationPackage, animationTime)

        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)

        local numOfLiftNodes = streamReadInt8(streamId)

        -- Read lifter pusher bags.
        local lifterPattern = self.bagPatterns[self.currentLifterPattern]
        for i = 1, numOfLiftNodes do
            local node = self:getClonedBag(fillType)
            local x, y, z, rx, ry, rz = self:readPositionInStream(streamId)

            self:linkToNode(node, self.bagLifterBagGuideNode)
            table.insert(lifterPattern.bagNodes, node)

            setTranslation(node, x, y, z)
            setRotation(node, rx, ry, rz)
        end

        local liftAnimationTime = streamReadFloat32(streamId)
        if numOfLiftNodes ~= 0 then
            self:handBagOverToLift(liftAnimationTime)
        end

        -- Read lift bags.
        self.bagLifterCurrentBagRow = streamReadInt8(streamId)
        local numOfPalletNodes = streamReadInt8(streamId)

        if self.bagLifterCurrentBagRow > 0 then
            -- Create pallet cause we have some rows.
            if self:canCreateLiftPallet() then
                self:createLiftPallet(true)
            end
        end

        for i = 1, numOfPalletNodes do
            local node = self:getClonedBag(fillType)
            self:linkToNode(node, self.bagLifterPalletGuideNode)
            table.insert(self.bagLifterPalletNodes, node)

            local x, y, z, rx, ry, rz = self:readPositionInStream(streamId)
            setTranslation(node, x, y, z)
            setRotation(node, rx, ry, rz)
        end

        -- Read pusher bags.
        local numOfPusherNodes = streamReadInt8(streamId)
        for i = 1, numOfPusherNodes do
            local node = self:getClonedBag(fillType)
            local x, y, z, rx, ry, rz = self:readPositionInStream(streamId)

            pattern.currentRotatoryBag = node
            self:handBagOverToPusher()
            self:guideNodesMoved()

            setTranslation(node, x, y, z)
            setRotation(node, rx, ry, rz)
        end
    end
end

function StrawHarvestPalletizer:writeStream(streamId, connection)
    StrawHarvestPalletizer:superClass().writeStream(self, streamId, connection)

    if not connection:getIsServer() then
        streamWriteString(streamId, NetworkUtil.convertToNetworkFilename(self.i3dFilename))

        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.bunkerBuffer))
        self.bunkerBuffer:writeStream(streamId, connection)
        g_server:registerObjectInStream(connection, self.bunkerBuffer)

        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.pelletizerBuffer))
        self.pelletizerBuffer:writeStream(streamId, connection)
        g_server:registerObjectInStream(connection, self.pelletizerBuffer)

        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.unloadPlace))
        self.unloadPlace:writeStream(streamId, connection)
        g_server:registerObjectInStream(connection, self.unloadPlace)

        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.animationUtil))
        g_server:registerObjectInStream(connection, self.animationUtil)

        streamWriteBool(streamId, self.isActive)
        streamWriteBool(streamId, self.isFillingActive)

        streamWriteInt32(streamId, self.bagsToday)
        streamWriteInt32(streamId, self.palletsToday)

        local isActive = self.isActive
        self.isActive = false -- disable the palletizer to sync current state.
        self.animationUtil:setIsActive(false) -- disable animation state

        -- Bag synchronisation
        self:cleanBagsOnLine()

        streamWriteInt8(streamId, self.currentRotatoryPattern)
        streamWriteInt8(streamId, self.currentPusherPattern)
        streamWriteInt8(streamId, self.currentLifterPattern)

        -- Fix initial position of first bags on the line.
        local pattern = self.bagPatterns[self.currentPusherPattern]
        streamWriteFloat32(streamId, self.animationUtil:getAnimationPackageTime(pattern.pusherFirstAnimationPackage))

        local fillType = self.pelletizerBuffer:getFillType()
        if fillType == FillType.UNKNOWN then
            fillType = self.pelletizerBuffer:getLastValidFillType()
        end

        -- When still nil we force it on straw pellets.
        if fillType == nil then
            fillType = FillType.STRAWPELLETS
        end

        streamWriteUIntN(streamId, fillType, FillTypeManager.SEND_NUM_BITS)

        -- Write lifter pusher bags.
        streamWriteInt8(streamId, #self.bagLifterBags)
        for i = 1, #self.bagLifterBags do
            local node = self.bagLifterBags[i]
            self:writePositionInStream(node, streamId)
        end

        -- Write lift post position.
        local liftAnimationTime = self.animationUtil:getAnimationPackageTime(self.bagLifterMovementAnimationPackage)
        streamWriteFloat32(streamId, liftAnimationTime)

        -- Write lift bags.
        streamWriteInt8(streamId, self.bagLifterCurrentBagRow)
        streamWriteInt8(streamId, #self.bagLifterPalletNodes)
        for i = 1, #self.bagLifterPalletNodes do
            local node = self.bagLifterPalletNodes[i]
            self:writePositionInStream(node, streamId)
        end

        -- Write pusher bags.
        streamWriteInt8(streamId, #pattern.bagNodes)
        for i = 1, #pattern.bagNodes do
            local node = pattern.bagNodes[i]
            self:writePositionInStream(node, streamId)
        end

        self.isActiveNextFrame = isActive
    end
end

function StrawHarvestPalletizer:readUpdateStream(streamId, timestamp, connection)
    StrawHarvestPalletizer:superClass().readUpdateStream(self, streamId, timestamp, connection)

    if streamReadBool(streamId) then
        if not self.isActiveNextFrame then
            local isActive = self.isActive
            self.isActive = false -- disable the palletizer to sync current state.
            self.animationUtil:setIsActive(false) -- disable animation state

            -- Clean bags on other clients too.
            self:cleanBagsOnLine()
            self.isActiveNextFrame = isActive
        end
    end

    if connection:getIsServer() then
        if streamReadBool(streamId) then
            self.isActive = streamReadBool(streamId)
            self.isFillingActive = streamReadBool(streamId)
            self.animationUtil:setIsActive(self.isActive)
        end

        if streamReadBool(streamId) then
            local bagsToday = streamReadUInt16(streamId)
            local palletsToday = streamReadUInt16(streamId)
            self:setStatistics(bagsToday, palletsToday)
        end
    end
end

function StrawHarvestPalletizer:writeUpdateStream(streamId, connection, dirtyMask)
    StrawHarvestPalletizer:superClass().writeUpdateStream(self, streamId, connection, dirtyMask)

    streamWriteBool(streamId, bitAND(dirtyMask, self.syncDirtyFlag) ~= 0)
    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, self.activeDirtyFlag) ~= 0) then
            streamWriteBool(streamId, self.isActive)
            streamWriteBool(streamId, self.isFillingActive)
        end

        if streamWriteBool(streamId, bitAND(dirtyMask, self.statsDirtyFlag) ~= 0) then
            streamWriteUInt16(streamId, self.bagsToday)
            streamWriteUInt16(streamId, self.palletsToday)
        end
    end
end

function StrawHarvestPalletizer:update(dt)
    StrawHarvestPalletizer:superClass().update(self, dt)

    if self.isServer and self.isActiveNextFrame then
        self:raiseDirtyFlags(self.syncDirtyFlag)
    end

    if self.isActive then
        self:raiseActive()
    end

    if self.isServer then
        local isFilling = self:fillPalletizer(dt)
        self:checkActiveState(isFilling)
    end

    if self.isClient then
        if self.animationUtil:isAnimationPackagePlaying(self.beltBagAnimationPackage) ~= self.isActive then
            self.animationUtil:setIsAnimationPackagePlaying(self.beltBagAnimationPackage, self.isActive)
        end

        if self.animationUtil:isAnimationPackagePlaying(self.beltBunkerAnimationPackage) ~= self.isFillingActive then
            self.animationUtil:setIsAnimationPackagePlaying(self.beltBunkerAnimationPackage, self.isFillingActive)
        end

        local pattern = self.bagPatterns[self.currentRotatoryPattern]
        if pattern ~= nil then
            local isActive = self.animationUtil:isAnimationPackagePlaying(pattern.rotatoryAnimationPackage)
            self.animationUtil:setIsAnimationPackagePlaying(self.rotatoryBeltAnimationPackage, not isActive)
        end

        if self.playerInRange then
            self:showStatistics()
            self:raiseActive()
        end

        self:setEffectActive(self.isFillingActive)

        if self.isActive then
            if not g_soundManager:getIsSamplePlaying(self.samples.work) then
                g_soundManager:playSample(self.samples.work)
            end
        else
            if g_soundManager:getIsSamplePlaying(self.samples.work) then
                g_soundManager:stopSample(self.samples.work)
            end
        end
    end

    if self.isActive then
        if self:canCreateBag() then
            self:createBag()
        end

        if self:canCreateLiftPallet() then
            self:createLiftPallet(false)
        end
    end

    if self.isServer and self.createPalletNextFrameFromSave then
        local fillType = self.pelletizerBuffer:getFillType()
        if fillType == FillType.UNKNOWN then
            fillType = self.pelletizerBuffer:getLastValidFillType()
        end

        local outputPlaceIndex = self:getNextOutputPlace(1)
        self:createPallet(outputPlaceIndex, fillType)
        self.createPalletNextFrameFromSave = false
    end

    if self.isActiveNextFrame then
        self.isActive = true -- set the actual state after sync
        self.animationUtil:setIsActive(self.isActive) -- set the animation state depending on the last synced active state.
        self.isActiveNextFrame = false
    end
end

function StrawHarvestPalletizer:fillPalletizer(dt)
    local bunkerFillLevel = self.bunkerBuffer:getFillLevel()
    local bunkerFillType = self.bunkerBuffer:getFillType()
    local palletizerFillProgress = self.pelletizerBuffer:getFillProgress()

    local thresholdReached = false
    if bunkerFillLevel > 0 and self.pelletizerBuffer:getIsFillTypeAllowed(bunkerFillType) then
        if not self.isFillingActive and palletizerFillProgress < 0.5 then
            thresholdReached = true
        end
    end

    local delta = 0
    if self.isFillingActive then
        local palletizerFillLevel = self.pelletizerBuffer:getFillLevel()
        local palletizerFreeCapacity = self.pelletizerBuffer:getFreeCapacity()
        delta = math.min(bunkerFillLevel, self.litersPerSecond * dt * 0.001, palletizerFreeCapacity)

        self.pelletizerBuffer:setFillLevel(palletizerFillLevel + delta, bunkerFillType)
        self.bunkerBuffer:setFillLevel(bunkerFillLevel - delta, bunkerFillType)
    end

    return delta > 0 or thresholdReached
end

function StrawHarvestPalletizer:checkActiveState(isFillingActive)
    if self.isServer then
        local isActive = isFillingActive or self.pelletizerBuffer:getFillProgress() > 0
        if isActive and not self:hasAvailableOutputPlaces() then
            if self.bagLifterCurrentBagRow >= StrawHarvestPalletizer.BAG_LIFTER_MAX_BAG_ROWS
                    or #self.palletConveyorBags > 0 then
                isActive = false
            end
        end

        if self.isActive ~= isActive or self.isFillingActive ~= isFillingActive then
            if not isActive then
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, g_i18n:getText("notification_palletizer_stopped"))
            end

            self.isActive = isActive
            self.isFillingActive = isFillingActive
            self:raiseDirtyFlags(self.activeDirtyFlag)
            self.animationUtil:setIsActive(isActive)
        end
    end
end

function StrawHarvestPalletizer:loadFromXMLFile(xmlFile, key)
    local bunkerKey = ("%s.bunkerBuffer"):format(key)
    if not self.bunkerBuffer:loadFromXMLFile(xmlFile, bunkerKey) then
        return false
    end

    local pelletizerKey = ("%s.pelletizerBuffer"):format(key)
    if not self.pelletizerBuffer:loadFromXMLFile(xmlFile, pelletizerKey) then
        return false
    end

    self.createPalletNextFrameFromSave = Utils.getNoNil(getXMLBool(xmlFile, key .. ".isPalletMovingToDestination"), false)
    self.bagsToday = Utils.getNoNil(getXMLInt(xmlFile, key .. ".bagsToday"), self.bagsToday)
    self.palletsToday = Utils.getNoNil(getXMLInt(xmlFile, key .. ".palletsToday"), self.palletsToday)
    self.currentRotatoryPattern = Utils.getNoNil(getXMLInt(xmlFile, key .. ".currentRotatoryPattern"), self.currentRotatoryPattern)
    self.currentPusherPattern = Utils.getNoNil(getXMLInt(xmlFile, key .. ".currentPusherPattern"), self.currentPusherPattern)
    self.currentLifterPattern = Utils.getNoNil(getXMLInt(xmlFile, key .. ".currentLifterPattern"), self.currentLifterPattern)

    local fillType = self.pelletizerBuffer:getFillType()
    if fillType == FillType.UNKNOWN then
        fillType = self.pelletizerBuffer:getLastValidFillType()
    end

    --Always do lift bags first, because animation order.
    local liftKey = ("%s.liftBags"):format(key)
    if liftKey ~= nil then
        local i = 0
        local lifterPattern = self.bagPatterns[self.currentLifterPattern]
        while i < StrawHarvestPalletizer.BAGS_PER_ROW do
            local bagKey = ("%s.bag(%d)"):format(liftKey, i)
            if not hasXMLProperty(xmlFile, bagKey) then break end

            local node = self:getClonedBag(fillType)
            local translation = StringUtil.getVectorNFromString(getXMLString(xmlFile, bagKey .. "#position"), 3)
            local rotation = StringUtil.getRadiansFromString(getXMLString(xmlFile, bagKey .. "#rotation"), 3)

            self:linkToNode(node, self.bagLifterBagGuideNode)
            table.insert(lifterPattern.bagNodes, node)

            setTranslation(node, unpack(translation))
            setRotation(node, unpack(rotation))

            i = i + 1
        end

        if i ~= 0 then
            local liftAnimationTime = getXMLFloat(xmlFile, liftKey .. "#liftAnimationTime")
            self:handBagOverToLift(liftAnimationTime)
        end
    end

    local patternKey = ("%s.pusherBags"):format(key)
    if patternKey ~= nil then
        local pattern = self.bagPatterns[self.currentPusherPattern]
        local i = 0
        while i < StrawHarvestPalletizer.BAGS_PER_ROW do
            local bagKey = ("%s.bag(%d)"):format(patternKey, i)
            if not hasXMLProperty(xmlFile, bagKey) then break end

            local node = self:getClonedBag(fillType)
            local translation = StringUtil.getVectorNFromString(getXMLString(xmlFile, bagKey .. "#position"), 3)
            local rotation = StringUtil.getRadiansFromString(getXMLString(xmlFile, bagKey .. "#rotation"), 3)

            pattern.currentRotatoryBag = node
            self:handBagOverToPusher() -- todo: perhaps skip animation.
            self:guideNodesMoved()

            setTranslation(node, unpack(translation))
            setRotation(node, unpack(rotation))

            i = i + 1
        end
    end

    local palletKey = ("%s.palletBags"):format(key)
    local rows = getXMLInt(xmlFile, palletKey .. "#bagRows")

    if rows ~= nil and rows > 0 then
        -- Create pallet cause we have some rows.
        if self:canCreateLiftPallet() then
            self:createLiftPallet(true)
        end

        -- Make sure we don't load more than the max.
        self.bagLifterCurrentBagRow = math.min(rows, self.bagLifterNumBagRowsOnPallet)
        local maxAmountOfBags = self.bagLifterCurrentBagRow * StrawHarvestPalletizer.BAGS_PER_ROW
        local i = 0
        while i < maxAmountOfBags do
            local bagKey = ("%s.bag(%d)"):format(palletKey, i)
            if not hasXMLProperty(xmlFile, bagKey) then break end

            local node = self:getClonedBag(fillType)
            self:linkToNode(node, self.bagLifterPalletGuideNode)
            table.insert(self.bagLifterPalletNodes, node)

            local translation = StringUtil.getVectorNFromString(getXMLString(xmlFile, bagKey .. "#position"), 3)
            local rotation = StringUtil.getRadiansFromString(getXMLString(xmlFile, bagKey .. "#rotation"), 3)

            setTranslation(node, unpack(translation))
            setRotation(node, unpack(rotation))

            i = i + 1
        end
    end

    self:raiseActive()

    return true
end

function StrawHarvestPalletizer:saveToXMLFile(xmlFile, key, usedModNames)
    local isActive = self.isActive
    self.isActive = false -- disable the palletizer to properly save the current state.
    self.animationUtil:setIsActive(false) -- disable animation state.

    setXMLInt(xmlFile, key .. "#farmId", self:getOwnerFarmId())

    local bunkerKey = ("%s.bunkerBuffer"):format(key)
    self.bunkerBuffer:saveToXMLFile(xmlFile, bunkerKey, usedModNames)

    local pelletizerKey = ("%s.pelletizerBuffer"):format(key)
    self.pelletizerBuffer:saveToXMLFile(xmlFile, pelletizerKey, usedModNames)

    setXMLBool(xmlFile, key .. ".isPalletMovingToDestination", self.isPalletMovingToDestination)
    setXMLInt(xmlFile, key .. ".bagsToday", self.bagsToday)
    setXMLInt(xmlFile, key .. ".palletsToday", self.palletsToday)
    setXMLInt(xmlFile, key .. ".currentRotatoryPattern", self.currentRotatoryPattern)
    setXMLInt(xmlFile, key .. ".currentPusherPattern", self.currentPusherPattern)
    setXMLInt(xmlFile, key .. ".currentLifterPattern", self.currentLifterPattern)

    self:cleanBagsOnLine()

    local function saveBag(bagKey, node)
        local x, y, z = getTranslation(node)
        local xRot, yRot, zRot = getRotation(node)
        setXMLString(xmlFile, bagKey .. "#position", ("%.4f %.4f %.4f"):format(x, y, z))
        setXMLString(xmlFile, bagKey .. "#rotation", ("%.4f %.4f %.4f"):format(math.deg(xRot), math.deg(yRot), math.deg(zRot)))
    end

    local pattern = self.bagPatterns[self.currentPusherPattern]
    if pattern.numOfBags > 0 then
        local patternKey = ("%s.pusherBags"):format(key)
        for i, node in ipairs(pattern.bagNodes) do
            local bagKey = ("%s.bag(%d)"):format(patternKey, i - 1)
            saveBag(bagKey, node)
        end
    end

    local liftKey = ("%s.liftBags"):format(key)
    local liftAnimationTime = self.animationUtil:getAnimationPackageTime(self.bagLifterMovementAnimationPackage)
    setXMLFloat(xmlFile, liftKey .. "#liftAnimationTime", liftAnimationTime)

    for i, node in ipairs(self.bagLifterBags) do
        local bagKey = ("%s.bag(%d)"):format(liftKey, i - 1)
        saveBag(bagKey, node)
    end

    local palletKey = ("%s.palletBags"):format(key)
    -- Get the actual bag row by counting the bagLifterPalletNodes and divide by bags per row.
    local rows = #self.bagLifterPalletNodes / StrawHarvestPalletizer.BAGS_PER_ROW
    setXMLInt(xmlFile, palletKey .. "#bagRows", math.min(rows, self.bagLifterCurrentBagRow))
    for i, node in ipairs(self.bagLifterPalletNodes) do
        local bagKey = ("%s.bag(%d)"):format(palletKey, i - 1)
        saveBag(bagKey, node)
    end

    self.isActiveNextFrame = isActive
end

function StrawHarvestPalletizer:cleanBagsOnLine()
    local numOfBagsLeft = 0
    numOfBagsLeft = numOfBagsLeft + self:removeActiveBag(self.currentBag, self.bagFillAnimationPackage)
    numOfBagsLeft = numOfBagsLeft + self:removeActiveBag(self.currentDropBag, self.bagDropAnimationPackage)
    local rotatoryPattern = self.bagPatterns[self.currentRotatoryPattern]
    numOfBagsLeft = numOfBagsLeft + self:removeActiveBag(rotatoryPattern.currentRotatoryBag, self.currentConveyorBeltGhostAnimationPackage)

    -- Remove all ghost animations on the belt and reset callbacks.
    numOfBagsLeft = numOfBagsLeft + self.animationUtil:resetGhostPackages()
    if self.isServer and numOfBagsLeft > 0 then
        local fillType = self.pelletizerBuffer:getFillType()
        if fillType == FillType.UNKNOWN then
            fillType = self.pelletizerBuffer:getLastValidFillType()
        end

        local palletizerFillLevel = self.pelletizerBuffer:getFillLevel()
        local delta = numOfBagsLeft * self.literPerBag
        self.pelletizerBuffer:setFillLevel(palletizerFillLevel + delta, fillType)

        if numOfBagsLeft ~= 0 then
            self:setStatistics(self.bagsToday - numOfBagsLeft, self.palletsToday)
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, g_i18n:getText("notification_palletizer_refilled"):format(numOfBagsLeft))
        end
    end
end

function StrawHarvestPalletizer:removeActiveBag(bag, animationPackage)
    if bag ~= nil then
        if animationPackage ~= nil then
            self.animationUtil:stopAnimationPackage(animationPackage)
            self.animationUtil:setAnimationPackageTime(animationPackage, 0)
        end

        self:removeClonedBag(bag)
        bag = nil

        return 1
    end

    return 0
end

function StrawHarvestPalletizer:finalizePlacement()
    addToPhysics(self.nodeId)

    local farmId = self:getOwnerFarmId()
    self.bunkerBuffer:setOwnerFarmId(farmId, true)
    self.bunkerBuffer:register(true)
    self.pelletizerBuffer:setOwnerFarmId(farmId, true)
    self.pelletizerBuffer:register(true)

    -- Todo: might want to get rid of it.
    self.animationUtil:setOwnerFarmId(farmId, true)
    self.animationUtil:register(true)
end

function StrawHarvestPalletizer:collectPickObjects(node)
    if not node == self.unloadPlace.exactFillRootNode then
        StrawHarvestPalletizer:superClass().collectPickObjects(self, node)
    end
end

function StrawHarvestPalletizer:initPose(x, y, z, rx, ry, rz)
    setTranslation(self.nodeId, x, y, z)
    setRotation(self.nodeId, rx, ry, rz)
end

---Creates a new storage object and loads it.
function StrawHarvestPalletizer:createBufferStorage(node, xmlFile, key)
    local buffer = StrawHarvestStorageBuffer:new(self.isServer, self.isClient)
    if not buffer:load(node, xmlFile, key, self.i3dMappings, self) then
        buffer:delete()

        return nil
    end

    return buffer
end

function StrawHarvestPalletizer:createNode(i3dFilename)
    self.i3dFilename = i3dFilename
    local root = g_i3DManager:loadSharedI3DFile(i3dFilename, nil, false, false)
    if root == 0 then
        return false
    end

    local nodeId = getChildAt(root, 0)
    link(getRootNode(), nodeId)
    delete(root)

    self.nodeId = nodeId

    return true
end

function StrawHarvestPalletizer:loadI3dMapping(xmlFile)
    self.i3dMappings = {}

    local i = 0
    while true do
        local key = ("palletizer.i3dMappings.i3dMapping(%d)"):format(i)
        if not hasXMLProperty(xmlFile, key) then break end

        local id = getXMLString(xmlFile, key .. "#id")
        local node = getXMLString(xmlFile, key .. "#node")
        if id ~= nil and node ~= nil then
            -- As we are not using components with placeables we replace the 0> prefixes.
            node = node:gsub("0>", "")
            if node ~= "" then
                self.i3dMappings[id] = node
            end
        end

        i = i + 1
    end
end

function StrawHarvestPalletizer:loadGuideNodes(xmlFile, baseKey)
    local nodes = {}
    local i = 0
    while true do
        local key = ("%s.guideNode(%d)"):format(baseKey, i)
        if not hasXMLProperty(xmlFile, key) then break end

        local node = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. "#node"), self.i3dMappings)
        table.insert(nodes, node)

        i = i + 1
    end

    return nodes
end

function StrawHarvestPalletizer:loadBagCreationPatterns(xmlFile)
    self.bagPatterns = {}
    self.currentRotatoryPattern = 1
    self.currentPusherPattern = 1
    self.currentLifterPattern = 1

    local i = 0
    while true do
        local key = ("palletizer.bagCreations.patterns.pattern(%d)"):format(i)
        if not hasXMLProperty(xmlFile, key) then break end

        local pattern = {}

        pattern.numOfBags = 0
        pattern.guideNodes = self:loadGuideNodes(xmlFile, key .. ".guideNodes")
        pattern.bagNodes = {}
        pattern.rotatoryAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.rotatory.rotatoryAnimationPackage"):format(key), self.i3dMappings)
        pattern.rotatoryGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. ".rotatory#guideNode"), self.i3dMappings)
        pattern.rotatoryPlayPattern = StringUtil.getVectorNFromString(getXMLString(xmlFile, key .. ".rotatory#playPattern"), 5)
        pattern.firstMovementBagThreshold = Utils.getNoNil(getXMLInt(xmlFile, key .. "#firstMovementBagThreshold"), 0)
        pattern.secondMovementBagThreshold = Utils.getNoNil(getXMLInt(xmlFile, key .. "#secondMovementBagThreshold"), 0)
        pattern.firstMovementAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.firstMovementAnimationPackage"):format(key), self.i3dMappings)
        pattern.secondMovementAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.secondMovementAnimationPackage"):format(key), self.i3dMappings)
        pattern.pusherFirstAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.pusher.pusherFirstAnimationPackage"):format(key), self.i3dMappings)
        pattern.pusherPushThroughAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, ("%s.pusher.pusherPushThroughAnimationPackage"):format(key), self.i3dMappings)

        -- Set the animation time of the first animation to set the correct post position.
        self.animationUtil:setAnimationPackageTime(pattern.pusherFirstAnimationPackage, 0)
        table.insert(self.bagPatterns, pattern)

        i = i + 1
    end
end

function StrawHarvestPalletizer:loadPalletOutputPlaces(xmlFile)
    self.movePalletToDestinationAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, "palletizer.palletOutput.movePalletToDestinationAnimationPackage", self.i3dMappings)
    self.isPalletMovingToDestination = false
    self.createPalletNextFrameFromSave = false
    self.palletOutputGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.palletOutput#palletGuideNode"), self.i3dMappings)
    self.palletOutputPlacesByTrigger = {}
    self.palletOutputPlaces = {}

    local duration = self.animationUtil:getAnimationPackageDuration(self.movePalletToDestinationAnimationPackage)
    local i = 0
    while true do
        local key = ("palletizer.palletOutput.places.place(%d)"):format(i)
        if not hasXMLProperty(xmlFile, key) then break end

        local place = {}
        local triggerId = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. "#triggerNode"), self.i3dMappings)
        if triggerId ~= nil then
            place.triggerId = triggerId
            addTrigger(triggerId, "outputPlaceTriggerCallback", self)
            place.numOfObjectsInTrigger = 0
            place.objectsInTrigger = {}
            place.animationTime = getXMLFloat(xmlFile, key .. "#animationTime") * duration
            place.spawnOffset = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#spawnOffset"), 0)
            self.palletOutputPlacesByTrigger[triggerId] = place

            table.insert(self.palletOutputPlaces, place)
        end

        i = i + 1
    end
end

function StrawHarvestPalletizer:loadPalletConveyor(xmlFile)
    self.conveyorMovePalletOutAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, "palletizer.conveyor.conveyorMovePalletOutAnimationPackage", self.i3dMappings)
    self.conveyorPalletGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.conveyor#palletGuideNode"), self.i3dMappings)
    self.palletConveyorBags = {}
    self.palletConveyorPallet = nil
end

function StrawHarvestPalletizer:loadPalletStacker(xmlFile)
    self.palletStackerDeliverPalletAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, "palletizer.palletStacker.palletStackerDeliverPalletAnimationPackage", self.i3dMappings)
    self.palletGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.palletStacker#palletGuideNode"), self.i3dMappings)
    self.palletCloneNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.palletStacker#palletCloneNode"), self.i3dMappings)
end

function StrawHarvestPalletizer:loadBagLifter(xmlFile)
    self.bagLifterMovementAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, "palletizer.bagLifter.bagLifterMovementAnimationPackage", self.i3dMappings)
    self.bagLifterPutBagsOnPalletAnimationPackage = self.animationUtil:loadAnimationPackage(xmlFile, self.nodeId, "palletizer.bagLifter.bagLifterPutBagsOnPalletAnimationPackage", self.i3dMappings)
    self.bagLifterPalletGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.bagLifter#palletGuideNode"), self.i3dMappings)
    self.bagLifterBagGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.bagLifter#bagGuideNode"), self.i3dMappings)

    local duration = self.animationUtil:getAnimationPackageDuration(self.bagLifterMovementAnimationPackage)
    self.bagLifterMinAnimationTime = getXMLFloat(xmlFile, "palletizer.bagLifter#minAnimationTime") * duration
    self.bagLifterMaxAnimationTime = getXMLFloat(xmlFile, "palletizer.bagLifter#maxAnimationTime") * duration
    self.bagLifterLoadPosAnimationTime = getXMLFloat(xmlFile, "palletizer.bagLifter#loadPosAnimationTime") * duration
    self.animationUtil:setAnimationPackageTime(self.bagLifterMovementAnimationPackage, self.bagLifterLoadPosAnimationTime / duration)

    self.bagLifterAnimationTimePerBagLayer = getXMLFloat(xmlFile, "palletizer.bagLifter#animationTimePerBagLayer") * duration
    self.bagLifterNumBagRowsOnPallet = getXMLInt(xmlFile, "palletizer.bagLifter#numBagRowsOnPallet")
    self.bagLifterCurrentBagRow = 0
    self.bagLifterBags = {}
    self.bagLifterPalletNodes = {}
end

function StrawHarvestPalletizer:loadBagCreations(xmlFile)
    self.literPerBag = Utils.getNoNil(getXMLFloat(xmlFile, "palletizer.bagCreations#literPerBag"), 35)
    self.costPerBag = Utils.getNoNil(getXMLFloat(xmlFile, "palletizer.bagCreations#costPerBag"), 1.25)
    self.hourlyCosts = 0
    self.bagsToday = 0
    self.palletsToday = 0

    self.bagFillGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.bagCreations#fillGuideNode"), self.i3dMappings)
    self.bagDropGuideNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, "palletizer.bagCreations#dropGuideNode"), self.i3dMappings)
    self.currentBag = nil
    self.currentDropBag = nil
    self.fillTypeToCloneableBag = {}
    self.fillTypeToDecisionWeight = {}
    self.clonedBagToFillType = {}
    self.fillTypeToPalletXML = {}

    local i = 0
    while true do
        local key = ("palletizer.bagCreations.bagCreation(%d)"):format(i)
        if not hasXMLProperty(xmlFile, key) then break end

        local fillType = getXMLString(xmlFile, key .. "#fillType")
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillType)
        local decisionWeight = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#fillTypeDecisionWeight"), 1)
        local cloneNode = I3DUtil.indexToObject(self.nodeId, getXMLString(xmlFile, key .. "#cloneNode"), self.i3dMappings)
        local palletXMLFilename = Utils.getNoNil(getXMLString(xmlFile, key .. "#palletXMLFilename"), "")

        if fillTypeIndex ~= nil and cloneNode ~= nil then
            self.fillTypeToCloneableBag[fillTypeIndex] = cloneNode
            self.fillTypeToDecisionWeight[fillTypeIndex] = decisionWeight
            self.fillTypeToPalletXML[fillTypeIndex] = Utils.getFilename(palletXMLFilename, self.baseDirectory)
        end

        i = i + 1
    end

    self:loadBagCreationPatterns(xmlFile)
    self:loadBagLifter(xmlFile)
    self:loadPalletStacker(xmlFile)
    self:loadPalletConveyor(xmlFile)
    self:loadPalletOutputPlaces(xmlFile)
end

function StrawHarvestPalletizer:setEffectActive(isActive)
    if isActive then
        if self.effects ~= nil then
            local lastValidFillType = self.bunkerBuffer:getFillType()
            g_effectManager:setFillType(self.effects, lastValidFillType)
            g_effectManager:startEffects(self.effects)
        end
    else
        if self.effects ~= nil then
            g_effectManager:stopEffects(self.effects)
        end
    end
end

---Sets the palletizer statistics of today.
function StrawHarvestPalletizer:setStatistics(numOfBags, numOfPallets)
    self.bagsToday = numOfBags
    self.palletsToday = numOfPallets

    if self.isServer then
        self:raiseDirtyFlags(self.statsDirtyFlag)
    end
end

---Shows the palletizer statistics of today as extra print text in the HUD.
function StrawHarvestPalletizer:showStatistics()
    local statsText = g_i18n:getText("statistics_palletizer_bags"):format(self.bagsToday, self.palletsToday)
    g_currentMission:addExtraPrintText(statsText)

    local capacity = self.pelletizerBuffer:getCapacity()
    local bunkerFillLevel = self.bunkerBuffer:getFillLevel()
    local fillLevel = self.pelletizerBuffer:getFillLevel()

    local numBagToGoLeft = (fillLevel + bunkerFillLevel) / self.literPerBag
    local numMinutesLeft = (numBagToGoLeft * self.animationUtil:getAnimationPackageDuration(self.bagFillAnimationPackage) * 0.001) / 60
    local timeText = g_i18n:getText("statistics_palletizer_time"):format(math.floor(numMinutesLeft), math.floor((numMinutesLeft - math.floor(numMinutesLeft)) * 60))
    g_currentMission:addExtraPrintText(timeText)

    local fillType = g_fillTypeManager:getFillTypeByIndex(self.pelletizerBuffer:getFillType())
    local fillTypeName = fillType ~= nil and fillType.title or ""
    local fillInfoText = string.format(g_i18n:getText("info_fillLevel") .. " %s: %s (%d%%)", fillTypeName, g_i18n:formatFluid(fillLevel), math.floor(100 * fillLevel / capacity))
    g_currentMission:addExtraPrintText(fillInfoText)

    if not self.isActive and not self:hasAvailableOutputPlaces() then
        g_currentMission:addExtraPrintText(g_i18n:getText("statistics_palletizer_blocked"))
    end
end

function StrawHarvestPalletizer:hasBlockingOutputNeighbour(nextIndex)
    local nextPlace = self.palletOutputPlaces[nextIndex]
    local isBlocking = nextPlace.numOfObjectsInTrigger > 0

    local neighbourIndex = nextIndex + 1
    if not isBlocking and neighbourIndex <= #self.palletOutputPlaces then
        return self:hasBlockingOutputNeighbour(neighbourIndex)
    end

    return isBlocking
end

function StrawHarvestPalletizer:hasAvailableOutputPlaces()
    local startIndex = 1
    local placeIndex = self:getNextOutputPlace(startIndex)

    -- Check if the next place is actually available, else check the neighbour
    local isBlocking = placeIndex == nil
    if not isBlocking then
        isBlocking = self:hasBlockingOutputNeighbour(math.min(placeIndex + 1, #self.palletOutputPlaces))
    end

    return not isBlocking
end

function StrawHarvestPalletizer:getNextOutputPlace(index)
    local nextIndex = index
    if nextIndex > #self.palletOutputPlaces then
        return nil -- all full
    end

    local place = self.palletOutputPlaces[nextIndex]
    if place.numOfObjectsInTrigger > 0 then
        return self:getNextOutputPlace(nextIndex + 1)
    end

    return nextIndex
end

function StrawHarvestPalletizer:canCreateBag()
    if self.animationUtil:isAnimationPackagePlaying(self.bagFillAnimationPackage) then
        return false
    end

    local fillLevel = self.pelletizerBuffer:getFillLevel()
    local fillType = self.pelletizerBuffer:getFillType()
    return fillLevel > 0 and fillType ~= FillType.UNKNOWN
end

function StrawHarvestPalletizer:createBag()
    local fillType = self.pelletizerBuffer:getFillType()

    if self.isServer then
        local fillLevel = self.pelletizerBuffer:getFillLevel()
        local delta = -self.literPerBag
        self.pelletizerBuffer:setFillLevel(fillLevel + delta, fillType)

        if self.pelletizerBuffer:isEmpty() then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, g_i18n:getText("notification_palletizer_empty"))
        end

        self.hourlyCosts = self.hourlyCosts + self.costPerBag
        self:setStatistics(self.bagsToday + 1, self.palletsToday)
    end

    self.currentBag = self:getClonedBag(fillType)

    link(self.bagFillGuideNode, self.currentBag)
    setTranslation(self.currentBag, 0, 0, 0)

    self.animationUtil:playAnimationPackage(self.bagFillAnimationPackage, 0, self.processBag, self)
end

function StrawHarvestPalletizer:canCreateLiftPallet()
    return self.currentLiftPallet == nil and not self.animationUtil:isAnimationPackagePlaying(self.palletStackerDeliverPalletAnimationPackage)
end

function StrawHarvestPalletizer:createLiftPallet(setInitialPosition)
    self.currentLiftPallet = clone(self.palletCloneNode, false, false, false)
    link(self.palletGuideNode, self.currentLiftPallet)
    setTranslation(self.currentLiftPallet, 0, 0, 0)
    setVisibility(self.currentLiftPallet, true)

    if setInitialPosition then
        local duration = self.animationUtil:getAnimationPackageDuration(self.palletStackerDeliverPalletAnimationPackage)
        self.animationUtil:setAnimationPackageTime(self.palletStackerDeliverPalletAnimationPackage, duration)
        self:handOverPallet()
    else
        self.animationUtil:playAnimationPackage(self.palletStackerDeliverPalletAnimationPackage, 0, self.handOverPallet, self)
    end
end

function StrawHarvestPalletizer:getClonedBag(fillType)
    local cloneNode = self.fillTypeToCloneableBag[fillType]
    local node = clone(cloneNode, false, false, false)
    self.clonedBagToFillType[node] = fillType
    return node
end

function StrawHarvestPalletizer:removeClonedBag(node)
    self.clonedBagToFillType[node] = nil
    if entityExists(node) then
        delete(node)
    end
end

function StrawHarvestPalletizer:processBag()
    local node = self.currentBag
    self.currentDropBag = node
    self.currentBag = nil

    self:linkToNode(node, self.bagDropGuideNode)
    self.animationUtil:playAnimationPackage(self.bagDropAnimationPackage, 0, self.handBagOverToBelt, self)
end

function StrawHarvestPalletizer:handBagOverToBelt()
    unlink(self.currentDropBag)

    local bag = self.currentDropBag or self:getClonedBag(self.pelletizerBuffer:getFillType())
    -- The identifier "bag" is linked to an animation.
    local nodes = { ["bag"] = bag }
    setTranslation(self.currentDropBag, 0, 0, 0)
    self.currentDropBag = nil

    local package = self.animationUtil:createGhostPackage(self.conveyorBeltGhostAnimationPackage, nodes)
    self.currentConveyorBeltGhostAnimationPackage = package
    self.animationUtil:playAnimationPackage(package, 0, self.handBagOverToRotatory, self, { package, nodes })
end

function StrawHarvestPalletizer:handBagOverToRotatory(package, nodes)
    self.animationUtil:deleteGhostPackage(package, false)
    self.currentConveyorBeltGhostAnimationPackage = nil

    local pattern = self.bagPatterns[self.currentRotatoryPattern]
    if nodes ~= nil then
        -- Rescue deleted bag by saving/sync.
        if not entityExists(nodes["bag"]) then
            nodes["bag"] = self:getClonedBag(self.pelletizerBuffer:getFillType())
        end
    end

    pattern.currentRotatoryBag = nodes ~= nil and nodes["bag"] or self:getClonedBag(self.pelletizerBuffer:getFillType())

    self.animationUtil:setAnimationPackageTime(pattern.rotatoryAnimationPackage, 0)

    self:linkToNode(pattern.currentRotatoryBag, pattern.rotatoryGuideNode)

    local playPatternIndex = pattern.numOfBags + 1
    if pattern.rotatoryPlayPattern[playPatternIndex] == 1 then
        -- numBags will be increased later, here we start the first bag at numBags==0
        self.animationUtil:playAnimationPackage(pattern.rotatoryAnimationPackage, 0, self.handBagOverToPusher, self)
    else
        self:handBagOverToPusher()
    end
end

function StrawHarvestPalletizer:handBagOverToPusher()
    local pattern = self.bagPatterns[self.currentPusherPattern]
    pattern.numOfBags = pattern.numOfBags + 1

    -- Rescue deleted bag by saving/sync.
    if not entityExists(pattern.currentRotatoryBag) then
        pattern.currentRotatoryBag = self:getClonedBag(self.pelletizerBuffer:getFillType())
    end

    self:linkToNode(pattern.currentRotatoryBag, pattern.guideNodes[math.min(pattern.numOfBags, #pattern.guideNodes)])
    setTranslation(pattern.currentRotatoryBag, 0, 0, 0)

    table.insert(pattern.bagNodes, pattern.currentRotatoryBag)
    pattern.currentRotatoryBag = nil

    if pattern.numOfBags <= pattern.firstMovementBagThreshold then
        local duration = self.animationUtil:getAnimationPackageDuration(pattern.firstMovementAnimationPackage)
        local startTime = ((pattern.numOfBags - 1) / pattern.firstMovementBagThreshold) * duration
        local stopTime = (pattern.numOfBags / pattern.firstMovementBagThreshold) * duration
        self.animationUtil:playAnimationPackageUntil(pattern.firstMovementAnimationPackage, startTime, stopTime, self.guideNodesMoved, self)
    elseif pattern.numOfBags <= pattern.secondMovementBagThreshold then
        if pattern.numOfBags == pattern.secondMovementBagThreshold then
            self.currentRotatoryPattern = self.currentRotatoryPattern + 1
            if self.currentRotatoryPattern > #self.bagPatterns then
                self.currentRotatoryPattern = 1
            end
        end

        local duration = self.animationUtil:getAnimationPackageDuration(pattern.secondMovementAnimationPackage)
        local startTime = ((pattern.numOfBags - 1 - pattern.firstMovementBagThreshold) / (pattern.secondMovementBagThreshold - pattern.firstMovementBagThreshold)) * duration
        local stopTime = ((pattern.numOfBags - pattern.firstMovementBagThreshold) / (pattern.secondMovementBagThreshold - pattern.firstMovementBagThreshold)) * duration
        self.animationUtil:playAnimationPackageUntil(pattern.secondMovementAnimationPackage, startTime, stopTime, self.guideNodesMoved, self)
    end
end

function StrawHarvestPalletizer:guideNodesMoved()
    local pattern = self.bagPatterns[self.currentPusherPattern]
    if pattern.numOfBags == pattern.firstMovementBagThreshold then
        self.animationUtil:playAnimationPackage(pattern.pusherFirstAnimationPackage, 0)
    end

    if pattern.numOfBags == pattern.secondMovementBagThreshold then
        self.currentLifterPattern = self.currentPusherPattern
        self.animationUtil:playAnimationPackage(pattern.pusherPushThroughAnimationPackage, 0, self.handBagOverToLift, self)
        self.currentPusherPattern = self.currentRotatoryPattern
    end
end

function StrawHarvestPalletizer:handBagOverToLift(posAnimationTime)
    local pattern = self.bagPatterns[self.currentLifterPattern]
    for _, node in ipairs(pattern.bagNodes) do
        self:linkToNode(node, self.bagLifterBagGuideNode)
        table.insert(self.bagLifterBags, node)
    end

    pattern.bagNodes = {}
    pattern.numOfBags = 0

    local targetTime = self.bagLifterMinAnimationTime + self.bagLifterAnimationTimePerBagLayer * self.bagLifterCurrentBagRow
    self.animationUtil:playAnimationPackageUntil(self.bagLifterMovementAnimationPackage, posAnimationTime or self.bagLifterLoadPosAnimationTime, targetTime, self.bagLifterReachedPalletHeight, self)
end

function StrawHarvestPalletizer:bagLifterReachedPalletHeight()
    self.animationUtil:playAnimationPackage(self.bagLifterPutBagsOnPalletAnimationPackage, 0, self.handBagsOverToPallet, self)
end

function StrawHarvestPalletizer:handBagsOverToPallet()
    for _, node in ipairs(self.bagLifterBags) do
        self:linkToNode(node, self.bagLifterPalletGuideNode)
        table.insert(self.bagLifterPalletNodes, node)
    end

    self.bagLifterBags = {}
    self.bagLifterCurrentBagRow = self.bagLifterCurrentBagRow + 1

    if self.bagLifterCurrentBagRow < self.bagLifterNumBagRowsOnPallet then
        self.animationUtil:playAnimationPackageUntil(self.bagLifterMovementAnimationPackage, nil, self.bagLifterLoadPosAnimationTime)
    elseif self.bagLifterCurrentBagRow == self.bagLifterNumBagRowsOnPallet then
        self.animationUtil:playAnimationPackageUntil(self.bagLifterMovementAnimationPackage, nil, self.bagLifterMaxAnimationTime, self.bagLifterReachedTop, self)
        self.bagLifterCurrentBagRow = 0
    end
end

function StrawHarvestPalletizer:handOverPallet()
    self:linkToNode(self.currentLiftPallet, self.bagLifterPalletGuideNode)
end

function StrawHarvestPalletizer:bagLifterReachedTop()
    self.animationUtil:setAnimationPackageTime(self.conveyorMovePalletOutAnimationPackage, 0)

    for _, node in ipairs(self.bagLifterPalletNodes) do
        self:linkToNode(node, self.conveyorPalletGuideNode)
        table.insert(self.palletConveyorBags, node)
    end

    self.bagLifterPalletNodes = {}
    self:linkToNode(self.currentLiftPallet, self.conveyorPalletGuideNode)
    self.palletConveyorPallet = self.currentLiftPallet

    self.animationUtil:playAnimationPackage(self.conveyorMovePalletOutAnimationPackage, 0, self.handOverToDestinationAnimation, self)

    if self.isServer then
        self.isPalletMovingToDestination = true
    end

    self.currentLiftPallet = nil
end

function StrawHarvestPalletizer:handOverToDestinationAnimation()
    self.animationUtil:setAnimationPackageTime(self.movePalletToDestinationAnimationPackage, 0)

    for _, node in ipairs(self.palletConveyorBags) do
        self:linkToNode(node, self.palletOutputGuideNode)
    end
    self:linkToNode(self.palletConveyorPallet, self.palletOutputGuideNode)

    local outputPlaceIndex = self:getNextOutputPlace(1)
    if outputPlaceIndex ~= nil then
        local animationTime = self.palletOutputPlaces[outputPlaceIndex].animationTime
        self.animationUtil:playAnimationPackageUntil(self.movePalletToDestinationAnimationPackage, 0, animationTime, self.calculatePalletBags, self)

        -- Move back the lift
        self.animationUtil:playAnimationPackageUntil(self.bagLifterMovementAnimationPackage, nil, self.bagLifterLoadPosAnimationTime)
    end
end

function StrawHarvestPalletizer:calculatePalletBags()
    local bagsPerFillType = {}
    for _, node in ipairs(self.palletConveyorBags) do
        local fillType = self.clonedBagToFillType[node] or FillType.STRAWPELLETS
        local amount = bagsPerFillType[fillType] or 0
        bagsPerFillType[fillType] = amount + 1
        self:removeClonedBag(node)
    end

    delete(self.palletConveyorPallet)

    self.palletConveyorBags = {}
    self.palletConveyorPallet = nil

    if self.isServer then
        local lastFillTypeIndex
        local lastAmount
        for fillTypeIndex, amount in pairs(bagsPerFillType) do
            local updateFillType = lastFillTypeIndex == nil
            if not updateFillType then
                updateFillType = amount > lastAmount
            end

            if updateFillType then
                lastFillTypeIndex = fillTypeIndex
                lastAmount = amount * self.fillTypeToDecisionWeight[fillTypeIndex]
            end
        end

        local outputPlaceIndex = self:getNextOutputPlace(1)
        self:createPallet(outputPlaceIndex, lastFillTypeIndex)
    end
end

---Creates a pallet on the given output place with the given filltype.
function StrawHarvestPalletizer:createPallet(outputPlaceIndex, fillType)
    if self.isServer then
        local outputPlace = self.palletOutputPlaces[outputPlaceIndex]
        local x, y, z = localToWorld(outputPlace.triggerId, 0, 0, 0)

        local palletFilename = self.fillTypeToPalletXML[fillType]
        local _, ry, _ = getRotation(self.nodeId)

        --Do rotation correct based on the node rotation.
        local rotCorrection = math.pi * 0.5
        local pallet = g_currentMission:loadVehicle(palletFilename, x, y + outputPlace.spawnOffset, z, 0, ry - rotCorrection, true, 0, Vehicle.PROPERTY_STATE_OWNED, self:getOwnerFarmId(), nil, nil)
        pallet:emptyAllFillUnits(true)

        local fillUnitIndex = pallet:getFirstValidFillUnitToFill(fillType)
        if fillUnitIndex ~= nil then
            pallet:addFillUnitFillLevel(self:getOwnerFarmId(), fillUnitIndex, pallet:getFillUnitCapacity(fillUnitIndex), fillType, ToolType.UNDEFINED, nil)
        end

        self:setStatistics(self.bagsToday, self.palletsToday + 1)
        self.isPalletMovingToDestination = false
    end
end

function StrawHarvestPalletizer:linkToNode(node, linkNode)
    -- Avoid callstacks when the bag got delete while animation was somehow still playing.
    if not entityExists(node) then
        return
    end

    local x, y, z = localToLocal(node, linkNode, 0, 0, 0)
    local dx, dy, dz = localDirectionToLocal(node, linkNode, 0, 0, 1)
    local upX, upY, upZ = localDirectionToLocal(node, linkNode, 0, 1, 0)

    setDirection(node, dx, dy, dz, upX, upY, upZ)
    setTranslation(node, x, y, z)
    unlink(node)
    link(linkNode, node)
end

function StrawHarvestPalletizer:onObjectRemovedFromPhysics(object)
    -- Remove the object from the output places.
    for _, place in ipairs(self.palletOutputPlaces) do
        if place.objectsInTrigger[object] ~= nil then
            object.strawHarvestPalletizer = nil
            place.objectsInTrigger[object] = nil
            place.numOfObjectsInTrigger = math.max(place.numOfObjectsInTrigger - 1, 0)
            --Raise active to check the active state again (if a removed pallet unblocks the outputs).
            self:raiseActive()
        end
    end
end

----------------------
-- Trigger callbacks
----------------------

function StrawHarvestPalletizer:outputPlaceTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if onEnter or onLeave then
        local object = g_currentMission:getNodeObject(otherId)

        if object ~= nil and object ~= self then
            local place = self.palletOutputPlacesByTrigger[triggerId]
            local numOfObjectsInTrigger = place.numOfObjectsInTrigger

            if onEnter then
                if place.objectsInTrigger[object] == nil then
                    object.strawHarvestPalletizer = self
                    place.numOfObjectsInTrigger = numOfObjectsInTrigger + 1
                    place.objectsInTrigger[object] = place.numOfObjectsInTrigger
                end
            else
                object.strawHarvestPalletizer = nil
                place.objectsInTrigger[object] = nil
                place.numOfObjectsInTrigger = math.max(numOfObjectsInTrigger - 1, 0)
            end

            --Raise active to check the active state again (if a removed pallet unblocks the outputs).
            self:raiseActive()
        end
    end
end

function StrawHarvestPalletizer:playerTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if onEnter or onLeave then
        if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
            if onEnter then
                local farmId = self:getOwnerFarmId()
                if farmId == nil or farmId == AccessHandler.EVERYONE or g_currentMission.accessHandler:canFarmAccessOtherId(g_currentMission:getFarmId(), farmId) then
                    self.playerInRange = true
                end
            else
                self.playerInRange = false
            end

            self:raiseActive()
        end
    end
end

----------------------
-- Events
----------------------

---Called by server on day change.
function StrawHarvestPalletizer:dayChanged()
    self:setStatistics(0, 0)
end

---Called by server on hour change.
function StrawHarvestPalletizer:hourChanged()
    local costs = self.hourlyCosts
    local farmId = self:getOwnerFarmId()

    g_currentMission:addMoney(-costs, farmId, MoneyType.PROPERTY_MAINTENANCE, true, false)
    g_currentMission:broadcastNotifications(MoneyType.PROPERTY_MAINTENANCE, farmId)

    self.hourlyCosts = 0
end
