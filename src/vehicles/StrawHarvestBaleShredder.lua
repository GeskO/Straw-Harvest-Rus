---
-- StrawHarvestBaleShredder
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: allows shredding of bales to feed the pelletizer.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestBaleShredder
StrawHarvestBaleShredder = {}
StrawHarvestBaleShredder.MOD_NAME = g_currentModName
StrawHarvestBaleShredder.SEND_OBJECT_NUM_BITS = 5 -- 2 ^ 5

StrawHarvestBaleShredder.WARNING_FILLTYPE_BALE_NOT_SUPPORTED = 1
StrawHarvestBaleShredder.WARNING_ROUND_BALE_NOT_SUPPORTED = 2
StrawHarvestBaleShredder.DAMAGED_SPEEDLIMIT_REDUCTION = 0.8

function StrawHarvestBaleShredder.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AnimatedVehicle, specializations)
end

function StrawHarvestBaleShredder.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "detectionTriggerCallback", StrawHarvestBaleShredder.detectionTriggerCallback)
    SpecializationUtil.registerFunction(vehicleType, "addBale", StrawHarvestBaleShredder.addBale)
    SpecializationUtil.registerFunction(vehicleType, "removeBale", StrawHarvestBaleShredder.removeBale)
    SpecializationUtil.registerFunction(vehicleType, "isBaleAllowed", StrawHarvestBaleShredder.isBaleAllowed)
    SpecializationUtil.registerFunction(vehicleType, "isRoundBale", StrawHarvestBaleShredder.isRoundBale)
    SpecializationUtil.registerFunction(vehicleType, "addDynamicMountedObject", StrawHarvestBaleShredder.addDynamicMountedObject)
    SpecializationUtil.registerFunction(vehicleType, "removeDynamicMountedObject", StrawHarvestBaleShredder.removeDynamicMountedObject)
    SpecializationUtil.registerFunction(vehicleType, "hasDummyBale", StrawHarvestBaleShredder.hasDummyBale)
    SpecializationUtil.registerFunction(vehicleType, "createDummyBaleFromBale", StrawHarvestBaleShredder.createDummyBaleFromBale)
    SpecializationUtil.registerFunction(vehicleType, "deleteDummyBale", StrawHarvestBaleShredder.deleteDummyBale)
    SpecializationUtil.registerFunction(vehicleType, "processBale", StrawHarvestBaleShredder.processBale)
    SpecializationUtil.registerFunction(vehicleType, "loadObjectChangeValuesFromXML", StrawHarvestBaleShredder.loadObjectChangeValuesFromXML)
    SpecializationUtil.registerFunction(vehicleType, "setObjectChangeValues", StrawHarvestBaleShredder.setObjectChangeValues)
end

function StrawHarvestBaleShredder.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldAllowed", StrawHarvestBaleShredder.getIsFoldAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getFillLevelInformation", StrawHarvestBaleShredder.getFillLevelInformation)
end

function StrawHarvestBaleShredder.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onPreAttach", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onPreDetach", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onTurnedOff", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onDeactivate", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onStartAnimation", StrawHarvestBaleShredder)
    SpecializationUtil.registerEventListener(vehicleType, "onFinishAnimation", StrawHarvestBaleShredder)
end

