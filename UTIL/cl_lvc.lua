--[[
---------------------------------------------------
LUXART VEHICLE CONTROL V3 (FOR FIVEM)
---------------------------------------------------
Coded by Lt.Caine
ELS Clicks by Faction
Additional Modification by TrevorBarns
---------------------------------------------------
FILE: cl_lvc.lua
PURPOSE: Core Functionality and User Input
---------------------------------------------------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
---------------------------------------------------
]]

--GLOBAL VARIABLES used in cl_ragemenu, UTILs, and plug-ins.
--	GENERAL VARIABLES
key_lock = false
playerped = nil
last_veh = nil
veh = nil
trailer = nil
player_is_emerg_driver = false
debug_mode = false

--	MAIN SIREN SETTINGS
tone_main_reset_standby 	= reset_to_standby_default
tone_airhorn_intrp 			= airhorn_interrupt_default
park_kill 					= park_kill_default

--LOCAL VARIABLES
local radio_wheel_active = false

local count_bcast_timer = 0
local delay_bcast_timer = 300

local count_sndclean_timer = 0
local delay_sndclean_timer = 400

local actv_ind_timer = false
local count_ind_timer = 0
local delay_ind_timer = 180

actv_lxsrnmute_temp = false
local srntone_temp = 0
local dsrn_mute = true
local lights_on = false
local new_tone = nil
local tone_mem_id = nil
local tone_mem_option = nil
local default_tone = nil
local default_tone_option = nil

state_indic = {}
state_lxsiren = {}
state_pwrcall = {}
state_airmanu = {}

actv_manu = nil
actv_horn = nil

local ind_state_o = 0
local ind_state_l = 1
local ind_state_r = 2
local ind_state_h = 3

local snd_lxsiren = {}
local snd_pwrcall = {}
local snd_airmanu = {}

--	Local fn forward declaration
local RegisterKeyMaps, MakeOrdinal

----------------THREADED FUNCTIONS----------------
-- Set check variable `player_is_emerg_driver` if player is driver of emergency vehicle.
-- Disables controls faster than previous thread.
CreateThread(function()
    if GetResourceState('lux_vehcontrol') ~= 'started' and GetResourceState('lux_vehcontrol') ~= 'starting' then
        if GetCurrentResourceName() == 'lvc' then
            if community_id ~= nil and community_id ~= '' then
                while true do
                    local playerped = PlayerPedId()
                    player_is_emerg_driver = false
                    if IsPedInAnyVehicle(playerped, false) then
                        local veh = GetVehiclePedIsUsing(playerped)
                        local trailer
                        _, trailer = GetVehicleTrailerVehicle(veh)
                        --IS DRIVER
                        if GetPedInVehicleSeat(veh, -1) == playerped then
                            --IS EMERGENCY VEHICLE
                            if GetVehicleClass(veh) == 18 then
                                player_is_emerg_driver = true
                                DisableControlAction(0, 80, true) -- INPUT_VEH_CIN_CAM
                                DisableControlAction(0, 86, true) -- INPUT_VEH_HORN
                                DisableControlAction(0, 172, true) -- INPUT_CELLPHONE_UP
                            end
                        end
                    end
                    Wait(100)  -- Increase wait time to reduce resource usage
                end
            else
                Wait(1000)
                HUD:ShowNotification(Lang:t('error.missing_community_id_frontend'), true)
                UTIL:Print(Lang:t('error.missing_community_id_console'), true)
            end
        else
            Wait(1000)
            HUD:ShowNotification(Lang:t('error.invalid_resource_name_frontend'), true)
            UTIL:Print(Lang:t('error.invalid_resource_name_console'), true)
        end
    else
        Wait(1000)
        HUD:ShowNotification(Lang:t('error.resource_conflict_frontend'), true)
        UTIL:Print(Lang:t('error.resource_conflict_console'), true)
    end
end)

-- On resource start/restart
CreateThread(function()
    debug_mode = GetResourceMetadata(GetCurrentResourceName(), 'debug_mode', 0) == 'true'
    TriggerEvent('chat:addSuggestion', Lang:t('command.lock_command'), Lang:t('command.lock_desc'))
    SetNuiFocus(false)
    
    UTIL:FixOversizeKeys(SIREN_ASSIGNMENTS)
    RegisterKeyMaps()
    STORAGE:SetBackupTable()
end)

