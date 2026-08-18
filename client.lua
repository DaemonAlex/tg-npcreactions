local threatGroups = {}
local ignoredWeapons = {}
local gangGroups = {}
local animalGroups = {}
local reactedPeds = {}
local pendingFlee = {}
local spreadingPeds = {}
local nextCleanup = 0

local defaults = {
    threatWeaponGroups = {
        'GROUP_PISTOL',
        'GROUP_SMG',
        'GROUP_SHOTGUN',
        'GROUP_RIFLE',
        'GROUP_MG',
        'GROUP_SNIPER',
        'GROUP_HEAVY',
        'GROUP_MELEE'
    },

    ignoredWeapons = {
        'WEAPON_UNARMED',
        'WEAPON_BALL',
        'WEAPON_SNOWBALL',
        'WEAPON_FLARE',
        'WEAPON_PETROLCAN',
        'WEAPON_FIREEXTINGUISHER',
        'WEAPON_FLASHLIGHT',
        'WEAPON_HAZARDCAN'
    },

    gangRelationshipGroups = {
        'AMBIENT_GANG_BALLAS',
        'AMBIENT_GANG_CULT',
        'AMBIENT_GANG_FAMILY',
        'AMBIENT_GANG_HILLBILLY',
        'AMBIENT_GANG_LOST',
        'AMBIENT_GANG_MARABUNTE',
        'AMBIENT_GANG_MEXICAN',
        'AMBIENT_GANG_SALVA',
        'AMBIENT_GANG_WEICHENG',
        'GANG_1',
        'GANG_2',
        'GANG_9',
        'GANG_10'
    },

    animalRelationshipGroups = {
        'DOMESTIC_ANIMAL',
        'GUARD_DOG',
        'WILD_ANIMAL'
    },

    requirePedFacingPlayer = true,
    visionAngle = 115.0,
    requireLineOfSight = true,
    aimedPedAlwaysReacts = true,
    hesitationMin = 350,
    hesitationMax = 1200,
    fleeDistance = 100.0,
    fleeTime = 15000,
    panicSpreadDelay = 450,
    panicSpreadCooldown = 12000,
    vehicleRequireFacingPlayer = true,
    vehicleRequireLineOfSight = false,
    vehicleVisionAngle = 120.0,
    ignoreMissionVehicleDrivers = true,
    ignoreDeadOrDying = true,

    ignoredPedTypes = {
        [6] = true,
        [20] = true,
        [21] = true,
        [27] = true
    },

    speechParams = 'SPEECH_PARAMS_FORCE_SHOUTED_CRITICAL',
    noticeSpeech = {
        'GENERIC_SHOCKED_HIGH',
        'GENERIC_FRIGHTENED_MED'
    },
    fleeSpeech = {
        'GENERIC_FRIGHTENED_HIGH',
        'GENERIC_FRIGHTENED_MED',
        'GENERIC_SHOCKED_HIGH',
        'GENERIC_CURSE_HIGH'
    },
    gangSpeech = {
        'GENERIC_CURSE_HIGH',
        'GENERIC_INSULT_HIGH'
    }
}

local general = Config.GeneralSettings
local pedSettings = Config.PedSettings
local vehicleSettings = Config.VehicleSettings

local function loadHashSets()
    for _, groupName in ipairs(defaults.threatWeaponGroups) do
        threatGroups[GetHashKey(groupName)] = true
    end

    for _, weaponName in ipairs(defaults.ignoredWeapons) do
        ignoredWeapons[GetHashKey(weaponName)] = true
    end

    for _, groupName in ipairs(defaults.gangRelationshipGroups) do
        gangGroups[GetHashKey(groupName)] = true
    end

    for _, groupName in ipairs(defaults.animalRelationshipGroups) do
        animalGroups[GetHashKey(groupName)] = true
    end
end

local function distanceSquared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z

    return dx * dx + dy * dy + dz * dz
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end

    if value > maxValue then
        return maxValue
    end

    return value
end