---Called on load.
function StrawHarvestBaleShredder:onLoad(savegame)
    self.spec_strawHarvestBaleShredder = self[("spec_%s.strawHarvestBaleShredder"):format(StrawHarvestBaleShredder.MOD_NAME)]
    local spec = self.spec_strawHarvestBaleShredder

    spec.objectChanges = {}
    spec.supportObjectChanges = {}
    spec.supportObjectChangesAnimationName = Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.baleShredder.supportObjectChanges#animationName"), "moveOnPallet")
    ObjectChangeUtil.loadObjectChangeFromXML(self.xmlFile, "vehicle.baleShredder.objectChanges", spec.objectChanges, self.components, self)
    ObjectChangeUtil.loadObjectChangeFromXML(self.xmlFile, "vehicle.baleShredder.supportObjectChanges", spec.objectChanges, self.components, self)
    ObjectChangeUtil.setObjectChanges(spec.objectChanges, false)
    ObjectChangeUtil.setObjectChanges(spec.supportObjectChanges, false)

    spec.dynamicMountedObjects = {}
    spec.activeBaleToTarget = {}
    spec.activeBales = {}
    if self.isServer then
        spec.detectionRootNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.detection#detectionRootNode"), self.i3dMappings)

        local node = createTransformGroup("detectionRootNodeReverse")
        link(spec.detectionRootNode, node)
        setTranslation(node, 0, 0, 0)
        setRotation(node, 0, 0, math.rad(180))
        spec.detectionRootNodeReverse = node
    end

    spec.detectionTriggerNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.detection#detectionTriggerNode"), self.i3dMappings)
    if spec.detectionTriggerNode ~= nil then
        addTrigger(spec.detectionTriggerNode, "detectionTriggerCallback", self)
    end

    spec.allowRoundBales = Utils.getNoNil(getXMLBool(self.xmlFile, "vehicle.baleShredder.baleAnimation#allowRoundBales"), false)
    spec.feedThreshold = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleShredder.baleAnimation#feedThreshold"), 0.1)
    spec.baleMovementSpeed = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleShredder.baleAnimation#movementSpeed"), 0.05)

    spec.twineAnimation = {}
    spec.twineAnimation.node = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.twineAnimation#detectionRootNode"), self.i3dMappings)
    spec.twineAnimation.startThreshold = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleShredder.twineAnimation#startThreshold"), 0.1)
    spec.twineAnimation.name = Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.baleShredder.twineAnimation#animationName"), "removeTwine")

    spec.knifeAnimation = {}
    spec.knifeAnimation.node = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.knifeAnimation#detectionRootNode"), self.i3dMappings)
    spec.knifeAnimation.startThreshold = Utils.getNoNil(getXMLFloat(self.xmlFile, "vehicle.baleShredder.knifeAnimation#startThreshold"), 0.1)
    spec.knifeAnimation.name = Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.baleShredder.knifeAnimation#animationName"), "moveKnife")

    if self.isClient then
        spec.twineAnimation.animationNodes = g_animationManager:loadAnimations(self.xmlFile, "vehicle.baleShredder.twineAnimation.animationNodes", self.components, self, self.i3dMappings)
        spec.knifeAnimation.animationNodes = g_animationManager:loadAnimations(self.xmlFile, "vehicle.baleShredder.knifeAnimation.animationNodes", self.components, self, self.i3dMappings)
    end

    spec.dummyBaleToCreate = nil
    spec.dummyBale = {}
    spec.dummyBale.scaleNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.baleAnimation#scaleNode"), self.i3dMappings)
    spec.dummyBale.baleNode = I3DUtil.indexToObject(self.components, getXMLString(self.xmlFile, "vehicle.baleShredder.baleAnimation#baleNode"), self.i3dMappings)
    spec.dummyBale.currentBaleFillType = FillType.UNKNOWN
    spec.dummyBale.currentBale = nil
    spec.dummyBale.scale = 1
    spec.dummyBale.scaleSent = 1

    spec.dummyBale.networkTimeInterpolator = InterpolationTime:new(1.2)
    spec.dummyBale.networkScaleInterpolator = InterpolatorValue:new(0)
    spec.dummyBale.networkScaleInterpolator:setMinMax(0, 1)

    if self.isClient then
        spec.effects = g_effectManager:loadEffect(self.xmlFile, "vehicle.baleShredder.effect", self.components, self, self.i3dMappings)
    end

    spec.currentWarning = 0
    spec.warnings = {}
    spec.warnings[StrawHarvestBaleShredder.WARNING_FILLTYPE_BALE_NOT_SUPPORTED] = g_i18n:getText("warning_baleFillTypeNotSupported")
    spec.warnings[StrawHarvestBaleShredder.WARNING_ROUND_BALE_NOT_SUPPORTED] = g_i18n:getText("warning_roundBalesNotSupported")

    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.dynamicMountedObjectsDirtyFlag = self:getNextDirtyFlag()
end

function StrawHarvestBaleShredder:onPostLoad(savegame)
    local spec = self.spec_strawHarvestBaleShredder

    if savegame ~= nil and not savegame.resetVehicles then
        local key = ("%s.%s.strawHarvestBaleShredder"):format(savegame.key, self:strawHarvest_getModName())

        local filename = getXMLString(savegame.xmlFile, key .. "#filename")
        if filename ~= nil then
            filename = NetworkUtil.convertFromNetworkFilename(filename)
            local fillTypeStr = getXMLString(savegame.xmlFile, key .. "#fillType")
            local fillType = g_fillTypeManager:getFillTypeByName(fillTypeStr)

            local fillLevel = getXMLFloat(savegame.xmlFile, key .. "#fillLevel")
            local capacity = getXMLFloat(savegame.xmlFile, key .. "#capacity")
            local currentBaleYOffset = getXMLFloat(savegame.xmlFile, key .. "#currentBaleYOffset")
            local currentBaleZOffset = getXMLFloat(savegame.xmlFile, key .. "#currentBaleZOffset")
            local scale = getXMLFloat(savegame.xmlFile, key .. "#scale")

            self:createDummyBaleFromBale(filename, currentBaleYOffset, currentBaleZOffset, fillType.index, fillLevel, capacity)
            spec.dummyBale.scale = Utils.getNoNil(scale, spec.dummyBale.scale)
            setScale(spec.dummyBale.scaleNode, 1, 1, scale)
        end
    end
