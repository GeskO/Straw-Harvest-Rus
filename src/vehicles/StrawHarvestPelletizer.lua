---
-- StrawHarvestPelletizer
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Converts input filltype to pellets.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestPelletizer
StrawHarvestPelletizer = {}
StrawHarvestPelletizer.MOD_NAME = g_currentModName

StrawHarvestPelletizer.DEFAULT_SPEED_LIMIT = 10
StrawHarvestPelletizer.TIMER_THRESHOLD = 500

function StrawHarvestPelletizer.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations) and
            SpecializationUtil.hasSpecialization(TurnOnVehicle, specializations) and
            SpecializationUtil.hasSpecialization(Pickup, specializations) and
            SpecializationUtil.hasSpecialization(WorkArea, specializations)
end

function StrawHarvestPelletizer.initSpecialization()
    g_workAreaTypeManager:addWorkAreaType("pelletizer", false)
end

function StrawHarvestPelletizer.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "processPelletizerArea", StrawHarvestPelletizer.processPelletizerArea)
    SpecializationUtil.registerFunction(vehicleType, "setEffectActive", StrawHarvestPelletizer.setEffectActive)
    SpecializationUtil.registerFunction(vehicleType, "isStationary", StrawHarvestPelletizer.isStationary)
    SpecializationUtil.registerFunction(vehicleType, "isShreddingBaleAllowed", StrawHarvestPelletizer.isShreddingBaleAllowed)
    SpecializationUtil.registerFunction(vehicleType, "hasAttachedBaleShredder", StrawHarvestPelletizer.hasAttachedBaleShredder)
    SpecializationUtil.registerFunction(vehicleType, "getAttachedBaleShredder", StrawHarvestPelletizer.getAttachedBaleShredder)
    SpecializationUtil.registerFunction(vehicleType, "fillPelletizer", StrawHarvestPelletizer.fillPelletizer)

end

function StrawHarvestPelletizer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsWorkAreaActive", StrawHarvestPelletizer.getIsWorkAreaActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "doCheckSpeedLimit", StrawHarvestPelletizer.doCheckSpeedLimit)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getConsumingLoad", StrawHarvestPelletizer.getConsumingLoad)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanChangePickupState", StrawHarvestPelletizer.getCanChangePickupState)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", StrawHarvestPelletizer.getCanBeTurnedOn)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getTurnedOnNotAllowedWarning", StrawHarvestPelletizer.getTurnedOnNotAllowedWarning)
end

function StrawHarvestPelletizer.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onStartWorkAreaProcessing", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onEndWorkAreaProcessing", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onTurnedOn", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onTurnedOff", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onDeactivate", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttachImplement", StrawHarvestPelletizer)
    SpecializationUtil.registerEventListener(vehicleType, "onPostDetachImplement", StrawHarvestPelletizer)
end

---Called on load.
function StrawHarvestPelletizer:onLoad(savegame)
    self.spec_strawHarvestPelletizer = self[("spec_%s.strawHarvestPelletizer"):format(StrawHarvestPelletizer.MOD_NAME)]
    local spec = self.spec_strawHarvestPelletizer

    spec.isFilling = false
    spec.pickupFillType = FillType.UNKNOWN
    spec.isFillingSent = false
    spec.fillTimer = 0

    spec.fillUnitIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.pelletizer#fillUnitIndex"), 1)
    spec.workAreaIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.pelletizer#workAreaIndex"), 1)

    spec.fillTypeConverters = {}
    spec.fillTypeConvertersByOutput = {}

    local i = 0
    while true do
        local key = ("vehicle.pelletizer.fillTypeConverters.fillTypeConverter(%d)"):format(i)
        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local inputFillTypeStr = getXMLString(self.xmlFile, key .. "#inputFillType")
        local outputFillTypeStr = getXMLString(self.xmlFile, key .. "#outputFillType")
        local conversionFactor = Utils.getNoNil(getXMLFloat(self.xmlFile, key .. "#conversionFactor"), 1)

        if inputFillTypeStr ~= nil and outputFillTypeStr ~= nil then
            local inputFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(inputFillTypeStr)
            local outputFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(outputFillTypeStr)

            if inputFillTypeIndex ~= nil and outputFillTypeIndex ~= nil then
                spec.fillTypeConverters[inputFillTypeIndex] = { targetFillTypeIndex = outputFillTypeIndex, conversionFactor = conversionFactor }
                spec.fillTypeConvertersByOutput[outputFillTypeIndex] = { sourceFillTypeIndex = inputFillTypeIndex, conversionFactor = conversionFactor }
            else
                g_logManager:warning("Invalid fill type converter for fill types: %s and %s!", inputFillTypeStr, outputFillTypeStr)
            end
        end

        i = i + 1
    end

    -- Add semidry when seasons is enabled.
    if g_seasons ~= nil then
        spec.fillTypeConverters[FillType.SEMIDRY_GRASS_WINDROW] = { targetFillTypeIndex = FillType.HAYPELLETS, conversionFactor = 0.25 }
        spec.fillTypeConvertersByOutput[FillType.HAYPELLETS] = { sourceFillTypeIndex = FillType.SEMIDRY_GRASS_WINDROW, conversionFactor = 0.25 }
    end

    if self.isClient then
        spec.animationNodes = g_animationManager:loadAnimations(self.xmlFile, "vehicle.pelletizer.animationNodes", self.components, self, self.i3dMappings)
        spec.inputEffects = g_effectManager:loadEffect(self.xmlFile, "vehicle.pelletizer.inputEffect", self.components, self, self.i3dMappings)
        spec.outputEffects = g_effectManager:loadEffect(self.xmlFile, "vehicle.pelletizer.outputEffect", self.components, self, self.i3dMappings)
    end

    spec.workAreaParameters = {}
    spec.workAreaParameters.lastPickupLiters = 0
    spec.workAreaParameters.lastPickupFillType = FillType.UNKNOWN

    spec.maxPickupLitersPerSecond = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.pelletizer#maxPickupLitersPerSecond"), 150)
    spec.pickUpLitersBuffer = ValueBuffer:new(750)
    spec.dirtyFlag = self:getNextDirtyFlag()

    spec.attachedBaleShredder = nil
    spec.attachedBaleShredderJointIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.pelletizer#attachedBaleShredderJointIndex"), 1)
