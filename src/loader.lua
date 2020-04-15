---
-- loader
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: loader script for the mod
--
-- Copyright (c) Creative Mesh UG, 2019

local directory = g_currentModDirectory
local modName = g_currentModName

--- Console compatibility
local originalFunctions = {}

---Store backup of the vanilla function.
local function storeOriginalFunction(target, name)
    if originalFunctions[target] == nil then
        originalFunctions[target] = {}
    end

    -- Store the original function
    if originalFunctions[target][name] == nil then
        originalFunctions[target][name] = target[name]
    end
end

---Reset the vanilla function to it's original state.
local function resetOriginalFunction()
    for target, functions in pairs(originalFunctions) do
        for name, func in pairs(functions) do
            target[name] = func
        end
    end
end

-- Events
source(Utils.getFilename("src/events/StrawHarvestBaleGrabEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestResetBaleCountEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestCollectModeEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestCollectBaleEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestDepartBalesEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestCoverEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestVariableBaleSizeEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestCraneToolsEvent.lua", directory))
source(Utils.getFilename("src/events/StrawHarvestLoadDummyBaleEvent.lua", directory))

--Main
source(Utils.getFilename("src/StrawHarvest.lua", directory))

--Misc
source(Utils.getFilename("src/utils/StrawHarvestAnimationUtil.lua", directory))

--Object
source(Utils.getFilename("src/objects/StrawHarvestStorageBuffer.lua", directory))
source(Utils.getFilename("src/objects/StrawHarvestPalletizer.lua", directory))

-- GUI
source(Utils.getFilename("src/gui/hud/StrawHarvestBaleCounterHUD.lua", directory))

local strawHarvest
local strawHarvestZipName = "FS19_addon_strawHarvest"
local strawHarvestConsoleZipName = "FS19_addon_strawHarvest_console"

local function isEnabled()
    if GS_IS_CONSOLE_VERSION and not g_isDevelopmentConsoleScriptModTesting then
        return g_modIsLoaded[strawHarvestConsoleZipName] or g_modIsLoaded[strawHarvestConsoleZipName:lower()]
    end

    return g_modIsLoaded[strawHarvestZipName] or g_modIsLoaded[strawHarvestZipName:lower()]
end

local function loadMission(mission)
    if not isEnabled() then
        return
    end

    assert(g_strawHarvest == nil)

    strawHarvest = StrawHarvest:new(mission, directory, modName, g_i18n, g_gui, g_fillTypeManager, g_densityMapHeightManager, g_baleTypeManager, g_particleSystemManager)

    getfenv(0)["g_strawHarvest"] = strawHarvest
end

local function loadedMap(mission, node)
    if not isEnabled() then
        return
    end

    if node ~= 0 then
        strawHarvest:onMapLoaded(mission, node)
    end
end

local function loadedMission(mission, node)
    if not isEnabled() then
        return
    end

    if mission.cancelLoading then
        return
    end

    strawHarvest:onMissionLoaded(mission)
end

local function validateVehicleTypes(vehicleTypeManager)
    if not isEnabled() then
        return
    end

    if GS_IS_CONSOLE_VERSION then
        storeOriginalFunction(AnimalFoodManager, "loadFoodGroups")
    end

    AnimalFoodManager.loadFoodGroups = Utils.overwrittenFunction(AnimalFoodManager.loadFoodGroups, StrawHarvest.inj_animalFoodManager_loadFoodGroups)

    g_placeableTypeManager:addPlaceableType("strawHarvestPelletHall", "StrawHarvestPelletHall", directory .. "src/placeables/StrawHarvestPelletHall.lua")
end

---Unload the mod when the game is closed.
local function unload()
    if not isEnabled() then
        return
    end

    if GS_IS_CONSOLE_VERSION then
        resetOriginalFunction()
    end

    if strawHarvest ~= nil then
        strawHarvest:delete()
        -- GC
        strawHarvest = nil
        getfenv(0)["g_strawHarvest"] = nil
    end
end

local function registerPelletFillTypes()
    if not isEnabled() then
        return
    end

    StrawHarvest.fillTypeInit(directory, g_fillTypeManager, g_i18n)
end

local function registerPelletHeightTypes()
    if not isEnabled() then
        return
    end

    strawHarvest:heightTypeInit(directory, g_fillTypeManager, g_densityMapHeightManager)
end

---Call preSave function in order to remove anything before saving.
local function preSaveItems(mission)
    if not isEnabled() then
        return
    end

    for _, e in pairs(mission.itemsToSave) do
        local item = e.item
        if item.onPreSaveToXMLFile ~= nil then
            item:onPreSaveToXMLFile()
        end
    end
end

