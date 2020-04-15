---
-- StrawHarvest
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Main class for the StrawHarvest DLC.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvest
StrawHarvest = {}

local StrawHarvest_mt = Class(StrawHarvest)

---Creates a new instance of the StrawHarvest.
---@return StrawHarvest
function StrawHarvest:new(mission, modDirectory, modName, i18n, gui, fillTypeManager, densityMapHeightManager, baleTypeManager, particleSystemManager)
    local self = {}

    setmetatable(self, StrawHarvest_mt)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    self.modDirectory = modDirectory
    self.modName = modName

    self.mission = mission
    self.i18n = i18n
    self.gui = gui
    self.fillTypeManager = fillTypeManager
    self.densityMapHeightManager = densityMapHeightManager
    self.baleTypeManager = baleTypeManager
    self.particleSystemManager = particleSystemManager

    self.baleCounterHud = StrawHarvestBaleCounterHUD:new(self, mission.inGameMenu.hud.fillLevelsDisplay)
    self.failedToLoadDueTooManyHeightTypes = false

    return self
end

function StrawHarvest:delete()
    self:unloadFillTypes()
    self:unloadBaleTypes()

    self.baleCounterHud:delete()
end

---Register the pellet filltypes early in order to be able to add them to the food groups for the animals.
function StrawHarvest.fillTypeInit(modDirectory, fillTypeManager, i18n)
    StrawHarvest.loadStrawPelletFillType(modDirectory, fillTypeManager, i18n)
    StrawHarvest.loadHayPelletFillType(modDirectory, fillTypeManager, i18n)
end

function StrawHarvest:heightTypeInit(modDirectory, fillTypeManager, densityMapHeightManager)
    -- Test if we can load 2 more height types (straw and hay pellets).
    if self.densityMapHeightManager.numHeightTypes + 2 > (2 ^ self.mission.terrainDetailHeightTypeNumChannels) - 1 then
        self.failedToLoadDueTooManyHeightTypes = true
    end

    StrawHarvest.loadStrawPelletHeightType(modDirectory, fillTypeManager, densityMapHeightManager)
    StrawHarvest.loadHayPelletHeightType(modDirectory, fillTypeManager, densityMapHeightManager)
end

function StrawHarvest:onMapLoaded(mission, node)
    self:loadFillTypes()
    self:loadBaleTypes()
end

function StrawHarvest:onMissionLoaded(mission)
    self.baleCounterHud:load()

    -- If we were unable to load the height types we need to quit or errors will happen during gameplay.
    if self.failedToLoadDueTooManyHeightTypes then
        self.gui:showInfoDialog({
            dialogType = DialogElement.TYPE_INFO,
            text = self.i18n:getText("strawHarvest_message_failedHeightTypes"),
            target = nil,
            callback = function()
                OnInGameMenuMenu()
            end
        })
    end
end

------------------------
-- Register fillTypes --
------------------------

---Load all the filltypes from the mod.
function StrawHarvest:loadFillTypes()
    -- Add new particle types.
    self.particleSystemManager:addParticleType("pellet")
    self.particleSystemManager:addParticleType("pellet_move")
    self.particleSystemManager:addParticleType("pellet_smoke")

    local strawPelletsMaterialHolderFilename = Utils.getFilename("resources/fillTypes/strawPellets/strawPelletsMaterialHolder.i3d", self.modDirectory)
    self.strawPelletsMaterialHolder = loadI3DFile(strawPelletsMaterialHolderFilename, false, true, false)

    local strawPelletsParticleMaterialHolderFilename = Utils.getFilename("resources/fillTypes/strawPellets/strawPellets_particles.i3d", self.modDirectory)
    self.strawPelletsParticleMaterialHolder = loadI3DFile(strawPelletsParticleMaterialHolderFilename, false, true, false)

    local hayPelletsMaterialHolderFilename = Utils.getFilename("resources/fillTypes/hayPellets/hayPelletsMaterialHolder.i3d", self.modDirectory)
    self.hayPelletsMaterialHolder = loadI3DFile(hayPelletsMaterialHolderFilename, false, true, false)

    local hayPelletsParticleMaterialHolderFilename = Utils.getFilename("resources/fillTypes/hayPellets/hayPellets_particles.i3d", self.modDirectory)
    self.hayPelletsParticleMaterialHolder = loadI3DFile(hayPelletsParticleMaterialHolderFilename, false, true, false)

    self:loadMolassesFillType()
    self:loadBaleNetFillType()
    self:loadBaleTwineFillType()

    self.mission.hud.fillLevelsDisplay:refreshFillTypes(self.fillTypeManager)