end

function StrawHarvestPelletizer:onDelete()
    local spec = self.spec_strawHarvestPelletizer

    if self.isClient then
        g_animationManager:deleteAnimations(spec.animationNodes)
        g_effectManager:deleteEffects(spec.inputEffects)
        g_effectManager:deleteEffects(spec.outputEffects)
    end
end

function StrawHarvestPelletizer:onReadStream(streamId, connection)
    local spec = self.spec_strawHarvestPelletizer
    spec.isFilling = streamReadBool(streamId)
    spec.pickupFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
end

function StrawHarvestPelletizer:onWriteStream(streamId, connection)
    local spec = self.spec_strawHarvestPelletizer
    streamWriteBool(streamId, spec.isFillingSent)
    streamWriteUIntN(streamId, spec.pickupFillType, FillTypeManager.SEND_NUM_BITS)
end

function StrawHarvestPelletizer:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self.spec_strawHarvestPelletizer
        if streamReadBool(streamId) then
            spec.isFilling = streamReadBool(streamId)
            spec.pickupFillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
            self:setEffectActive(spec.isFilling)
        end
    end
end

function StrawHarvestPelletizer:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self.spec_strawHarvestPelletizer
        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteBool(streamId, spec.isFilling)
            streamWriteUIntN(streamId, spec.pickupFillType, FillTypeManager.SEND_NUM_BITS)
        end
    end
end

function StrawHarvestPelletizer:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_strawHarvestPelletizer

    if self.isServer then
        if self:isStationary() then
            spec.workAreaParameters.lastPickupLiters = 0
            spec.workAreaParameters.lastPickupFillType = FillType.UNKNOWN

            local baleShredder = self:getAttachedBaleShredder()
            if baleShredder ~= nil then
                if self:getFillUnitFreeCapacity(spec.fillUnitIndex) ~= 0 then
                    local delta, fillType = baleShredder:processBale(dt)
                    if delta > 0 then
                        self:fillPelletizer(delta, fillType)
                        spec.workAreaParameters.lastPickupLiters = spec.workAreaParameters.lastPickupLiters + delta
                        spec.workAreaParameters.lastPickupFillType = fillType
                    end
                else
                    self:setIsTurnedOn(false)
                end
            end
        end

        local lastPickupFillType = spec.workAreaParameters.lastPickupFillType
        local isFilling = spec.fillTimer > 0
        if isFilling then
            spec.fillTimer = spec.fillTimer - dt
        end

        spec.isFilling = isFilling

        if spec.isFilling ~= spec.isFillingSent
                or spec.pickupFillType ~= lastPickupFillType then
            spec.pickupFillType = lastPickupFillType
            spec.isFillingSent = spec.isFilling
            self:raiseDirtyFlags(spec.dirtyFlag)
            self:setEffectActive(spec.isFilling)
        end

        spec.pickUpLitersBuffer:add(spec.workAreaParameters.lastPickupLiters)
    end