---Initialize the mod.
local function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, loadMission)
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
    Mission00.saveItems = Utils.prependedFunction(Mission00.saveItems, preSaveItems)

    FSBaseMission.loadMapFinished = Utils.prependedFunction(FSBaseMission.loadMapFinished, loadedMap)
    FSBaseMission.loadMap = Utils.appendedFunction(FSBaseMission.loadMap, registerPelletHeightTypes)
    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)
    FillTypeManager.loadMapData = Utils.appendedFunction(FillTypeManager.loadMapData, registerPelletFillTypes)

    if GS_IS_CONSOLE_VERSION then
        -- Static overwritten function
        local originalLoadPlaceable = PlacementUtil.loadPlaceable
        PlacementUtil.loadPlaceable = function(...)
            return inj_placementUtil_loadPlaceable(originalLoadPlaceable, ...)
        end

        storeOriginalFunction(MixerWagon, "onLoad")
        storeOriginalFunction(HusbandryModuleStraw, "load")
        storeOriginalFunction(HusbandryModuleStraw, "getFilltypeInfos")
        storeOriginalFunction(HusbandryModuleStraw, "addFillLevelFromTool")
        storeOriginalFunction(HusbandryModuleFood, "addFillLevelFromTool")
    end

    MixerWagon.onLoad = Utils.appendedFunction(MixerWagon.onLoad, StrawHarvest.inj_mixerWagon_onLoad)

    HusbandryModuleStraw.load = Utils.overwrittenFunction(HusbandryModuleStraw.load, StrawHarvest.inj_husbandryModuleStraw_load)
    HusbandryModuleStraw.getFilltypeInfos = Utils.overwrittenFunction(HusbandryModuleStraw.getFilltypeInfos, StrawHarvest.inj_husbandryModuleStraw_getFilltypeInfos)

    -- Fix for both specific as the HusbandryModuleFood isn't calling the superclass..
    HusbandryModuleStraw.addFillLevelFromTool = Utils.overwrittenFunction(HusbandryModuleStraw.addFillLevelFromTool, StrawHarvest.inj_husbandryModuleBase_addFillLevelFromTool)
    HusbandryModuleFood.addFillLevelFromTool = Utils.overwrittenFunction(HusbandryModuleFood.addFillLevelFromTool, StrawHarvest.inj_husbandryModuleBase_addFillLevelFromTool)
end

init()

-------------------------------------------------------------------------------
--- Script fixes
-------------------------------------------------------------------------------

---Get the mod name of the StrawHarvest DLC.
function Vehicle:strawHarvest_getModName()
    return modName
end

---Call method on specs before saving.
function Vehicle:onPreSaveToXMLFile()
    for _, spec in pairs(self.specializations) do
        if spec.onPreSaveToXMLFile ~= nil then
            spec.onPreSaveToXMLFile(self)
        end
    end
end

--- Bale mounting position fix.
--- Fix position synchronization of PhysicsObject after the position has been changed via setWorldPositionQuaternion.
--- With this fix it is directly sends the new/correct position instead of the old for one frame.
---
--- @author  Stefan Maurus
---
--- Copyright (C) GIANTS Software GmbH, Confidential, All Rights Reserved.
if not _G["g_baleMountingPositionSyncFixEnabled"] then
    _G["g_baleMountingPositionSyncFixEnabled"] = true

    PhysicsObject.setWorldPositionQuaternion = function(self, x, y, z, quatX, quatY, quatZ, quatW, changeInterp)
        setTranslation(self.nodeId, x, y, z)
        setQuaternion(self.nodeId, quatX, quatY, quatZ, quatW)

        if changeInterp then
            if not self.isServer then
                self.positionInterpolator:setPosition(x, y, z)
                self.quaternionInterpolator:setQuaternion(quatX, quatY, quatZ, quatW)
            else
                self:raiseDirtyFlags(self.physicsObjectDirtyFlag)
                self.sendPosX, self.sendPosY, self.sendPosZ = x, y, z
                self.sendRotX, self.sendRotY, self.sendRotZ = getRotation(self.nodeId)
            end
        end
    end
end

---Checks is the bale type actually is for round bales only, we have to check fields cause there's nothing obvious like TYPES.
local function isRoundBaleBaleType(baleType)
    return baleType.minBaleDiameter ~= nil and baleType.maxBaleDiameter ~= nil
end

---Add validation of bale types with rounded values.
local function validateBaleTypes(bale, baleTypes)
    local isRoundBale = bale.baleDiameter ~= nil
    local baleDiameter = MathUtil.round(Utils.getNoNil(bale.baleDiameter, 0), 2)
    local baleWidth = MathUtil.round(Utils.getNoNil(bale.baleWidth, 0), 2)
    local baleHeight = MathUtil.round(Utils.getNoNil(bale.baleHeight, 0), 2)
    local baleLength = MathUtil.round(Utils.getNoNil(bale.baleLength, 0), 2)

    if baleTypes ~= nil then
        for _, baleType in pairs(baleTypes) do
            if isRoundBaleBaleType(baleType) then
                if isRoundBale and baleDiameter ~= 0 and baleWidth ~= 0 then
                    if baleDiameter >= baleType.minBaleDiameter and baleDiameter <= baleType.maxBaleDiameter and
                            baleWidth >= baleType.minBaleWidth and baleWidth <= baleType.maxBaleWidth
                    then
                        return baleType
                    end
                end
            else
                if not isRoundBale and baleHeight ~= 0 and baleWidth ~= 0 and baleLength ~= 0 then
                    if baleHeight >= baleType.minBaleHeight and baleHeight <= baleType.maxBaleHeight and
                            baleWidth >= baleType.minBaleWidth and baleWidth <= baleType.maxBaleWidth and
                            baleLength >= baleType.minBaleLength and baleLength <= baleType.maxBaleLength
                    then
                        return baleType
                    end
                end
            end
        end
    end

    return nil