-- Auxiliary Control Handling
-- Handles radio wheel controls and default horn on siren change playback. 
CreateThread(function()
    while true do
        if player_is_emerg_driver then
            -- RADIO WHEEL
            if IsControlPressed(0, 243) and AUDIO.radio_masterswitch then
                while IsControlPressed(0, 243) do
                    radio_wheel_active = true
                    SetControlNormal(0, 85, 1.0)
                    Wait(0)
                end
                Wait(100)
                radio_wheel_active = false
            else
                DisableControlAction(0, 85, true) -- INPUT_VEH_RADIO_WHEEL
                SetVehicleRadioEnabled(veh, false)
            end
        end
        Wait(100)  -- Increase wait time to reduce resource usage
    end
end)

------ON VEHICLE EXIT EVENT TRIGGER------
CreateThread(function()
    while true do
        if player_is_emerg_driver then
            while playerped ~= nil and veh ~= nil do
                if GetIsTaskActive(playerped, 2) and GetVehiclePedIsIn(playerped, true) then
                    TriggerEvent('lvc:onVehicleExit')
                    Wait(1000)
                end
                Wait(100)  -- Increase wait time to reduce resource usage
            end
        end
        Wait(1000)
    end
end)

------VEHICLE CHANGE DETECTION AND TRIGGER------
CreateThread(function()
    while true do
        if player_is_emerg_driver and veh ~= nil then
            if last_veh == nil or last_veh ~= veh then
                TriggerEvent('lvc:onVehicleChange')
            end
            last_veh = veh
        end
        Wait(1000)
    end
end)

------------REGISTERED VEHICLE EVENTS------------
--Kill siren on Exit
RegisterNetEvent('lvc:onVehicleExit')
AddEventHandler('lvc:onVehicleExit', function()
    if park_kill_masterswitch and park_kill then
        if not tone_main_reset_standby and state_lxsiren[veh] ~= 0 then
            UTIL:SetToneByID('MAIN_MEM', state_lxsiren[veh])
        end
        SetLxSirenStateForVeh(veh, 0)
        SetPowercallStateForVeh(veh, 0)
        SetAirManuStateForVeh(veh, 0)
        HUD:SetItemState('siren', false)
        HUD:SetItemState('horn', false)
        count_bcast_timer = delay_bcast_timer
    end
end)

RegisterNetEvent('lvc:onVehicleChange')
AddEventHandler('lvc:onVehicleChange', function()
    last_veh = veh
    UTIL:UpdateApprovedTones(veh)
    Wait(100) --waiting for JS event handler
    STORAGE:ResetSettings()
    UTIL:BuildToneOptions()
    STORAGE:LoadSettings()
    HUD:RefreshHudItemStates()
    SetVehRadioStation(veh, 'OFF')
    Wait(500)
    SetVehRadioStation(veh, 'OFF')
end)


--------------REGISTERED COMMANDS---------------
--Toggle Debug Mode
RegisterCommand(Lang:t('command.debug_command'), function()
    debug_mode = not debug_mode
    HUD:ShowNotification(Lang:t('info.debug_mode_frontend', {state = debug_mode}), true)
    UTIL:Print(Lang:t('info.debug_mode_console', {state = debug_mode}), true)
    if debug_mode then
        TriggerEvent('lvc:onVehicleChange')
    end
end)

--Toggle LUX lock command
RegisterCommand(Lang:t('command.lock_command'), function()
    if player_is_emerg_driver then
        key_lock = not key_lock
        AUDIO:Play('Key_Lock', AUDIO.lock_volume, true)
        HUD:SetItemState('lock', key_lock)
        --if HUD is visible do not show notification
        if not HUD:GetHudState() then
            HUD:ShowNotification(Lang:t(key_lock and 'info.locked' or 'info.unlocked'), true)
        end
    end
end)

RegisterKeyMapping(Lang:t('command.lock_command'), Lang:t('control.lock_desc'), 'keyboard', lockout_default_hotkey)