end

---Checks whether or not the bale fill type on the shredder is allowed.
function StrawHarvestPelletizer:isShreddingBaleAllowed(fillType)
    local spec = self.spec_strawHarvestPelletizer
    local lastFillType = self:getFillUnitFillType(spec.fillUnitIndex)
    local lastInputFillType = spec.fillTypeConvertersByOutput[lastFillType]

    local allowsFillType = spec.fillTypeConverters[fillType] ~= nil

    return allowsFillType and (lastFillType == FillType.UNKNOWN
            or (lastInputFillType ~= nil and fillType == lastInputFillType.sourceFillTypeIndex))
end

---Checks when a bale shredder is attached and if it's in working position.
function StrawHarvestPelletizer:isStationary()
    if not self:getIsTurnedOn() then
        return false
    end

    if self:hasAttachedBaleShredder() then
        local baleShredder = self:getAttachedBaleShredder()
        if baleShredder:getIsInWorkPosition() then
            return true
        end
    end

    return false
end

function StrawHarvestPelletizer:hasAttachedBaleShredder()
    local spec = self.spec_strawHarvestPelletizer
    return spec.attachedBaleShredder ~= nil
end

function StrawHarvestPelletizer:getAttachedBaleShredder()
    local spec = self.spec_strawHarvestPelletizer
    return spec.attachedBaleShredder
end

function StrawHarvestPelletizer:setEffectActive(isActive)
    local spec = self.spec_strawHarvestPelletizer

    if isActive then
        if spec.inputEffects ~= nil then
            local lastValidFillType = spec.pickupFillType
            g_effectManager:setFillType(spec.inputEffects, lastValidFillType)
            g_effectManager:startEffects(spec.inputEffects)
        end
        if spec.outputEffects ~= nil then
            local lastValidFillType = self:getFillUnitLastValidFillType(spec.fillUnitIndex)
            g_effectManager:setFillType(spec.outputEffects, lastValidFillType)
            g_effectManager:startEffects(spec.outputEffects)
        end
    else
        if spec.inputEffects ~= nil then
            g_effectManager:stopEffects(spec.inputEffects)
        end

        if spec.outputEffects ~= nil then
            g_effectManager:stopEffects(spec.outputEffects)
        end
    end
end

function StrawHarvestPelletizer:processPelletizerArea(workArea)
    local spec = self.spec_strawHarvestPelletizer

    local currentFillType = spec.workAreaParameters.lastPickupFillType
    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByArea(workArea.start, workArea.width, workArea.height)
    local inputLiters = 0

    if currentFillType ~= FillType.UNKNOWN then
        inputLiters = -DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, currentFillType, lsx, lsy, lsz, lex, ley, lez, lineRadius, nil, nil, false, nil)
    else
        for inputFruitType, _ in pairs(spec.fillTypeConverters) do
            inputLiters = -DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFruitType, lsx, lsy, lsz, lex, ley, lez, lineRadius, nil, nil, false, nil)
            if inputLiters > 0 then
                currentFillType = inputFruitType
                break
            end
        end
    end

    spec.workAreaParameters.lastPickupFillType = currentFillType
    spec.workAreaParameters.lastPickupLiters = spec.workAreaParameters.lastPickupLiters + inputLiters

    return inputLiters, inputLiters
end

function StrawHarvestPelletizer:onStartWorkAreaProcessing(dt)
    local spec = self.spec_strawHarvestPelletizer
    spec.workAreaParameters.lastPickupLiters = 0
    spec.workAreaParameters.lastPickupFillType = FillType.UNKNOWN

    local fillLevel = self:getFillUnitFillLevel(spec.fillUnitIndex)
    if fillLevel > self:getFillTypeChangeThreshold(spec.fillUnitIndex) then
        local lastPickupFillType = spec.fillTypeConvertersByOutput[self:getFillUnitFillType(spec.fillUnitIndex)]
        spec.workAreaParameters.lastPickupFillType = lastPickupFillType.sourceFillTypeIndex
    end
end

function StrawHarvestPelletizer:onEndWorkAreaProcessing(dt, hasProcessed)
    local spec = self.spec_strawHarvestPelletizer
    if self.isServer then
        -- Convert picked up filltype to pellet.
        local inputLiters = spec.workAreaParameters.lastPickupLiters
        local inputFruitType = spec.workAreaParameters.lastPickupFillType

        if inputLiters > 0 then
            self:fillPelletizer(inputLiters, inputFruitType)
        end
    end
end