end

---Called on delete.
function StrawHarvestBaleShredder:onDelete()
    local spec = self.spec_strawHarvestBaleShredder

    if self.isClient then
        g_effectManager:deleteEffects(spec.effects)
        g_animationManager:deleteAnimations(spec.twineAnimation.animationNodes)
        g_animationManager:deleteAnimations(spec.knifeAnimation.animationNodes)
    end

    self:deleteDummyBale()

    if self.isServer then
        if spec.detectionTriggerNode ~= nil then
            removeTrigger(spec.detectionTriggerNode)
        end
    end
end

function StrawHarvestBaleShredder:onReadStream(streamId, connection)
    if connection:getIsServer() then
        local spec = self.spec_strawHarvestBaleShredder
        local scale = streamReadFloat32(streamId)
        spec.dummyBale.networkScaleInterpolator:setValue(scale)
        spec.dummyBale.networkTimeInterpolator:reset()

        if streamReadBool(streamId) then
            local i3dFilename = NetworkUtil.convertFromNetworkFilename(streamReadString(streamId))
            local yOffset = streamReadFloat32(streamId)
            local zOffset = streamReadFloat32(streamId)
            local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
            spec.dummyBaleToCreate = { i3dFilename, yOffset, zOffset, fillType, scale }
        end
    end
end