end

---Call the unload methods.
function StrawHarvest:unloadFillTypes()
    self:unloadStrawPelletFillType()
    self:unloadHayPelletFillType()
end

---Load fill type strawPellet.
function StrawHarvest.loadStrawPelletFillType(modDirectory, fillTypeManager, i18n)
    local hudOverlayFilename = "resources/hud/fillTypes/hud_fill_strawPellets.png"
    local hudOverlayFilenameSmall = "resources/hud/fillTypes/hud_fill_strawPellets_small.png"
    local price = 0.6
    local massPerLiter = .75 / 1000 -- 0.00075
    local maxPhysicalSurfaceAngle = 38

    fillTypeManager:addFillType("STRAWPELLETS", i18n:getText("fillType_strawPellets"), true, price, massPerLiter, maxPhysicalSurfaceAngle, hudOverlayFilename, hudOverlayFilenameSmall, modDirectory, nil, { 1, 1, 1 }, nil, false)
end

---Add strawPellet density height type and load the materialholder.
function StrawHarvest.loadStrawPelletHeightType(modDirectory, fillTypeManager, densityMapHeightManager)
    local fillTypeIndex = fillTypeManager:getFillTypeIndexByName("strawPellets")
    fillTypeManager:addFillTypeToCategory(fillTypeIndex, fillTypeManager.nameToCategoryIndex["BULK"])

    g_fillTypeManager.fillTypeToSample[fillTypeIndex] = g_fillTypeManager.fillTypeToSample[FillType.WOODCHIPS]

    local diffuseMapFilename = Utils.getFilename("resources/fillTypes/strawPellets/strawPellets_diffuse.png", modDirectory)
    local normalMapFilename = Utils.getFilename("resources/fillTypes/pellets_normal.png", modDirectory)
    local distanceMapFilename = Utils.getFilename("resources/fillTypes/strawPellets/strawPellets_distance.png", modDirectory)

    local maxPhysicalSurfaceAngle = math.rad(38)
    local collisionScale = 1
    local collisionBaseOffset = 0.2
    local minCollisionOffset = 0.2
    local maxCollisionOffset = 0.5
    local fillToGroundScale = 1

    local strawPelletsHeightType = densityMapHeightManager:addDensityMapHeightType("STRAWPELLETS", maxPhysicalSurfaceAngle, collisionScale, collisionBaseOffset, minCollisionOffset, maxCollisionOffset, fillToGroundScale, true, diffuseMapFilename, normalMapFilename, distanceMapFilename, false)
    if strawPelletsHeightType == nil then
        log("Could not create the STRAW PELLETS height type. The combination of map and mods are not compatible")
    end
end

---Load fill type hayPellet.
function StrawHarvest.loadHayPelletFillType(modDirectory, fillTypeManager, i18n)
    local hudOverlayFilename = "resources/hud/fillTypes/hud_fill_hayPellets.png"
    local hudOverlayFilenameSmall = "resources/hud/fillTypes/hud_fill_hayPellets_small.png"
    local price = 0.8
    local massPerLiter = .75 / 1000 -- 0.00075
    local maxPhysicalSurfaceAngle = 38

    fillTypeManager:addFillType("HAYPELLETS", i18n:getText("fillType_hayPellets"), true, price, massPerLiter, maxPhysicalSurfaceAngle, hudOverlayFilename, hudOverlayFilenameSmall, modDirectory, nil, { 1, 1, 1 }, nil, false)