------------------------------------------------
-------------------FUNCTIONS--------------------
------------------------------------------------

RegisterKeyMaps = function()
    for i = 2, #SIRENS do
        local command = '_lvc_siren_' .. (i-1)
        local description = Lang:t('control.siren_control_desc', {ord_num = MakeOrdinal(i-1)})

        RegisterCommand(command, function(source, args)
            if veh and player_is_emerg_driver and IsVehicleSirenOn(veh) and not key_lock then
                local proposed_tone = UTIL:GetToneAtPos(i)
                local tone_option = UTIL:GetToneOption(proposed_tone)
                if i-1 < #UTIL:GetApprovedTonesTable() and tone_option and (tone_option == 1 or tone_option == 3) then
                    if state_lxsiren[veh] ~= proposed_tone or state_lxsiren[veh] == 0 then
                        HUD:SetItemState('siren', true)
                        AUDIO:Play('Upgrade', AUDIO.upgrade_volume)
                        SetLxSirenStateForVeh(veh, proposed_tone)
                    else
                        if state_pwrcall[veh] == 0 then
                            HUD:SetItemState('siren', false)
                        end
                        AUDIO:Play('Downgrade', AUDIO.downgrade_volume)
                        SetLxSirenStateForVeh(veh, 0)
                    end
                    count_bcast_timer = delay_bcast_timer
                else
                    HUD:ShowNotification(Lang:t('error.reg_keymap_nil_1', {i = i, proposed_tone = proposed_tone, profile_name = UTIL:GetVehicleProfileName()}), true)
                    HUD:ShowNotification(Lang:t('error.reg_keymap_nil_2'), true)
                end
            end
        end)

        if main_siren_set_register_keys_set_defaults then
            local key = (i < 11) and tostring(i-1) or (i == 11 and '0' or '')
            RegisterKeyMapping(command, description, 'keyboard', key)
        else
            RegisterKeyMapping(command, description, 'keyboard', '')
        end
    end
end

MakeOrdinal = function(number)
    local sufixes = { 'th', 'st', 'nd', 'rd', 'th', 'th', 'th', 'th', 'th', 'th' }
    local mod = number % 100
    if mod == 11 or mod == 12 or mod == 13 then
        return number .. 'th'
    else
        return number .. sufixes[number % 10 + 1]
    end
end

------------------------------------------------
local function CleanupSounds()
    if count_sndclean_timer > delay_sndclean_timer then
        count_sndclean_timer = 0
        local function stopAndCleanSound(state, snd)
            for k, v in pairs(state) do
                if v > 0 and (not DoesEntityExist(k) or IsEntityDead(k)) then
                    if snd[k] then
                        StopSound(snd[k])
                        ReleaseSoundId(snd[k])
                        snd[k] = nil
                        state[k] = nil
                    end
                end
            end
        end

        stopAndCleanSound(state_lxsiren, snd_lxsiren)
        stopAndCleanSound(state_pwrcall, snd_pwrcall)
        for k, v in pairs(state_airmanu) do
            if v and (not DoesEntityExist(k) or IsEntityDead(k) or IsVehicleSeatFree(k, -1)) then
                if snd_airmanu[k] then
                    StopSound(snd_airmanu[k])
                    ReleaseSoundId(snd_airmanu[k])
                    snd_airmanu[k] = nil
                    state_airmanu[k] = nil
                end
            end
        end
    else
        count_sndclean_timer = count_sndclean_timer + 1
    end
end

------------------------------------------------
function TogIndicStateForVeh(veh, newstate)
    if DoesEntityExist(veh) and not IsEntityDead(veh) then
        SetVehicleIndicatorLights(veh, 0, newstate == ind_state_r or newstate == ind_state_h)
        SetVehicleIndicatorLights(veh, 1, newstate == ind_state_l or newstate == ind_state_h)
        state_indic[veh] = newstate
    end
end

------------------------------------------------
function TogMuteDfltSrnForVeh(veh, toggle)
    if DoesEntityExist(veh) and not IsEntityDead(veh) then
        DisableVehicleImpactExplosionActivation(veh, toggle)
    end
end