end

---Fix bale validation for the bale loader to accept new bale types.
function BaleLoader.getBaleInRange(self, refNode, balesInTrigger)
    local spec = self.spec_baleLoader
    local nearestDistance = spec.baleGrabber.pickupRange
    local nearestBale
    local nearestBaleType

    for bale, state in pairs(balesInTrigger) do
        if state ~= nil and state > 0 then
            local isValidBale = true
            for _, balePlace in pairs(spec.balePlaces) do
                if balePlace.bales ~= nil then
                    for _, baleServerId in pairs(balePlace.bales) do
                        local baleInPlace = NetworkUtil.getObject(baleServerId)
                        if baleInPlace ~= nil and baleInPlace == bale then
                            isValidBale = false
                        end
                    end
                end
            end
            for _, baleServerId in ipairs(spec.startBalePlace.bales) do
                local baleInPlace = NetworkUtil.getObject(baleServerId)
                if baleInPlace ~= nil and baleInPlace == bale then
                    isValidBale = false
                end
            end

            if bale == nil
                    or not entityExists(bale.nodeId)
                    or bale.dynamicMountJointIndex ~= nil
                    or not bale:getBaleSupportsBaleLoader() then
                isValidBale = false
            end

            if isValidBale then
                local distance = calcDistanceFrom(refNode, bale.nodeId)
                if distance < nearestDistance then
                    local foundBaleType = validateBaleTypes(bale, spec.allowedBaleTypes)

                    if foundBaleType ~= nil or nearestBaleType == nil then
                        if foundBaleType ~= nil then
                            nearestDistance = distance
                        end
                        nearestBale = bale
                        nearestBaleType = foundBaleType
                    end
                end

            end
        end
    end

    return nearestBale, nearestBaleType
end

---Fix bale validation for the bale wrapper to accept new bale types.
function BaleWrapper:getWrapperBaleType(bale)
    local spec = self.spec_baleWrapper
    if spec.strawHarvest_didFixAllowedBaleTypes == nil then
        local function fixRoundings(allowedBaleTypes, isRoundBaleWrapper)
            for _, baleTypes in pairs(allowedBaleTypes) do
                if baleTypes ~= nil then
                    for _, baleType in ipairs(baleTypes) do
                        baleType.minBaleWidth = MathUtil.round(baleType.minBaleWidth, 2)
                        baleType.maxBaleWidth = MathUtil.round(baleType.maxBaleWidth, 2)

                        if isRoundBaleWrapper then
                            baleType.minBaleDiameter = MathUtil.round(baleType.minBaleDiameter, 2)
                            baleType.maxBaleDiameter = MathUtil.round(baleType.maxBaleDiameter, 2)
                        else
                            baleType.minBaleHeight = MathUtil.round(baleType.minBaleHeight, 2)
                            baleType.maxBaleHeight = MathUtil.round(baleType.maxBaleHeight, 2)
                            baleType.minBaleLength = MathUtil.round(baleType.minBaleLength, 2)
                            baleType.maxBaleLength = MathUtil.round(baleType.maxBaleLength, 2)
                        end
                    end
                end
            end
        end

        fixRoundings(spec.roundBaleWrapper.allowedBaleTypes, true)
        fixRoundings(spec.squareBaleWrapper.allowedBaleTypes, false)
        spec.strawHarvest_didFixAllowedBaleTypes = true
    end

    local baleTypes
    if bale.baleDiameter ~= nil then
        baleTypes = spec.roundBaleWrapper.allowedBaleTypes[bale:getFillType()]
    else
        baleTypes = spec.squareBaleWrapper.allowedBaleTypes[bale:getFillType()]
    end

    return validateBaleTypes(bale, baleTypes)
end

-------------------------------------------------------------------------------
--- Console script fixes
-------------------------------------------------------------------------------

if GS_IS_CONSOLE_VERSION then
    ---Turn FS19_addon_strawHarvest into a _console version
    function inj_placementUtil_loadPlaceable(superFunc, placeableType, ...)
        if isEnabled() then
            if placeableType == "FS19_addon_strawHarvest.strawHarvestPelletHall" then
                placeableType = "FS19_addon_strawHarvest_console.strawHarvestPelletHall"
            end
        end

        return superFunc(placeableType, ...)
    end
end