end

---Add hayPellet density height type and load the materialholder.
function StrawHarvest.loadHayPelletHeightType(modDirectory, fillTypeManager, densityMapHeightManager)
    local fillTypeIndex = fillTypeManager:getFillTypeIndexByName("hayPellets")
    fillTypeManager:addFillTypeToCategory(fillTypeIndex, fillTypeManager.nameToCategoryIndex["BULK"])

    g_fillTypeManager.fillTypeToSample[fillTypeIndex] = g_fillTypeManager.fillTypeToSample[FillType.WOODCHIPS]

    local diffuseMapFilename = Utils.getFilename("resources/fillTypes/hayPellets/hayPellets_diffuse.png", modDirectory)
    local normalMapFilename = Utils.getFilename("resources/fillTypes/pellets_normal.png", modDirectory)
    local distanceMapFilename = Utils.getFilename("resources/fillTypes/hayPellets/hayPellets_distance.png", modDirectory)

    local maxPhysicalSurfaceAngle = math.rad(38)
    local collisionScale = 1
    local collisionBaseOffset = 0.2
    local minCollisionOffset = 0.2
    local maxCollisionOffset = 0.5
    local fillToGroundScale = 1

    local hayPelletsHeightType = densityMapHeightManager:addDensityMapHeightType("HAYPELLETS", maxPhysicalSurfaceAngle, collisionScale, collisionBaseOffset, minCollisionOffset, maxCollisionOffset, fillToGroundScale, true, diffuseMapFilename, normalMapFilename, distanceMapFilename, false)
    if hayPelletsHeightType == nil then
        log("Could not create the HAY PELLETS height type. The combination of map and mods are not compatible")
    end
end

---Unload fill type strawPellet and delete the materialholder.
function StrawHarvest:unloadStrawPelletFillType()
    if self.strawPelletsMaterialHolder ~= nil then
        delete(self.strawPelletsMaterialHolder)
        self.strawPelletsMaterialHolder = nil
    end

    if self.strawPelletsParticleMaterialHolder ~= nil then
        delete(self.strawPelletsParticleMaterialHolder)
        self.strawPelletsParticleMaterialHolder = nil
    end
end

---Unload fill type hayPellet and delete the materialholder.
function StrawHarvest:unloadHayPelletFillType()
    if self.hayPelletsMaterialHolder ~= nil then
        delete(self.hayPelletsMaterialHolder)
        self.hayPelletsMaterialHolder = nil
    end

    if self.hayPelletsParticleMaterialHolder ~= nil then
        delete(self.hayPelletsParticleMaterialHolder)
        self.hayPelletsParticleMaterialHolder = nil
    end
end

---Load fill type molasses.
function StrawHarvest:loadMolassesFillType()
    local hudOverlayFilename = "resources/hud/fillTypes/hud_fill_molasses.png"
    local hudOverlayFilenameSmall = "resources/hud/fillTypes/hud_fill_molasses_small.png"
    local price = 3
    local massPerLiter = 1 / 1000
    local maxPhysicalSurfaceAngle = 0

    self.fillTypeManager:addFillType("MOLASSES", self.i18n:getText("fillType_molasses"), false, price, massPerLiter, maxPhysicalSurfaceAngle, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)
end

---Load fill type baleNet.
function StrawHarvest:loadBaleNetFillType()
    local hudOverlayFilename = "resources/hud/fillTypes/hud_fill_baleNet.png"
    local hudOverlayFilenameSmall = "resources/hud/fillTypes/hud_fill_baleNet_small.png"
    local price = 3
    local massPerLiter = 1 / 1000
    local maxPhysicalSurfaceAngle = 25

    self.fillTypeManager:addFillType("BALENET", self.i18n:getText("fillType_baleNet"), false, price, massPerLiter, maxPhysicalSurfaceAngle, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)