------------------------------------------------
function SetLxSirenStateForVeh(veh, newstate)
    if DoesEntityExist(veh) and not IsEntityDead(veh) and newstate ~= state_lxsiren[veh] and newstate then
        if snd_lxsiren[veh] then
            StopSound(snd_lxsiren[veh])
            ReleaseSoundId(snd_lxsiren[veh])
            snd_lxsiren[veh] = nil
        end
        if newstate ~= 0 then
            snd_lxsiren[veh] = GetSoundId()
            PlaySoundFromEntity(snd_lxsiren[veh], SIRENS[newstate].String, veh, SIRENS[newstate].Ref, 0, 0)
            TogMuteDfltSrnForVeh(veh, true)
        end
        state_lxsiren[veh] = newstate
    end
end

------------------------------------------------
function SetPowercallStateForVeh(veh, newstate)
    if DoesEntityExist(veh) and not IsEntityDead(veh) and newstate ~= state_pwrcall[veh] and newstate then
        if snd_pwrcall[veh] then
            StopSound(snd_pwrcall[veh])
            ReleaseSoundId(snd_pwrcall[veh])
            snd_pwrcall[veh] = nil
        end
        if newstate ~= 0 then
            snd_pwrcall[veh] = GetSoundId()
            PlaySoundFromEntity(snd_pwrcall[veh], SIRENS[newstate].String, veh, SIRENS[newstate].Ref, 0, 0)
        end
        state_pwrcall[veh] = newstate
    end
end

------------------------------------------------
function SetAirManuStateForVeh(veh, newstate)
    if DoesEntityExist(veh) and not IsEntityDead(veh) and newstate ~= state_airmanu[veh] and newstate then
        if snd_airmanu[veh] then
            StopSound(snd_airmanu[veh])
            ReleaseSoundId(snd_airmanu[veh])
            snd_airmanu[veh] = nil
        end
        if newstate ~= 0 then
            snd_airmanu[veh] = GetSoundId()
            PlaySoundFromEntity(snd_airmanu[veh], SIRENS[newstate].String, veh, SIRENS[newstate].Ref, 0, 0)
        end
        state_airmanu[veh] = newstate
    end
end

------------------------------------------------
----------------EVENT HANDLERS------------------
------------------------------------------------

local function handleVehicleEvent(sender, stateHandler, newstate)
    local player_s = GetPlayerFromServerId(sender)
    local ped_s = GetPlayerPed(player_s)
    if DoesEntityExist(ped_s) and not IsEntityDead(ped_s) and ped_s ~= GetPlayerPed(-1) then
        if IsPedInAnyVehicle(ped_s, false) then
            local veh = GetVehiclePedIsUsing(ped_s)
            stateHandler(veh, newstate)
        end
    end
end

RegisterNetEvent('lvc:TogIndicState_c')
AddEventHandler('lvc:TogIndicState_c', function(sender, newstate)
    handleVehicleEvent(sender, TogIndicStateForVeh, newstate)
end)

RegisterNetEvent('lvc:TogDfltSrnMuted_c')
AddEventHandler('lvc:TogDfltSrnMuted_c', function(sender)
    handleVehicleEvent(sender, TogMuteDfltSrnForVeh, true)
end)

RegisterNetEvent('lvc:SetLxSirenState_c')
AddEventHandler('lvc:SetLxSirenState_c', function(sender, newstate)
    handleVehicleEvent(sender, SetLxSirenStateForVeh, newstate)
end)

RegisterNetEvent('lvc:SetPwrcallState_c')
AddEventHandler('lvc:SetPwrcallState_c', function(sender, newstate)
    handleVehicleEvent(sender, SetPowercallStateForVeh, newstate)
end)

RegisterNetEvent('lvc:SetAirManuState_c')
AddEventHandler('lvc:SetAirManuState_c', function(sender, newstate)
    handleVehicleEvent(sender, SetAirManuStateForVeh, newstate)
end)