local function requestEntityControl(entity)
    if entity == 0 or not DoesEntityExist(entity) then
        return
    end

    if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then
        NetworkRequestControlOfEntity(entity)
    end
end

local function getDriverVehicle(ped)
    if not vehicleSettings.Enabled or not IsPedInAnyVehicle(ped, false) then
        return 0
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return vehicle
    end

    return 0
end

local function isThreatWeapon(playerPed)
    -- Weapon must actually be drawn (in hand), not just selected-but-holstered.
    -- GetSelectedPedWeapon still returns the pistol when a holster script has it
    -- put away, so without this NPCs react to a weapon nobody can see — which
    -- contradicts the "visible threatening weapon" behaviour this script promises.
    if not IsPedArmed(playerPed, 7) then
        return false
    end

    local weapon = GetSelectedPedWeapon(playerPed)

    if ignoredWeapons[weapon] then
        return false
    end

    return threatGroups[GetWeapontypeGroup(weapon)] == true
end

local function isGangPed(ped)
    return pedSettings.GangRetaliation and gangGroups[GetPedRelationshipGroupHash(ped)] == true
end

local function isAnimalPed(ped)
    return animalGroups[GetPedRelationshipGroupHash(ped)] == true
end

local function isValidReactionPed(ped, playerPed)
    if ped == 0 or ped == playerPed then
        return false
    end

    if not DoesEntityExist(ped) or IsPedAPlayer(ped) or isAnimalPed(ped) or not IsPedHuman(ped) then
        return false
    end

    if defaults.ignoreDeadOrDying and (IsPedDeadOrDying(ped, true) or IsPedInjured(ped)) then
        return false
    end

    local driverVehicle = getDriverVehicle(ped)

    if general.IgnoreMissionPeds and IsEntityAMissionEntity(ped) then
        if driverVehicle == 0 or defaults.ignoreMissionVehicleDrivers then
            return false
        end
    end

    if IsPedInAnyVehicle(ped, false) and driverVehicle == 0 then
        return false
    end

    if general.IgnoreCops and defaults.ignoredPedTypes[GetPedType(ped)] then
        return false
    end

    if IsPedInCombat(ped, playerPed) then
        return false
    end

    return true
end

local function isVehicleFacingCoords(vehicle, coords, angle)
    local vehicleCoords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local dx = coords.x - vehicleCoords.x
    local dy = coords.y - vehicleCoords.y
    local length = math.sqrt(dx * dx + dy * dy)

    if length <= 0.001 then
        return true
    end

    local dot = (forward.x * (dx / length)) + (forward.y * (dy / length))
    local degrees = math.deg(math.acos(clamp(dot, -1.0, 1.0)))

    return degrees <= angle
end

local function isPlayerAimingAtPed(ped)
    local isAiming, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())

    return isAiming and entity == ped
end

local function canPedNoticePlayer(ped, playerPed, isAiming)
    if isAiming and defaults.aimedPedAlwaysReacts and isPlayerAimingAtPed(ped) then
        return true
    end

    if defaults.requirePedFacingPlayer and not IsPedFacingPed(ped, playerPed, defaults.visionAngle) then
        return false
    end

    if defaults.requireLineOfSight and not HasEntityClearLosToEntity(ped, playerPed, 17) then
        return false
    end

    return true
end

local function canDriverNoticePlayer(vehicle, playerPed, playerCoords, distSq)
    if distSq <= (vehicleSettings.ClosePanicRadius * vehicleSettings.ClosePanicRadius) then
        return true
    end

    if defaults.vehicleRequireFacingPlayer and not isVehicleFacingCoords(vehicle, playerCoords, defaults.vehicleVisionAngle) then
        return false
    end

    if defaults.vehicleRequireLineOfSight and not HasEntityClearLosToEntity(vehicle, playerPed, 17) then
        return false
    end

    return true
end