end

---Load fill type baleTwine.
function StrawHarvest:loadBaleTwineFillType()
    local hudOverlayFilename = "resources/hud/fillTypes/hud_fill_baleTwine.png"
    local hudOverlayFilenameSmall = "resources/hud/fillTypes/hud_fill_baleTwine_small.png"
    local price = 3
    local massPerLiter = 1 / 1000
    local maxPhysicalSurfaceAngle = 25

    self.fillTypeManager:addFillType("BALETWINE", self.i18n:getText("fillType_baleTwine"), false, price, massPerLiter, maxPhysicalSurfaceAngle, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)
end

------------------------
-- Register baleTypes --
------------------------

---Loads the bale types.
function StrawHarvest:loadBaleTypes()
    local baleTypes = {}
    --Square bales
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/squareBales/squareBaleStraw_8Knots.i3d", self.modDirectory), "STRAW", false, 1.2, 0.85, 2.39, 0))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/squareBales/squareBaleGrass_8Knots.i3d", self.modDirectory), "GRASS_WINDROW", false, 1.2, 0.85, 2.39, 0))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/squareBales/squareBaleHay_8Knots.i3d", self.modDirectory), "DRYGRASS_WINDROW", false, 1.2, 0.85, 2.39, 0))

    --Round bales
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleStraw_w120_d110.i3d", self.modDirectory), "STRAW", true, 1.2, 0, 0, 1.1))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleStraw_w120_d130.i3d", self.modDirectory), "STRAW", true, 1.2, 0, 0, 1.3))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleStraw_w120_d155.i3d", self.modDirectory), "STRAW", true, 1.2, 0, 0, 1.55))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleStraw_w120_d180.i3d", self.modDirectory), "STRAW", true, 1.2, 0, 0, 1.8))

    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleGrass_w120_d110.i3d", self.modDirectory), "GRASS_WINDROW", true, 1.2, 0, 0, 1.1))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleGrass_w120_d130.i3d", self.modDirectory), "GRASS_WINDROW", true, 1.2, 0, 0, 1.3))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleGrass_w120_d155.i3d", self.modDirectory), "GRASS_WINDROW", true, 1.2, 0, 0, 1.55))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleGrass_w120_d180.i3d", self.modDirectory), "GRASS_WINDROW", true, 1.2, 0, 0, 1.8))

    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleHay_w120_d110.i3d", self.modDirectory), "DRYGRASS_WINDROW", true, 1.2, 0, 0, 1.1))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleHay_w120_d130.i3d", self.modDirectory), "DRYGRASS_WINDROW", true, 1.2, 0, 0, 1.3))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleHay_w120_d155.i3d", self.modDirectory), "DRYGRASS_WINDROW", true, 1.2, 0, 0, 1.55))
    table.insert(baleTypes, self.baleTypeManager:addBaleType(Utils.getFilename("objects/roundBales/roundbaleHay_w120_d180.i3d", self.modDirectory), "DRYGRASS_WINDROW", true, 1.2, 0, 0, 1.8))

    -- Load shared root file to make sure the bale exists as cloneable node.
    for _, baleType in ipairs(baleTypes) do
        baleType.sharedRoot = g_i3DManager:loadSharedI3DFile(baleType.filename, nil, false, false)
    end
    baleTypes = nil
end

---Unloads the bale types.
function StrawHarvest:unloadBaleTypes()
end

---Returns true when the given fillType list contains the target fillType.
function StrawHarvest.hasFillTypeInGroup(fillTypes, targetFillType)
    for _, fillType in pairs(fillTypes) do
        if fillType == targetFillType then
            return true
        end
    end
    return false
end