---------------------------------------------------------------------
CreateThread(function()
    while true do
        CleanupSounds()
        DistantCopCarSirens(false)

        if GetPedInVehicleSeat(veh, -1) == playerped then
            if state_indic[veh] == nil then
                state_indic[veh] = ind_state_o
            end

            -- INDICATOR AUTO CONTROL
            if actv_ind_timer and (state_indic[veh] == ind_state_l or state_indic[veh] == ind_state_r) then
                if GetEntitySpeed(veh) < 6 then
                    count_ind_timer = 0
                else
                    if count_ind_timer > delay_ind_timer then
                        count_ind_timer = 0
                        actv_ind_timer = false
                        state_indic[veh] = ind_state_o
                        TogIndicStateForVeh(veh, state_indic[veh])
                        count_bcast_timer = delay_bcast_timer
                    else
                        count_ind_timer = count_ind_timer + 1
                    end
                end
            end

            -- EMERGENCY VEHICLE CHECK
            local isEmergencyVehicle = GetVehicleClass(veh) == 18
            if isEmergencyVehicle then
                lights_on = IsVehicleSirenOn(veh)

                if radio_masterswitch then
                    SetVehicleRadioEnabled(veh, true)
                end

                if not IsEntityDead(veh) then
                    TogMuteDfltSrnForVeh(veh, true)
                    state_lxsiren[veh] = state_lxsiren[veh] or 0
                    state_pwrcall[veh] = state_pwrcall[veh] or 0
                    state_airmanu[veh] = state_airmanu[veh] or 0

                    if not lights_on then
                        if state_lxsiren[veh] > 0 then
                            if not tone_main_reset_standby then
                                UTIL:SetToneByID('MAIN_MEM', state_lxsiren[veh])
                            end
                            SetLxSirenStateForVeh(veh, 0)
                            count_bcast_timer = delay_bcast_timer
                        end
                        if state_pwrcall[veh] > 0 then
                            SetPowercallStateForVeh(veh, 0)
                            count_bcast_timer = delay_bcast_timer
                        end
                    end

                    handleControls(veh, lights_on) -- Separate control handling for better readability
                end
            else
                TogMuteDfltSrnForVeh(veh, true)
            end

            if not isEmergencyVehicle and not (GetVehicleClass(veh) >= 14 and GetVehicleClass(veh) <= 21) then
                handleSignalControls(veh) -- Signal control handling
            end

            -- AUTO BROADCAST VEH STATES
            if count_bcast_timer > delay_bcast_timer then
                count_bcast_timer = 0
                TriggerServerEvent('lvc:TogDfltSrnMuted_s')
                TriggerServerEvent('lvc:SetLxSirenState_s', state_lxsiren[veh])
                TriggerServerEvent('lvc:SetPwrcallState_s', state_pwrcall[veh])
                TriggerServerEvent('lvc:SetAirManuState_s', state_airmanu[veh])
                TriggerServerEvent('lvc:TogIndicState_s', state_indic[veh])
            else
                count_bcast_timer = count_bcast_timer + 1
            end
        end
        Wait(0)
    end
end)

function handleControls(veh, lights_on)
    -- Control logic for handling sirens and lights
    if IsPauseMenuActive() or radio_wheel_active then return end

    if IsDisabledControlJustReleased(0, 85) then -- Toggle Default Siren
        toggleSiren(veh, lights_on)
    elseif IsDisabledControlJustReleased(0, 19) then -- Toggle LX Siren
        toggleLxSiren(veh, lights_on)
    elseif IsDisabledControlJustReleased(0, 172) and not IsMenuOpen() then -- Toggle Powercall
        togglePowercall(veh, lights_on)
    end

    if state_lxsiren[veh] > 0 then
        if IsDisabledControlJustReleased(0, 80) then -- Cycle LX Siren Tones
            AUDIO:Play('Upgrade', AUDIO.upgrade_volume)
            HUD:SetItemState('horn', false)
            SetLxSirenStateForVeh(veh, UTIL:GetNextSirenTone(state_lxsiren[veh], veh, true))
        elseif IsDisabledControlPressed(0, 80) then
            HUD:SetItemState('horn', true)
        end
    end

    handleHornAndManu(veh) -- Separate handling for horn and manu
end

