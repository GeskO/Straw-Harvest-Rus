---
-- StrawHarvestBaleCollectBaler
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Allows the baler to unload on the bale collect.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestBaleCollectBaler
StrawHarvestBaleCollectBaler = {}
StrawHarvestBaleCollectBaler.MOD_NAME = g_currentModName

function StrawHarvestBaleCollectBaler.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Baler, specializations)
end

function StrawHarvestBaleCollectBaler.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "hasAttachedBaleCollect", StrawHarvestBaleCollectBaler.hasAttachedBaleCollect)
    SpecializationUtil.registerFunction(vehicleType, "getAttachedBaleCollect", StrawHarvestBaleCollectBaler.getAttachedBaleCollect)
    SpecializationUtil.registerFunction(vehicleType, "isBaleCollectActive", StrawHarvestBaleCollectBaler.isBaleCollectActive)
end

function StrawHarvestBaleCollectBaler.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldAllowed", StrawHarvestBaleCollectBaler.getIsFoldAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", StrawHarvestBaleCollectBaler.getCanBeTurnedOn)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getTurnedOnNotAllowedWarning", StrawHarvestBaleCollectBaler.getTurnedOnNotAllowedWarning)
end

function StrawHarvestBaleCollectBaler.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestBaleCollectBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttachImplement", StrawHarvestBaleCollectBaler)
    SpecializationUtil.registerEventListener(vehicleType, "onPostDetachImplement", StrawHarvestBaleCollectBaler)
end

---Called on load.
function StrawHarvestBaleCollectBaler:onLoad(savegame)
    self.spec_strawHarvestBaleCollectBaler = self[("spec_%s.strawHarvestBaleCollectBaler"):format(StrawHarvestBaleCollectBaler.MOD_NAME)]
    local spec = self.spec_strawHarvestBaleCollectBaler

    spec.attachedBaleCollectIsActive = false
    spec.attachedBaleCollectJointIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.baleCollectBaler#attacherJointIndex"), 1)

    local configurationName = Utils.getNoNil(getXMLString(self.xmlFile, "vehicle.baleCollectBaler#configurationName"), "attacherJoint")
    local configurationIndex = Utils.getNoNil(getXMLInt(self.xmlFile, "vehicle.baleCollectBaler#configurationIndex"), 1)
    local configuration = self.configurations[configurationName]
    if configuration ~= nil then
        spec.attachedBaleCollectIsActive = configuration == configurationIndex
    end

    if spec.attachedBaleCollectIsActive then
        local firstBaleMarker = getXMLFloat(self.xmlFile, "vehicle.baleCollectBaler.baleAnimation#firstBaleMarker")

        if firstBaleMarker ~= nil then
            local baleAnimCurve = AnimCurve:new(linearInterpolatorN)
            local i = 0

            while true do
                local key = ("vehicle.baleCollectBaler.baleAnimation.key(%d)"):format(i)
                if not hasXMLProperty(self.xmlFile, key) then
                    break
                end

                local time = getXMLFloat(self.xmlFile, key .. "#time")
                local x, y, z = StringUtil.getVectorFromString(getXMLString(self.xmlFile, key .. "#pos"))
                local rx, ry, rz = unpack(StringUtil.getRadiansFromString(getXMLString(self.xmlFile, key .. "#rot"), 3))

                baleAnimCurve:addKeyframe({ x, y, z, rx, ry, rz, time = time })
                i = i + 1
            end

            if i > 0 then
                self.spec_baler.baleAnimCurve = baleAnimCurve
                self.spec_baler.firstBaleMarker = firstBaleMarker
            end
        end

        -- Don't check on fold limits
        if self.spec_foldable ~= nil then
            self.spec_foldable.turnOnFoldMaxLimit = 1
            self.spec_foldable.turnOnFoldMinLimit = 0
        end
    end

    spec.attachedBaleCollect = nil
end

function StrawHarvestBaleCollectBaler:hasAttachedBaleCollect()
    return self.spec_strawHarvestBaleCollectBaler.attachedBaleCollect ~= nil
end

function StrawHarvestBaleCollectBaler:getAttachedBaleCollect()
    return self.spec_strawHarvestBaleCollectBaler.attachedBaleCollect
end

function StrawHarvestBaleCollectBaler:isBaleCollectActive()
    return self.spec_strawHarvestBaleCollectBaler.attachedBaleCollectIsActive
end

function StrawHarvestBaleCollectBaler:onPostAttachImplement(attachable, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_strawHarvestBaleCollectBaler
    if jointDescIndex == spec.attachedBaleCollectJointIndex then
        spec.attachedBaleCollect = attachable
    end
end

function StrawHarvestBaleCollectBaler:onPostDetachImplement(implementIndex)
    local spec = self.spec_strawHarvestBaleCollectBaler
    local object
    if self.getObjectFromImplementIndex ~= nil then
        object = self:getObjectFromImplementIndex(implementIndex)
    end

    if object ~= nil then
        local attachedImplements = self:getAttachedImplements()
        if attachedImplements[implementIndex].jointDescIndex == spec.attachedBaleCollectJointIndex then
            spec.attachedBaleCollect = nil
        end
    end
end

----------------
-- Overwrites --
----------------

---Checks whether fold is allowed or not.
---Returns false when the bale collect is attached, false otherwise.
function StrawHarvestBaleCollectBaler:getIsFoldAllowed(superFunc, direction, onAiTurnOn)
    if self:isBaleCollectActive() then
        return false
    end

    return superFunc(self, direction, onAiTurnOn)
end

---Returns true when the bale collect is in working position when attached, false otherwise.
function StrawHarvestBaleCollectBaler:getCanBeTurnedOn(superFunc)
    if self:isBaleCollectActive() then
        if self:hasAttachedBaleCollect() then
            local baleCollect = self:getAttachedBaleCollect()
            if not baleCollect:getIsInWorkPosition() then
                return false
            end
        else
            return false
        end
    end

    return superFunc(self)
end

---Returns unfold bale collect warning text when the player try's to turn on the vehicle while the bale collect is folded.
function StrawHarvestBaleCollectBaler:getTurnedOnNotAllowedWarning(superFunc)
    if self:isBaleCollectActive() then
        if self:hasAttachedBaleCollect() then
            local baleCollect = self:getAttachedBaleCollect()
            if not baleCollect:getIsInWorkPosition() then
                return g_i18n:getText("warning_firstUnfoldTheTool"):format(baleCollect:getName())
            end
        else
            return g_i18n:getText("warning_needsABaleTrailer")
        end
    end

    return superFunc(self)
end