---Add straw and hay pellets to the food groups.
function StrawHarvest.inj_animalFoodManager_loadFoodGroups(foodManager, superFunc, xmlFile)
    if not superFunc(foodManager, xmlFile) then
        return false
    end

    for _, group in pairs(foodManager.foodGroups) do
        local list = group.content
        if list ~= nil then
            for _, foodGroup in ipairs(list) do
                if StrawHarvest.hasFillTypeInGroup(foodGroup.fillTypes, FillType.DRYGRASS_WINDROW) then
                    table.insert(foodGroup.fillTypes, FillType.HAYPELLETS)
                end

                if StrawHarvest.hasFillTypeInGroup(foodGroup.fillTypes, FillType.STRAW) then
                    table.insert(foodGroup.fillTypes, FillType.STRAWPELLETS)
                end
            end
        end
    end

    return true
end

function StrawHarvest.inj_mixerWagon_onLoad(vehicle, savegame)
    local spec = vehicle.spec_mixerWagon

    -- Add hay and straw pellets to the supportedFillTypes.
    for _, fillUnit in pairs(vehicle:getFillUnits()) do
        if fillUnit.supportedFillTypes[FillType.DRYGRASS_WINDROW] then
            fillUnit.supportedFillTypes[FillType.HAYPELLETS] = true
        end

        if fillUnit.supportedFillTypes[FillType.STRAW] then
            fillUnit.supportedFillTypes[FillType.STRAWPELLETS] = true
        end
    end

    -- Add hay and straw pellets to the mix entries that have straw and dry grass.
    for _, mixerWagonFillType in ipairs(spec.mixerWagonFillTypes) do
        if mixerWagonFillType.fillTypes[FillType.DRYGRASS_WINDROW] ~= nil then
            mixerWagonFillType.fillTypes[FillType.HAYPELLETS] = true
            spec.fillTypeToMixerWagonFillType[FillType.HAYPELLETS] = mixerWagonFillType
        end

        if mixerWagonFillType.fillTypes[FillType.STRAW] ~= nil then
            mixerWagonFillType.fillTypes[FillType.STRAWPELLETS] = true
            spec.fillTypeToMixerWagonFillType[FillType.STRAWPELLETS] = mixerWagonFillType
        end
    end
end

---Add straw to bedding.
function StrawHarvest.inj_husbandryModuleStraw_load(module, superFunc, xmlFile, configKey, rootNode, owner)
    if not superFunc(module, xmlFile, configKey, rootNode, owner) then
        return false
    end

    if module.unloadPlace ~= nil then
        --Avoid loadPlaces that are not loaded correctly.
        if module.unloadPlace.fillTypes ~= nil then
            module.unloadPlace.fillTypes[FillType.STRAWPELLETS] = true
            module.fillLevels[FillType.STRAWPELLETS] = 0.0
            module.providedFillTypes[FillType.STRAWPELLETS] = true
        end
    end

    return true
end

---Filltype info fix for the straw module.
function StrawHarvest.inj_husbandryModuleStraw_getFilltypeInfos(module, superFunc)
    local result = {}
    for fillTypeIndex, fillLevel in pairs(module.fillLevels) do
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        local freeCapacity = module:getFreeCapacity(fillTypeIndex)
        table.insert(result, { fillType = fillType, fillLevel = fillLevel, capacity = freeCapacity })
    end

    return result
end

---Compensate strawpellet/haypellet pallets on the animal husbandry modules.
function StrawHarvest.inj_husbandryModuleBase_addFillLevelFromTool(module, superFunc, farmId, deltaFillLevel, fillTypeIndex)
    local delta = superFunc(module, farmId, deltaFillLevel, fillTypeIndex)
    if fillTypeIndex == FillType.STRAWPELLETS or fillTypeIndex == FillType.HAYPELLETS then
        delta = delta * 0.25 -- compensate with the pelletizer.
    end
    return delta
end