local function playPedSpeech(ped, poolName, chance)
    if not general.Speech.enabled or math.random(100) > chance then
        return
    end

    local speechPool = defaults.fleeSpeech

    if poolName == 'notice' then
        speechPool = defaults.noticeSpeech
    elseif poolName == 'gang' then
        speechPool = defaults.gangSpeech
    end

    if not speechPool or #speechPool == 0 then
        return
    end

    PlayPedAmbientSpeechNative(
        ped,
        speechPool[math.random(#speechPool)],
        defaults.speechParams
    )
end

local function makeDriverReact(ped, playerPed, vehicle)
    requestEntityControl(ped)
    requestEntityControl(vehicle)
    playPedSpeech(ped, 'flee', general.Speech.vehicleChance)

    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    TaskReactAndFleePed(ped, playerPed)
    SetPedKeepTask(ped, true)
end

local function makeGangReact(ped, playerPed)
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
        return
    end

    requestEntityControl(ped)
    playPedSpeech(ped, 'gang', general.Speech.chance)

    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedAlertness(ped, 3)
    TaskCombatPed(ped, playerPed, 0, 16)
    SetPedKeepTask(ped, true)
end

local function makePedReact(ped, playerPed, instant, allowSpread)
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
        return
    end

    if not instant and math.random(100) <= pedSettings.HesitationChance then
        playPedSpeech(ped, 'notice', general.Speech.chance)
        TaskLookAtEntity(ped, playerPed, defaults.hesitationMax + 300, 2048, 3)
        TaskTurnPedToFaceEntity(ped, playerPed, defaults.hesitationMax)
        pendingFlee[ped] = {
            fleeAt = GetGameTimer() + math.random(defaults.hesitationMin, defaults.hesitationMax),
            allowSpread = allowSpread ~= false
        }
        return
    end

    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedCanRagdoll(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    playPedSpeech(ped, 'flee', general.Speech.chance)
    ClearPedSecondaryTask(ped)
    TaskSmartFleePed(ped, playerPed, defaults.fleeDistance, defaults.fleeTime, false, false)
    SetPedKeepTask(ped, true)

    if allowSpread ~= false and pedSettings.PanicSpread.Enabled then
        spreadingPeds[ped] = {
            spreadAt = GetGameTimer() + defaults.panicSpreadDelay,
            playerPed = playerPed
        }
    end
end

local function requestPedReaction(ped, playerPed, now, instant, allowSpread, cooldown)
    reactedPeds[ped] = now + (cooldown or pedSettings.ReactionCooldown)

    if not pedSettings.ServerSync then
        makePedReact(ped, playerPed, instant, allowSpread)
        return
    end

    if not NetworkGetEntityIsNetworked(ped) then
        makePedReact(ped, playerPed, instant, allowSpread)
        return
    end

    TriggerServerEvent('tg-npcreactions:requestPedReaction', NetworkGetNetworkIdFromEntity(ped), instant == true, allowSpread ~= false)
end

local function requestDriverReaction(ped, playerPed, vehicle, now)
    reactedPeds[ped] = now + vehicleSettings.ReactionCooldown

    if not vehicleSettings.ServerSync then
        makeDriverReact(ped, playerPed, vehicle)
        return
    end

    if not NetworkGetEntityIsNetworked(ped) or not NetworkGetEntityIsNetworked(vehicle) then
        makeDriverReact(ped, playerPed, vehicle)
        return
    end

    local driverNetId = NetworkGetNetworkIdFromEntity(ped)
    local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)

    TriggerServerEvent('tg-npcreactions:requestDriverReaction', driverNetId, vehicleNetId)
end

local function requestGangReaction(ped, playerPed, now)
    reactedPeds[ped] = now + pedSettings.ReactionCooldown

    if not pedSettings.ServerSync then
        makeGangReact(ped, playerPed)
        return
    end

    if not NetworkGetEntityIsNetworked(ped) then
        makeGangReact(ped, playerPed)
        return
    end

    TriggerServerEvent('tg-npcreactions:requestGangReaction', NetworkGetNetworkIdFromEntity(ped))
end

local function makePedFlee(ped, playerPed)
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
        return
    end

    if isGangPed(ped) then
        makeGangReact(ped, playerPed)
        return
    end

    local driverVehicle = getDriverVehicle(ped)

    if driverVehicle ~= 0 then
        makeDriverReact(ped, playerPed, driverVehicle)
        return
    end

    makePedReact(ped, playerPed, true, true)
end

local function scheduleReaction(ped, playerPed, now, instant)
    if isGangPed(ped) then
        reactedPeds[ped] = now + pedSettings.ReactionCooldown
        requestGangReaction(ped, playerPed, now)
        return
    end

    local driverVehicle = getDriverVehicle(ped)
    local cooldown = driverVehicle ~= 0 and vehicleSettings.ReactionCooldown or pedSettings.ReactionCooldown
    reactedPeds[ped] = now + cooldown

    if driverVehicle ~= 0 then
        requestDriverReaction(ped, playerPed, driverVehicle, now)
        return
    end

    requestPedReaction(ped, playerPed, now, instant, true)
end

RegisterNetEvent('tg-npcreactions:applyReaction', function(reactionType, entityNetId, vehicleNetId, sourceServerId, instant, allowSpread)
    local entity = NetworkGetEntityFromNetworkId(entityNetId)
    local sourcePlayer = GetPlayerFromServerId(sourceServerId)

    if entity == 0 or sourcePlayer == -1 then
        return
    end

    -- Defense in depth: never apply reactions to a player's ped
    if IsPedAPlayer(entity) then
        return
    end

    local playerPed = GetPlayerPed(sourcePlayer)

    if playerPed == 0 or not DoesEntityExist(playerPed) then
        return
    end

    if reactionType == 'driver' then
        local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

        if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= entity then
            return
        end

        makeDriverReact(entity, playerPed, vehicle)
    elseif reactionType == 'gang' then
        makeGangReact(entity, playerPed)
    elseif reactionType == 'ped' then
        makePedReact(entity, playerPed, instant == true, allowSpread ~= false)
    end
end)

local function processPendingFlee(playerPed, now)
    for ped, state in pairs(pendingFlee) do
        local fleeAt = type(state) == 'table' and state.fleeAt or state
        local allowSpread = type(state) ~= 'table' or state.allowSpread ~= false

        if now >= fleeAt then
            pendingFlee[ped] = nil
            makePedReact(ped, playerPed, true, allowSpread)
        elseif not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
            pendingFlee[ped] = nil
        end
    end
end

local function cleanupReactionCache(now)
    if now < nextCleanup then
        return
    end

    nextCleanup = now + 5000

    for ped, cooldownEnds in pairs(reactedPeds) do
        if now >= cooldownEnds or not DoesEntityExist(ped) then
            reactedPeds[ped] = nil
        end
    end
end

local function processPanicSpread(playerPed, now)
    if not pedSettings.PanicSpread.Enabled then
        return
    end

    for sourcePed, state in pairs(spreadingPeds) do
        local spreadAt = type(state) == 'table' and state.spreadAt or state
        local sourcePlayerPed = type(state) == 'table' and state.playerPed or playerPed

        if now < spreadAt then
            goto continue
        end

        spreadingPeds[sourcePed] = nil

        if not DoesEntityExist(sourcePed)
            or not DoesEntityExist(sourcePlayerPed)
            or IsPedDeadOrDying(sourcePed, true)
        then
            goto continue
        end

        local sourceCoords = GetEntityCoords(sourcePed)
        local radiusSq = pedSettings.PanicSpread.Radius * pedSettings.PanicSpread.Radius
        local spreadCount = 0

        for _, nearbyPed in ipairs(GetGamePool('CPed')) do
            if spreadCount >= pedSettings.PanicSpread.MaxPeds then
                break
            end

            if nearbyPed ~= sourcePed
                and not pendingFlee[nearbyPed]
                and isValidReactionPed(nearbyPed, sourcePlayerPed)
                and getDriverVehicle(nearbyPed) == 0
            then
                local cooldownEnds = reactedPeds[nearbyPed]

                if not cooldownEnds or now >= cooldownEnds then
                    local nearbyCoords = GetEntityCoords(nearbyPed)

                    if distanceSquared(sourceCoords, nearbyCoords) <= radiusSq then
                        if isGangPed(nearbyPed) then
                            reactedPeds[nearbyPed] = now + pedSettings.ReactionCooldown
                            requestGangReaction(nearbyPed, sourcePlayerPed, now)
                        else
                            -- Spread reactions use the shorter panic-spread cooldown so a
                            -- crowd can ripple; pass it through instead of letting
                            -- requestPedReaction overwrite it with the full cooldown.
                            requestPedReaction(nearbyPed, sourcePlayerPed, now, false, false, defaults.panicSpreadCooldown)
                        end

                        spreadCount = spreadCount + 1
                    end
                end
            end
        end

        ::continue::
    end
end

local function scanNearbyPeds(playerPed, now, isAiming)
    local playerCoords = GetEntityCoords(playerPed)
    local radius = isAiming and pedSettings.AimingRadius or pedSettings.Radius
    local radiusSq = radius * radius
    local panicRadiusSq = pedSettings.ClosePanicRadius * pedSettings.ClosePanicRadius
    local vehicleRadius = isAiming and vehicleSettings.AimingRadius or vehicleSettings.Radius
    local vehicleRadiusSq = vehicleRadius * vehicleRadius
    local reactionsThisScan = 0

    for _, ped in ipairs(GetGamePool('CPed')) do
        if reactionsThisScan >= general.MaxPedsPerScan then
            break
        end

        if isValidReactionPed(ped, playerPed) and not pendingFlee[ped] then
            local cooldownEnds = reactedPeds[ped]

            if not cooldownEnds or now >= cooldownEnds then
                local driverVehicle = getDriverVehicle(ped)

                if driverVehicle ~= 0 then
                    local vehicleCoords = GetEntityCoords(driverVehicle)
                    local vehicleDistSq = distanceSquared(playerCoords, vehicleCoords)

                    if vehicleDistSq <= vehicleRadiusSq and canDriverNoticePlayer(driverVehicle, playerPed, playerCoords, vehicleDistSq) then
                        scheduleReaction(ped, playerPed, now, true)
                        reactionsThisScan = reactionsThisScan + 1
                    end
                else
                    local pedCoords = GetEntityCoords(ped)
                    local distSq = distanceSquared(playerCoords, pedCoords)

                    if distSq <= radiusSq and canPedNoticePlayer(ped, playerPed, isAiming) then
                        local shouldPanic = isAiming or distSq <= panicRadiusSq
                        scheduleReaction(ped, playerPed, now, shouldPanic)
                        reactionsThisScan = reactionsThisScan + 1
                    end
                end
            end
        end
    end
end

CreateThread(function()
    math.randomseed(GetGameTimer())
    loadHashSets()

    while true do
        local sleep = general.IdleScanInterval
        local playerPed = PlayerPedId()
        local now = GetGameTimer()

        processPendingFlee(playerPed, now)
        cleanupReactionCache(now)
        processPanicSpread(playerPed, now)

        if DoesEntityExist(playerPed)
            and not IsEntityDead(playerPed)
            and (general.ReactWhenPlayerInVehicle or not IsPedInAnyVehicle(playerPed, false))
            and isThreatWeapon(playerPed)
        then
            -- Include assisted/lock-on aim (controllers) so those players trigger
            -- the same faster-scan + forced-panic behaviour as free-aim.
            local isAiming = IsPlayerFreeAiming(PlayerId()) or IsPlayerTargettingAnything(PlayerId())
            sleep = isAiming and general.AimingScanInterval or general.ArmedScanInterval

            scanNearbyPeds(playerPed, now, isAiming)
        end

        Wait(sleep)
    end
end)