function StrawHarvestBaleShredder:onWriteStream(streamId, connection)
    if not connection:getIsServer() then
        local spec = self.spec_strawHarvestBaleShredder
        streamWriteFloat32(streamId, spec.dummyBale.scaleSent)

        local hasDummyBale = spec.dummyBale.currentBale ~= nil
        if streamWriteBool(streamId, hasDummyBale) then
            streamWriteString(streamId, NetworkUtil.convertToNetworkFilename(spec.dummyBale.currentFilename))
            streamWriteFloat32(streamId, spec.dummyBale.currentBaleYOffset)
            streamWriteFloat32(streamId, spec.dummyBale.currentBaleZOffset)
            streamWriteUIntN(streamId, spec.dummyBale.currentBaleFillType, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

function StrawHarvestBaleShredder:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self.spec_strawHarvestBaleShredder
        if streamReadBool(streamId) then
            local scale = streamReadFloat32(streamId)
            spec.dummyBale.networkScaleInterpolator:setTargetValue(scale)
            spec.dummyBale.networkTimeInterpolator:startNewPhaseNetwork()
        end

        if streamReadBool(streamId) then
            local amount = streamReadUIntN(streamId, StrawHarvestBaleShredder.SEND_OBJECT_NUM_BITS)

            spec.dynamicMountedObjects = {}
            for i = 1, amount do
                local object = NetworkUtil.readNodeObject(streamId)
                if object ~= nil then
                    spec.dynamicMountedObjects[object] = object
                end
            end
        end
    end
end

function StrawHarvestBaleShredder:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self.spec_strawHarvestBaleShredder
        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteFloat32(streamId, spec.dummyBale.scale)
        end

        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dynamicMountedObjectsDirtyFlag) ~= 0) then
            local objects = {}
            for object, _ in pairs(spec.dynamicMountedObjects) do
                table.insert(objects, object)
            end

            streamWriteUIntN(streamId, #objects, StrawHarvestBaleShredder.SEND_OBJECT_NUM_BITS)
            for i = 1, #objects do
                local object = objects[i]
                NetworkUtil.writeNodeObject(streamId, object)
            end
        end
    end
end

function StrawHarvestBaleShredder:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_strawHarvestBaleShredder

    if self:hasDummyBale() then
        local currentBale = spec.dummyBale
        local fillType = currentBale.currentBaleFillType
        local fillTypeStr = "UNKNOWN"
        if fillType ~= FillType.UNKNOWN then
            fillTypeStr = g_fillTypeManager:getFillTypeNameByIndex(fillType)
        end

        setXMLString(xmlFile, key .. "#fillType", fillTypeStr)
        setXMLFloat(xmlFile, key .. "#fillLevel", currentBale.currentBaleFillLevel)
        setXMLFloat(xmlFile, key .. "#capacity", currentBale.currentBaleCapacity)
        setXMLFloat(xmlFile, key .. "#currentBaleYOffset", currentBale.currentBaleYOffset)
        setXMLFloat(xmlFile, key .. "#currentBaleZOffset", currentBale.currentBaleZOffset)
        setXMLString(xmlFile, key .. "#filename", HTMLUtil.encodeToHTML(NetworkUtil.convertToNetworkFilename(currentBale.currentFilename)))
        setXMLFloat(xmlFile, key .. "#scale", currentBale.scale)
    end
end

function StrawHarvestBaleShredder:onUpdate(dt)
    local spec = self.spec_strawHarvestBaleShredder

    if spec.dummyBaleToCreate ~= nil then
        local i3dFilename, yOffset, zOffset, fillType, scale = unpack(spec.dummyBaleToCreate)
        self:createDummyBaleFromBale(i3dFilename, yOffset, zOffset, fillType)
        if spec.dummyBale.currentBale ~= nil then
            setScale(spec.dummyBale.scaleNode, 1, 1, scale)
            spec.dummyBaleToCreate = nil
        end
    end

    local currentBale = spec.dummyBale
    local scale = currentBale.scale
    if not self.isServer then
        currentBale.networkTimeInterpolator:update(dt)
        local interpolationAlpha = currentBale.networkTimeInterpolator:getAlpha()
        scale = currentBale.networkScaleInterpolator:getInterpolatedValue(interpolationAlpha)
    end

    if self.isClient then
        local isFilling = self:hasDummyBale() and self:getIsTurnedOn()
        if isFilling then
            setScale(currentBale.scaleNode, 1, 1, scale)

            isFilling = scale > 0.01 -- take interpolated value into account.
            if not isFilling then
                self:deleteDummyBale()
            end
        end

        if spec.effects ~= nil then
            if isFilling then
                g_effectManager:setFillType(spec.effects, currentBale.currentBaleFillType)
                g_effectManager:startEffects(spec.effects)
            else
                g_effectManager:stopEffects(spec.effects)
            end
        end
    end

    if not self.isServer then
        if currentBale.networkTimeInterpolator:isInterpolating() then
            self:raiseActive()
        end
    end

    if self.isClient and self:getIsActiveForInput(true) then
        if spec.currentWarning ~= 0 then
            local warning = spec.warnings[spec.currentWarning]
            g_currentMission:showBlinkingWarning(warning, 5000)
            spec.currentWarning = 0
        end
    end
end

function StrawHarvestBaleShredder:onUpdateTick(dt)
    if not self.isServer then
        return
    end

    if not self:getIsTurnedOn() then
        return
    end

    local spec = self.spec_strawHarvestBaleShredder
    for object, target in pairs(spec.activeBaleToTarget) do
        if not (spec.dynamicMountedObjects[object] ~= nil) then
            local objectId = object.nodeId or object.rootNode
            if object.lastMoveTime + 50 < g_currentMission.time
                    and not object.isAttachedToBaleHook
                    and object.dynamicMountJointIndex == nil then
                local x, y, z = localToLocal(objectId, spec.detectionRootNode, 0, 0, 0)

                if y <= 0 then
                    -- First unmount to remove existing joints.
                    object:unmountDynamic()
                    setTranslation(target.jointNode, x, y, z)

                    local _, _, bz = getRotation(objectId)
                    local isInverted = not (MathUtil.round(bz) ~= 0)
                    local node = isInverted and spec.detectionRootNodeReverse or spec.detectionRootNode
                    local rx, ry, rz = localRotationToLocal(objectId, getParent(node), getRotation(node))
                    setRotation(target.jointNode, rx, ry, rz)

                    if object:mountDynamic(self, self.rootNode, target.jointNode, DynamicMountUtil.TYPE_AUTO_ATTACH_XYZ, 45) then
                        self:addDynamicMountedObject(object, isInverted)
                    end
                end
            end
        end
    end

    local positionIsDirty = false
    for object, _ in pairs(spec.dynamicMountedObjects) do
        local target = spec.activeBaleToTarget[object]

        if target ~= nil then
            local baleOffset = -target.z
            if target.direction == nil then
                local dx, dy, dz = localDirectionToWorld(target.jointNode, 0, 0, 1)
                target.direction = { worldDirectionToLocal(getParent(target.jointNode), dx, dy, dz) }
            end

            target.time = target.time + dt * 0.2

            local distance = calcDistanceFrom(target.detectionNode, target.jointNode) - baleOffset
            if distance > spec.feedThreshold then
                local x, y, z = localToWorld(target.jointNode, 0, 0, 0)
                local _, _, dot = worldDirectionToLocal(target.jointNode, localDirectionToWorld(spec.detectionRootNode, 0, 0, 1))
                local dir = MathUtil.sign(dot)
                local dirX, dirY, dirZ = localDirectionToWorld(target.jointNode, 0, 0, (distance + 0.1) * dir)

                -- Normalize
                if distance > 0.0001 then
                    dirX, dirY, dirZ = dirX / distance, dirY / distance, dirZ / distance
                end

                local threshHoldTime = 1000
                if target.time <= threshHoldTime then
                    local alpha = target.time / threshHoldTime
                    local localDirX, localDirY, localDirZ = worldDirectionToLocal(target.jointNode, dirX, dirY, dirZ)

                    local ox, oy, oz = unpack(target.direction)
                    localDirX, localDirY, localDirZ = MathUtil.vector3Lerp(ox, oy, oz, localDirX, localDirY, localDirZ, alpha)
                    local localUpX, localUpY, localUpZ = worldDirectionToLocal(getParent(target.jointNode), localDirectionToWorld(target.jointNode, 0, 1, 0))

                    I3DUtil.setDirection(target.jointNode, localDirX, localDirY, localDirZ, localUpX, localUpY, localUpZ)
                end

                local movementFactor = 1
                local damage = self:getVehicleDamage()
                if damage > 0 then
                    movementFactor = movementFactor - damage * StrawHarvestBaleShredder.DAMAGED_SPEEDLIMIT_REDUCTION
                end

                local speed = (spec.baleMovementSpeed * movementFactor) * 0.001 * dt
                local tx = x + (dirX * speed)
                local tz = z + (dirZ * speed)
                setWorldTranslation(target.jointNode, tx, y, tz)
                positionIsDirty = true

                if not target.isTwineCut then
                    local knifeAnimation = spec.knifeAnimation
                    -- Reset animation
                    if not self:getIsAnimationPlaying(knifeAnimation.name) and self:getAnimationTime(knifeAnimation.name) == 1 then
                        self:playAnimation(knifeAnimation.name, -1, nil, false)
                    end

                    local knifeDistance = calcDistanceFrom(knifeAnimation.node, target.jointNode) - baleOffset
                    if knifeDistance <= knifeAnimation.startThreshold then
                        self:playAnimation(knifeAnimation.name, 1, nil, false)
                        target.isTwineCut = true
                    end
                end

                if not target.isTwineRemoved then
                    local twineAnimation = spec.twineAnimation
                    -- Reset animation
                    if not self:getIsAnimationPlaying(twineAnimation.name) and self:getAnimationTime(twineAnimation.name) == 1 then
                        self:playAnimation(twineAnimation.name, -1, nil, false)
                    end

                    local twineDistance = calcDistanceFrom(twineAnimation.node, target.jointNode) - baleOffset
                    if twineDistance <= twineAnimation.startThreshold then
                        self:playAnimation(twineAnimation.name, 1, nil, false)
                        target.isTwineRemoved = true
                    end
                end

                if VehicleDebug.state == VehicleDebug.DEBUG then
                    DebugUtil.drawDebugNode(target.jointNode, "N")
                    x, y, z = localToWorld(target.detectionNode, 0, 0, 0)
                    drawDebugLine(x, y + 1, z, 1, 1, 0, tx, y + 1, tz, 1, 1, 0)
                end
            else
                -- Check when we allow..
                local isBaleAllowed, warning = self:isBaleAllowed(object)
                if isBaleAllowed then
                    if not self:hasDummyBale() then
                        self:removeDynamicMountedObject(object, true)

                        local baleFillType = object:getFillType()
                        local fillLevel = object:getFillLevel()
                        local isRoundBale = self:isRoundBale(object)
                        -- These rounds are needed to get the correct bale..
                        local width = MathUtil.round(Utils.getNoNil(object.baleWidth, 1.2), 2)
                        local baleHeight = StrawHarvestBaleShredder.getCorrectedBaleHeight(object, isRoundBale)
                        local height = MathUtil.round(Utils.getNoNil(baleHeight, 0.9), 2)
                        local length = MathUtil.round(Utils.getNoNil(object.baleLength, 2.4), 2)
                        local diameter = MathUtil.round(Utils.getNoNil(object.baleDiameter, 1.8), 2)
                        -- Get bale from the baleTypeManager in order to make sure we load from the same sharedRoot node.
                        local baleType = g_baleTypeManager:getBale(baleFillType, isRoundBale, width, height, length, diameter)

                        self:createDummyBaleFromBale(baleType.filename, target.y, target.z, baleFillType, fillLevel, fillLevel)
                        object:delete()
                    end
                else
                    spec.currentWarning = warning
                end
            end
        else
            self:removeDynamicMountedObject(object)
        end
    end

    if positionIsDirty then
        for object, _ in pairs(spec.dynamicMountedObjects) do
            local target = spec.activeBaleToTarget[object]

            if target ~= nil then
                if object.dynamicMountJointIndex ~= nil then
                    setJointFrame(object.dynamicMountJointIndex, 0, target.jointNode)
                end

                if object.backupMass == nil then
                    local mass = getMass(object.nodeId)
                    if mass ~= 1 then
                        object.backupMass = mass
                        setMass(object.nodeId, 0.1)
                    end
                end
            end
        end
    end
end

---Processes the bale (called from the attacher vehicle) and returns the delta on the fill level.
function StrawHarvestBaleShredder:processBale(dt)
    local spec = self.spec_strawHarvestBaleShredder
    local delta, fillType = 0, FillType.UNKNOWN

    local currentBale = spec.dummyBale
    if self:hasDummyBale() then
        fillType = currentBale.currentBaleFillType

        local movementFactor = 1
        local damage = self:getVehicleDamage()
        if damage > 0 then
            movementFactor = movementFactor - damage * StrawHarvestBaleShredder.DAMAGED_SPEEDLIMIT_REDUCTION
        end

        local speed = (spec.baleMovementSpeed * movementFactor) * 0.001 * dt
        delta = math.abs(currentBale.currentBaleCapacity * (speed / (currentBale.currentBaleZOffset * 2)))
        delta = math.min(delta, currentBale.currentBaleFillLevel, currentBale.currentBaleCapacity)

        currentBale.currentBaleFillLevel = currentBale.currentBaleFillLevel - delta
        currentBale.scale = currentBale.currentBaleFillLevel / currentBale.currentBaleCapacity
    end

    if currentBale.scaleSent ~= currentBale.scale then
        if not (currentBale.scale > 0) then
            self:deleteDummyBale()
        end

        currentBale.scaleSent = currentBale.scale
        self:raiseDirtyFlags(spec.dirtyFlag)
    end

    return delta, fillType
end

---Returns true when allowed, false and warning otherwise.
function StrawHarvestBaleShredder:isBaleAllowed(object)
    local spec = self.spec_strawHarvestBaleShredder
    local isRoundBale = self:isRoundBale(object)
    local allowBale = (isRoundBale and spec.allowRoundBales) or not isRoundBale
    local warning
    if not allowBale then
        warning = StrawHarvestBaleShredder.WARNING_ROUND_BALE_NOT_SUPPORTED
    else
        -- Check if we allow the fillType from the bale
        local baleFillType = object:getFillType()
        if spec.attacherVehicle ~= nil then
            allowBale = spec.attacherVehicle:isShreddingBaleAllowed(baleFillType)
            if not allowBale then
                warning = StrawHarvestBaleShredder.WARNING_FILLTYPE_BALE_NOT_SUPPORTED
            end
        end
    end

    return allowBale, warning
end

---Returns true when the object has the property 'baleDiameter' and 'baleWidth', false otherwise.
function StrawHarvestBaleShredder:isRoundBale(object)
    return object.baleDiameter ~= nil and object.baleWidth ~= nil
end

---Adds the given bale object to the active bales table in order to move the bale towards to drums.
function StrawHarvestBaleShredder:addBale(object)
    local spec = self.spec_strawHarvestBaleShredder
    local target = {}

    local z = self:isRoundBale(object) and object.baleDiameter or object.baleLength
    target.z = -z * 0.5

    target.time = 0
    target.isTwineCut = false
    target.isTwineRemoved = false

    target.object = object
    target.jointNode = createTransformGroup("targetJointNode")
    link(spec.detectionRootNode, target.jointNode)

    spec.activeBaleToTarget[object] = target
    table.insert(spec.activeBales, target)
end

---Removes the given bale object from the active bales table.
function StrawHarvestBaleShredder:removeBale(object)
    local spec = self.spec_strawHarvestBaleShredder
    local target = spec.activeBaleToTarget[object]
    if target ~= nil then
        if self.isServer then
            delete(target.jointNode)
        end
    end
    ListUtil.removeElementFromList(spec.activeBales, target)
    spec.activeBaleToTarget[object] = nil
end

---Adds dynamic mounted object (Bale).
function StrawHarvestBaleShredder:addDynamicMountedObject(object, isInverted)
    -- Prevent calling from the DynamicMountUtil.
    if isInverted == nil then
        return
    end

    local spec = self.spec_strawHarvestBaleShredder
    local target = spec.activeBaleToTarget[object]
    if target ~= nil then
        target.detectionNode = isInverted and spec.detectionRootNodeReverse or spec.detectionRootNode

        local _, y, _ = getTranslation(target.jointNode)
        target.y = y

        -- Reset the timer to fix rotation issues.
        target.time = 0
        target.direction = nil
    end

    spec.dynamicMountedObjects[object] = object
    self:raiseDirtyFlags(spec.dynamicMountedObjectsDirtyFlag)
end

---Removes dynamic mounted object (Bale).
function StrawHarvestBaleShredder:removeDynamicMountedObject(object, isDeleting)
    local spec = self.spec_strawHarvestBaleShredder

    spec.dynamicMountedObjects[object] = nil
    if isDeleting then
        self:removeBale(object)
    end

    if self.isServer then
        object:unmountDynamic()
        if object.backupMass ~= nil then
            setMass(object.nodeId, object.backupMass)
            object.backupMass = nil
        end
    end

    self:raiseDirtyFlags(spec.dynamicMountedObjectsDirtyFlag)
end

---Returns the correct bale height for vanilla bales.
function StrawHarvestBaleShredder.getCorrectedBaleHeight(bale, isRoundBale)
    if not isRoundBale then
        local balesToFix = {
            ["baleGrass240"] = true,
            ["baleHay240"] = true,
            ["baleStraw240"] = true
        }

        -- Do fix for bale height here
        local name = Utils.getFilenameInfo(bale.i3dFilename, bale.baseDirectory)
        if balesToFix[name] then
            return 0.9 -- This is correct height registered in the manager.
        end
    end

    return bale.baleHeight
end

---Returns true when the current dummy bale fillType is set, false otherwise.
function StrawHarvestBaleShredder:hasDummyBale()
    local spec = self.spec_strawHarvestBaleShredder
    return spec.dummyBale.currentBaleFillType ~= FillType.UNKNOWN
end

---Creates a dummy bale for shredding from the shared root bale.
function StrawHarvestBaleShredder:createDummyBaleFromBale(filename, yOffset, zOffset, fillTypeIndex, fillLevel, capacity)
    local spec = self.spec_strawHarvestBaleShredder
    local baleRoot = g_i3DManager:loadSharedI3DFile(filename, nil, false, false, false)

    local baleId = getChildAt(baleRoot, 0)
    setRigidBodyType(baleId, "NoRigidBody")
    link(spec.dummyBale.baleNode, baleId)
    setScale(spec.dummyBale.scaleNode, 1, 1, 1)
    setTranslation(baleId, 0, yOffset, zOffset)
    delete(baleRoot)

    spec.dummyBale.currentBale = baleId
    spec.dummyBale.isRoundBale = Utils.getNoNil(getUserAttribute(baleId, "isRoundbale"), false)
    spec.dummyBale.currentFilename = filename

    spec.dummyBale.scale = 1
    spec.dummyBale.networkScaleInterpolator:setValue(1)

    spec.dummyBale.currentBaleYOffset = yOffset
    spec.dummyBale.currentBaleZOffset = zOffset
    spec.dummyBale.currentBaleFillType = fillTypeIndex

    if self.isServer then
        spec.dummyBale.currentBaleFillLevel = fillLevel
        spec.dummyBale.currentBaleCapacity = capacity
        spec.dummyBale.scaleSent = spec.dummyBale.scale

        g_server:broadcastEvent(StrawHarvestLoadDummyBaleEvent:new(self, filename, yOffset, zOffset, fillTypeIndex), nil, nil, self)
        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

---Removes the current dummy bale and releases the shared file.
function StrawHarvestBaleShredder:deleteDummyBale()
    local spec = self.spec_strawHarvestBaleShredder
    if spec.dummyBale.currentBale ~= nil then
        delete(spec.dummyBale.currentBale)
        g_i3DManager:releaseSharedI3DFile(spec.dummyBale.currentFilename, nil, true)
        spec.dummyBale.currentBale = nil
    end
    spec.dummyBale.currentBaleFillType = FillType.UNKNOWN
end

---Detection trigger callback when object enters the table trigger.
function StrawHarvestBaleShredder:detectionTriggerCallback(triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    local spec = self.spec_strawHarvestBaleShredder

    local object = g_currentMission:getNodeObject(otherActorId)
    if object ~= nil and object:isa(Bale) then
        if onEnter and self:getIsInWorkPosition() then
            local isBaleAllowed, warning = self:isBaleAllowed(object)
            if warning ~= nil then
                spec.currentWarning = warning
            end

            if self.isServer and spec.activeBaleToTarget[object] == nil and isBaleAllowed then
                self:addBale(object)
            end
        end

        if self.isServer and onLeave then
            self:removeDynamicMountedObject(object, true)
        end
    end
end

------------
-- Events --
------------

function StrawHarvestBaleShredder:onStartAnimation(animationName)
    local spec = self.spec_strawHarvestBaleShredder
    local twineAnimation = spec.twineAnimation
    if animationName == twineAnimation.name then
        g_animationManager:startAnimations(twineAnimation.animationNodes)
    end

    local knifeAnimation = spec.knifeAnimation
    if animationName == knifeAnimation.name then
        g_animationManager:startAnimations(knifeAnimation.animationNodes)
    end
end

function StrawHarvestBaleShredder:onFinishAnimation(animationName)
    local spec = self.spec_strawHarvestBaleShredder
    local twineAnimation = spec.twineAnimation
    if animationName == twineAnimation.name then
        g_animationManager:stopAnimations(twineAnimation.animationNodes)
    end

    local knifeAnimation = spec.knifeAnimation
    if animationName == knifeAnimation.name then
        g_animationManager:stopAnimations(knifeAnimation.animationNodes)
    end

    if animationName == spec.supportObjectChangesAnimationName then
        local isAttached = self:getAnimationTime(animationName) == 0
        ObjectChangeUtil.setObjectChanges(spec.supportObjectChanges, isAttached, self)
    end
end

function StrawHarvestBaleShredder:onPreAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_strawHarvestBaleShredder
    spec.attacherVehicle = attacherVehicle
    ObjectChangeUtil.setObjectChanges(spec.objectChanges, true, self)
end

function StrawHarvestBaleShredder:onPreDetach(attacherVehicle, implement)
    local spec = self.spec_strawHarvestBaleShredder
    spec.attacherVehicle = nil
    ObjectChangeUtil.setObjectChanges(spec.objectChanges, false, self)

    -- Force fold when not folded or when the animation is playing.
    if self.getFoldAnimTime ~= nil then
        local animationTime = self:getFoldAnimTime()
        local spec_foldable = self.spec_foldable

        if self:getIsInWorkPosition()
                or animationTime > spec_foldable.detachingMinLimit
                or animationTime < spec_foldable.detachingMaxLimit then
            Foldable.setAnimTime(self, 1, false)
        end
    end
end

function StrawHarvestBaleShredder:onTurnedOff()
    local spec = self.spec_strawHarvestBaleShredder

    if self.isClient then
        g_effectManager:stopEffects(spec.effects)
    end
end

function StrawHarvestBaleShredder:onDeactivate()
    local spec = self.spec_strawHarvestBaleShredder

    if self.isClient then
        g_effectManager:stopEffects(spec.effects)
    end
end

----------------
-- Overwrites --
----------------

---Loads extra attributes for setting the collision mask for object changes.
function StrawHarvestBaleShredder:loadObjectChangeValuesFromXML(xmlFile, key, node, object)
    local collisionMask = getCollisionMask(node)
    object.collisionMaskActive = getXMLInt(xmlFile, key .. "#collisionMaskActive") or collisionMask
    object.collisionMaskInactive = getXMLInt(xmlFile, key .. "#collisionMaskInactive") or collisionMask
end

---Set collision ask on object change.
function StrawHarvestBaleShredder:setObjectChangeValues(object, isActive)
    local collisionMaskToSet = isActive and object.collisionMaskActive or object.collisionMaskInactive
    setCollisionMask(object.node, collisionMaskToSet)
end

---Checks whether fold is allowed or not.
---Returns false when the bale shredder is has bales attached, false otherwise.
function StrawHarvestBaleShredder:getIsFoldAllowed(superFunc, direction, onAiTurnOn)
    local spec = self.spec_strawHarvestBaleShredder

    -- When there are bales attached disable folding.
    if #spec.activeBales > 0 or self:hasDummyBale() then
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

---Adds the bale fill level information to the list.
function StrawHarvestBaleShredder.addBaleFillLevelInformation(fillType, fillLevel, fillLevelsInformation)
    for _, fillLevelInformation in ipairs(fillLevelsInformation) do
        if fillLevelInformation.fillType == fillType then
            fillLevelInformation.fillLevel = fillLevelInformation.fillLevel + fillLevel
            fillLevelInformation.capacity = fillLevelInformation.capacity + fillLevel
            return true
        end
    end

    return false
end

---Gets the fill level information based on the bales on the table.
function StrawHarvestBaleShredder:getFillLevelInformation(superFunc, fillLevelInformations)
    superFunc(self, fillLevelInformations)

    local spec = self.spec_strawHarvestBaleShredder
    for object, _ in pairs(spec.dynamicMountedObjects) do
        if object:isa(Bale) then
            local fillType = object:getFillType()
            local fillLevel = object:getFillLevel()
            if not StrawHarvestBaleShredder.addBaleFillLevelInformation(fillType, fillLevel, fillLevelInformations) then
                table.insert(fillLevelInformations, { fillType = fillType, fillLevel = fillLevel, capacity = fillLevel })
            end
        end
    end
end