function toggleSiren(veh, lights_on)
    if lights_on then
        AUDIO:Play('Off', AUDIO.off_volume)
        HUD:SetItemState('switch', false)
        SetVehicleSiren(veh, false)
    else
        AUDIO:Play('On', AUDIO.on_volume)
        HUD:SetItemState('switch', true)
        SetVehicleSiren(veh, true)
    end
    AUDIO:ResetActivityTimer()
    count_bcast_timer = delay_bcast_timer
end

function toggleLxSiren(veh, lights_on)
    if state_lxsiren[veh] == 0 and lights_on then
        AUDIO:Play('Upgrade', AUDIO.upgrade_volume)
        HUD:SetItemState('siren', true)
        local tone_mem_id = UTIL:GetToneID('MAIN_MEM')
        local tone_mem_option = UTIL:GetToneOption(tone_mem_id)
        
        if UTIL:IsApprovedTone(tone_mem_id) and tone_mem_option < 3 then
            SetLxSirenStateForVeh(veh, tone_mem_id)
        else
            new_tone = UTIL:GetNextSirenTone(tone_mem_id, veh, true)
            UTIL:SetToneByID('MAIN_MEM', new_tone)
            SetLxSirenStateForVeh(veh, new_tone)
        end
    else
        AUDIO:Play('Downgrade', AUDIO.downgrade_volume)
        HUD:SetItemState('siren', state_pwrcall[veh] == 0)
        SetLxSirenStateForVeh(veh, 0)
    end
    AUDIO:ResetActivityTimer()
    count_bcast_timer = delay_bcast_timer
end

function togglePowercall(veh, lights_on)
    if state_pwrcall[veh] == 0 and lights_on then
        AUDIO:Play('Upgrade', AUDIO.upgrade_volume)
        HUD:SetItemState('siren', true)
        SetPowercallStateForVeh(veh, UTIL:GetToneID('AUX'))
    else
        AUDIO:Play('Downgrade', AUDIO.downgrade_volume)
        HUD:SetItemState('siren', state_lxsiren[veh] == 0)
        SetPowercallStateForVeh(veh, 0)
    end
    AUDIO:ResetActivityTimer()
    count_bcast_timer = delay_bcast_timer
end

function handleHornAndManu(veh)
    if IsDisabledControlPressed(0, 86) then
        actv_horn = true
        AUDIO:ResetActivityTimer()
        HUD:SetItemState('horn', true)
    else
        if actv_horn then
            HUD:SetItemState('horn', false)
        end
        actv_horn = false
    end

    -- Handle manual and horn sound effects
    if AUDIO.airhorn_button_SFX then
        if IsDisabledControlJustPressed(0, 86) then
            AUDIO:Play('Press', AUDIO.upgrade_volume)
        elseif IsDisabledControlJustReleased(0, 86) then
            AUDIO:Play('Release', AUDIO.upgrade_volume)
        end
    end
end

function handleSignalControls(veh)
    if IsPauseMenuActive() then return end

    if IsDisabledControlJustReleased(0, left_signal_key) then
        toggleIndicator(veh, ind_state_l)
    elseif IsDisabledControlJustReleased(0, right_signal_key) then
        toggleIndicator(veh, ind_state_r)
    elseif IsControlPressed(0, hazard_key) then
        handleHazardControl(veh)
    end
end

function toggleIndicator(veh, state)
    local cstate = state_indic[veh]
    state_indic[veh] = (cstate == state) and ind_state_o or state
    actv_ind_timer = (cstate ~= state)
    TogIndicStateForVeh(veh, state_indic[veh])
    count_ind_timer = 0
    count_bcast_timer = delay_bcast_timer
end

function handleHazardControl(veh)
    if GetLastInputMethod(0) then
        Wait(hazard_hold_duration)
        if IsControlPressed(0, hazard_key) then
            local cstate = state_indic[veh]
            state_indic[veh] = (cstate == ind_state_h) and ind_state_o or ind_state_h
            AUDIO:Play((state_indic[veh] == ind_state_h) and 'Hazards_On' or 'Hazards_Off', AUDIO.hazards_volume, true)
            TogIndicStateForVeh(veh, state_indic[veh])
            actv_ind_timer = false
            count_ind_timer = 0
            count_bcast_timer = delay_bcast_timer
            while IsControlPressed(0, hazard_key) do
                Wait(0)
            end
        end
    end
end
