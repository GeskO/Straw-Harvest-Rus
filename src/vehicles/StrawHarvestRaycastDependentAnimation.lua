---
-- StrawHarvestRaycastDependentAnimation
--
-- Author: Stijn Wopereis (Wopster) and rafftnix (FS17)
-- Purpose: Animation will depend on the raycast.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestRaycastDependentAnimation
StrawHarvestRaycastDependentAnimation = {}
StrawHarvestRaycastDependentAnimation.MOD_NAME = g_currentModName

function StrawHarvestRaycastDependentAnimation.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AnimatedVehicle, specializations)
end

function StrawHarvestRaycastDependentAnimation.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "loadRaycastAnimationFromXML", StrawHarvestRaycastDependentAnimation.loadRaycastAnimationFromXML)
    SpecializationUtil.registerFunction(vehicleType, "raycastAnimationRaycastCallback", StrawHarvestRaycastDependentAnimation.raycastAnimationRaycastCallback)
end

function StrawHarvestRaycastDependentAnimation.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", StrawHarvestRaycastDependentAnimation)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", StrawHarvestRaycastDependentAnimation)
end

---Called on load.
function StrawHarvestRaycastDependentAnimation:onLoad(savegame)
    self.spec_strawHarvestRaycastDependentAnimation = self[("spec_%s.strawHarvestRaycastDependentAnimation"):format(StrawHarvestRaycastDependentAnimation.MOD_NAME)]
    local spec = self.spec_strawHarvestRaycastDependentAnimation

    spec.animations = {}
    spec.lastDist = 0

    local i = 0
    while true do
        local key = ("vehicle.raycastAnimations.animation(%d)"):format(i)
        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local animation = {}
        if self:loadRaycastAnimationFromXML(animation, self.xmlFile, key) then
            table.insert(spec.animations, animation)
        end

        i = i + 1
    end
end

---Called on update.
function StrawHarvestRaycastDependentAnimation:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if self:getIsActive() then
        local spec = self.spec_strawHarvestRaycastDependentAnimation
        for _, animation in ipairs(spec.animations) do
            local x, y, z = getWorldTranslation(animation.raycastNodeId)
            local dirX, dirY, dirZ = localDirectionToWorld(animation.raycastNodeId, animation.raycastDirX, animation.raycastDirY, animation.raycastDirZ)

            spec.lastDist = 0
            raycastAll(x, y, z, dirX, dirY, dirZ, "raycastAnimationRaycastCallback", animation.raycastDist, self, animation.collisionMask, false)

            if spec.lastDist ~= 0 then
                animation.lastDist = spec.lastDist
            else
                -- if we find nothing we set the animation to time=0
                animation.lastDist = animation.dist1
            end

            local dist = MathUtil.clamp(animation.lastDist - animation.dist0, 0, animation.dist1 - animation.dist0)
            local animTime = 1 - (dist / (animation.dist1 - animation.dist0))
            self:setAnimationTime(animation.name, animTime, true)
        end
    end
end

function StrawHarvestRaycastDependentAnimation:raycastAnimationRaycastCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex)
    local object = g_currentMission:getNodeObject(hitObjectId)
    if object ~= self then
        local spec = self.spec_strawHarvestRaycastDependentAnimation
        spec.lastDist = distance
    end
end

---Load raycast animation from the XML.
---@param animation table
---@param xmlFile number
---@param key string
function StrawHarvestRaycastDependentAnimation:loadRaycastAnimationFromXML(animation, xmlFile, key)
    animation.name = getXMLString(xmlFile, key .. "#name")
    animation.raycastNodeId = I3DUtil.indexToObject(self.components, getXMLString(xmlFile, key .. "#raycastNodeIndex"), self.i3dMappings)
    animation.raycastDirX, animation.raycastDirY, animation.raycastDirZ = StringUtil.getVectorFromString(getXMLString(xmlFile, key .. "#raycastDirection"))
    animation.collisionMask = Utils.getNoNil(getXMLInt(xmlFile, key .. "#collisionMask"), 0xffffffff)
    animation.dist0 = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#dist0"), 0)
    animation.dist1 = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#dist1"), 0.25)
    animation.raycastDist = animation.dist1
    animation.lastDist = animation.dist1

    return true
end
