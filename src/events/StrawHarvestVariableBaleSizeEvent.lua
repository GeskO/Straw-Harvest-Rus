---
-- StrawHarvestVariableBaleSizeEvent
--
-- Author: Stijn Wopereis (Wopster)
-- Purpose: Event for changing the bale size.
--
-- Copyright (c) Creative Mesh UG, 2019

---@class StrawHarvestVariableBaleSizeEvent
StrawHarvestVariableBaleSizeEvent = {}

local StrawHarvestVariableBaleSizeEvent_mt = Class(StrawHarvestVariableBaleSizeEvent, Event)

InitEventClass(StrawHarvestVariableBaleSizeEvent, "StrawHarvestVariableBaleSizeEvent")

---@return StrawHarvestVariableBaleSizeEvent
function StrawHarvestVariableBaleSizeEvent:emptyNew()
    local self = Event:new(StrawHarvestVariableBaleSizeEvent_mt)
    return self
end

function StrawHarvestVariableBaleSizeEvent:new(object, index)
    local self = StrawHarvestVariableBaleSizeEvent:emptyNew()

    self.object = object
    self.index = index

    return self
end

function StrawHarvestVariableBaleSizeEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.index = streamReadUIntN(streamId, StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS) + 1
    self:run(connection)
end

function StrawHarvestVariableBaleSizeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteUIntN(streamId, self.index - 1, StrawHarvestVariableBaleSizeBaler.SIZES_SEND_NUM_BITS)
end

function StrawHarvestVariableBaleSizeEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.object)
    end

    self.object:setBaleSizeUnit(self.index, true)
end

function StrawHarvestVariableBaleSizeEvent.sendEvent(object, index, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(StrawHarvestVariableBaleSizeEvent:new(object, index), nil, nil, object)
        else
            g_client:getServerConnection():sendEvent(StrawHarvestVariableBaleSizeEvent:new(object, index))
        end
    end
end