function StrawHarvestPelletizer:fillPelletizer(inputLiters, inputFruitType)
    local spec = self.spec_strawHarvestPelletizer
    local conversionFactor = 1.0
    local outputFillType = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(inputFruitType)

    if spec.fillTypeConverters[inputFruitType] ~= nil then
        outputFillType = spec.fillTypeConverters[inputFruitType].targetFillTypeIndex
        conversionFactor = spec.fillTypeConverters[inputFruitType].conversionFactor
    end

    local deltaFillLevel = inputLiters * conversionFactor

    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.fillUnitIndex, deltaFillLevel, outputFillType, ToolType.UNDEFINED)

    spec.fillTimer = StrawHarvestPelletizer.TIMER_THRESHOLD
end

function StrawHarvestPelletizer:onTurnedOn()
    local spec = self.spec_strawHarvestPelletizer

    if self.isClient then
        g_animationManager:startAnimations(spec.animationNodes)
    end
end

function StrawHarvestPelletizer:onTurnedOff()
    local spec = self.spec_strawHarvestPelletizer

    if self.isClient then
        spec.fillTimer = 0
        self:setEffectActive(false)
        g_animationManager:stopAnimations(spec.animationNodes)
    end
end

function StrawHarvestPelletizer:onDeactivate()
    local spec = self.spec_strawHarvestPelletizer

    if self.isClient then
        spec.fillTimer = 0
        self:setEffectActive(false)
    end
end

function StrawHarvestPelletizer:onPostAttachImplement(attachable, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_strawHarvestPelletizer
    if jointDescIndex == spec.attachedBaleShredderJointIndex then
        spec.attachedBaleShredder = attachable
        -- Higher the pickup.
        self:setPickupState(false)
    end
end

function StrawHarvestPelletizer:onPostDetachImplement(implementIndex)
    local spec = self.spec_strawHarvestPelletizer
    local attachedImplements = self:getAttachedImplements()
    if attachedImplements[implementIndex].jointDescIndex == spec.attachedBaleShredderJointIndex then
        spec.attachedBaleShredder = nil
    end
end

----------------
-- Overwrites --
----------------

---The pickup can only change it's state when no bale shredder is attached.
function StrawHarvestPelletizer:getCanChangePickupState(superFunc, newState)
    if self:hasAttachedBaleShredder() then
        return false
    end

    return superFunc(self, newState)
end

---Returns true when the bale shredder is in working position when attached, false otherwise.
function StrawHarvestPelletizer:getCanBeTurnedOn(superFunc)
    if self:hasAttachedBaleShredder() then
        local baleShredder = self:getAttachedBaleShredder()
        if not baleShredder:getIsInWorkPosition() then
            return false
        end
    end

    return superFunc(self)
end

---Returns the unfold bale shredder warning text when the player try's to turn on the vehicle while the bale shredder is folded.
function StrawHarvestPelletizer:getTurnedOnNotAllowedWarning(superFunc)
    if self:hasAttachedBaleShredder() then
        local baleShredder = self:getAttachedBaleShredder()
        if not baleShredder:getIsInWorkPosition() then
            return g_i18n:getText("warning_firstUnfoldTheTool"):format(baleShredder:getName())
        end
    end

    return superFunc(self)
end

---The workarea is only active when the pelletizer is turned on and when the pickup is lowered.
function StrawHarvestPelletizer:getIsWorkAreaActive(superFunc, workArea)
    local spec = self.spec_strawHarvestPelletizer
    local area = self.spec_workArea.workAreas[spec.workAreaIndex]

    if area ~= nil and workArea == area then
        if not self:getIsTurnedOn() or not self:allowPickingUp() then
            return false
        end
    end

    if self:getFillUnitFreeCapacity(spec.fillUnitIndex) == 0 then
        return false
    end

    return superFunc(self, workArea)
end

---Gets the default speed limit.
function StrawHarvestPelletizer.getDefaultSpeedLimit()
    return StrawHarvestPelletizer.DEFAULT_SPEED_LIMIT
end

---Check speedlimit when turned on or when lowered.
function StrawHarvestPelletizer:doCheckSpeedLimit(superFunc)
    return superFunc(self) or (self:getIsTurnedOn() and self:getIsLowered())
end

---Calculate the load based on the liters per second from the buffer.
function StrawHarvestPelletizer:getConsumingLoad(superFunc)
    local value, count = superFunc(self)

    local spec = self.spec_strawHarvestPelletizer
    local loadPercentage = spec.pickUpLitersBuffer:get(1000) / spec.maxPickupLitersPerSecond

    return value + loadPercentage, count + 1
end
