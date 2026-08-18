local reactedEntities = {}
local defaults = {
    pedServerMaxDistance = 80.0,
    vehicleServerMaxDistance = 80.0
}

local pedSettings = Config.PedSettings
local vehicleSettings = Config.VehicleSettings

local function distanceSquared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z

    return dx * dx + dy * dy + dz * dz
end

local function cleanupReactionCache(now)
    for key, cooldownEnds in pairs(reactedEntities) do
        if now >= cooldownEnds then
            reactedEntities[key] = nil
        end
    end
end

local function requestReaction(entityNetId, vehicleNetId, reactionType, cooldown, maxDistance, instant, allowSpread)
    local source = source

    if type(entityNetId) ~= 'number' then
        return
    end

    if vehicleNetId ~= nil and type(vehicleNetId) ~= 'number' then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(entityNetId)

    if entity == 0 then
        return
    end

    -- The target must be a real NPC ped. Without this a client could pass another
    -- PLAYER's ped net id and have that player's own client mutate their ped
    -- (combat attributes, flee tasks, ClearPedSecondaryTask).
    if GetEntityType(entity) ~= 1 or IsPedAPlayer(entity) then
        return
    end

    if reactionType == 'driver' then
        if type(vehicleNetId) ~= 'number' then
            return
        end

        local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

        if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= entity then
            return
        end
    end

    local playerPed = GetPlayerPed(source)

    if playerPed == 0 then
        return
    end

    if distanceSquared(GetEntityCoords(playerPed), GetEntityCoords(entity)) > (maxDistance * maxDistance) then
        return
    end

    local now = GetGameTimer()
    cleanupReactionCache(now)

    local cacheKey = ('%s:%s'):format(reactionType, entityNetId)

    if reactedEntities[cacheKey] and now < reactedEntities[cacheKey] then
        return
    end

    reactedEntities[cacheKey] = now + cooldown

    local owner = NetworkGetEntityOwner(entity)
    local target = owner and owner > 0 and owner or source

    TriggerClientEvent('tg-npcreactions:applyReaction', target, reactionType, entityNetId, vehicleNetId or 0, source, instant == true, allowSpread ~= false)
end

RegisterNetEvent('tg-npcreactions:requestPedReaction', function(pedNetId, instant, allowSpread)
    requestReaction(pedNetId, nil, 'ped', pedSettings.ReactionCooldown, defaults.pedServerMaxDistance, instant, allowSpread)
end)

RegisterNetEvent('tg-npcreactions:requestGangReaction', function(pedNetId)
    requestReaction(pedNetId, nil, 'gang', pedSettings.ReactionCooldown, defaults.pedServerMaxDistance, true, false)
end)

RegisterNetEvent('tg-npcreactions:requestDriverReaction', function(driverNetId, vehicleNetId)
    requestReaction(driverNetId, vehicleNetId, 'driver', vehicleSettings.ReactionCooldown, defaults.vehicleServerMaxDistance, true, false)
end)
