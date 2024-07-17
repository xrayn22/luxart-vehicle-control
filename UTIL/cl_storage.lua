--[[
---------------------------------------------------
LUXART VEHICLE CONTROL V3 (FOR FIVEM)
---------------------------------------------------
Coded by Lt.Caine
ELS Clicks by Faction
Additional Modification by TrevorBarns
---------------------------------------------------
FILE: cl_storage.lua
PURPOSE: Handle save/load functions and version checking
---------------------------------------------------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
---------------------------------------------------
]]

STORAGE = {}
local save_prefix = 'lvc_' .. community_id .. '_'
local repo_version = nil
local custom_tone_names = false
local profiles = {}

-- Forward local function declaration
local IsNewerVersion

------------------------------------------------
-- Deletes all saved KVPs for that vehicle profile
RegisterCommand('lvcfactoryreset', function()
	local choice = HUD:FrontEndAlert(Lang:t('warning.warning'), Lang:t('warning.factory_reset'), Lang:t('warning.facory_reset_options'))
	if choice then
		STORAGE:FactoryReset()
	end
end)

function STORAGE:FactoryReset()
	STORAGE:DeleteKVPs(save_prefix)
	STORAGE:ResetSettings()
	UTIL:Print(Lang:t('info.factory_reset_success_console'), true)
	HUD:ShowNotification(Lang:t('info.factory_reset_success_frontend'), true)
end

-- Prints all KVP keys and values to console
RegisterCommand('lvcdumpkvp', function()
	UTIL:Print('^4LVC ^5STORAGE: ^7Dumping KVPs...')
	local handle = StartFindKvp(save_prefix)
	local key

	while (key = FindKvp(handle)) ~= nil do
		local value = GetResourceKvpString(key) or GetResourceKvpInt(key) or GetResourceKvpFloat(key)
		if value then
			UTIL:Print(string.format('^4LVC ^5STORAGE Found: ^7"%s" "%s", %s', key, value, type(value)))
		end
		Wait(0)
	end
	UTIL:Print('^4LVC ^5STORAGE: ^7Finished Dumping KVPs...')
end)

------------------------------------------------
-- Resource Start Initialization
CreateThread(function()
	TriggerServerEvent('lvc:GetRepoVersion_s')
	STORAGE:FindSavedProfiles()
end)

-- Deletes KVPs based on prefix
function STORAGE:DeleteKVPs(prefix)
	local handle = StartFindKvp(prefix)
	local key

	while (key = FindKvp(handle)) ~= nil do
		DeleteResourceKvp(key)
		UTIL:Print(string.format('^3LVC Info: Deleting Key \'%s\'', key), true)
		Wait(0)
	end
end

-- Gets current version used in RageUI
function STORAGE:GetCurrentVersion()
	return GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown'
end

-- Gets repo version used in RageUI
function STORAGE:GetRepoVersion()
	return repo_version
end

-- Checks if there is a newer version
function STORAGE:GetIsNewerVersion()
	return IsNewerVersion(repo_version, STORAGE:GetCurrentVersion())
end

-- Saves HUD settings
function STORAGE:SaveHUDSettings()
	local hud_save_data = {
		Show_HUD = HUD:GetHudState(),
		HUD_Scale = HUD:GetHudScale(),
		HUD_pos = HUD:GetHudPosition(),
		HUD_backlight_mode = HUD:GetHudBacklightMode(),
	}
	SetResourceKvp(save_prefix .. 'hud_data', json.encode(hud_save_data))
end

-- Saves all KVP values
function STORAGE:SaveSettings()
	UTIL:Print('^4LVC: ^5STORAGE: ^7Saving Settings...')
	SetResourceKvp(save_prefix .. 'save_version', STORAGE:GetCurrentVersion())

	-- Save HUD Settings
	STORAGE:SaveHUDSettings()
	
	-- Save Tone Names
	if custom_tone_names then
		local tone_names = {}
		for _, siren_pkg in pairs(SIRENS) do
			table.insert(tone_names, siren_pkg.Name)
		end
		SetResourceKvp(save_prefix .. 'tone_names', json.encode(tone_names))
		UTIL:Print('^4LVC ^5STORAGE: ^7saving tone_names...')
	end
	
	-- Profile Specific Settings
	local profile_name = UTIL:GetVehicleProfileName()
	if profile_name then
		profile_name = profile_name:gsub(' ', '_')
		local tone_options_encoded = json.encode(UTIL:GetToneOptionsTable())
		local profile_save_data = {
			PMANU = UTIL:GetToneID('PMANU'),
			SMANU = UTIL:GetToneID('SMANU'),
			AUX = UTIL:GetToneID('AUX'),
			airhorn_intrp = tone_airhorn_intrp,
			main_reset_standby = tone_main_reset_standby,
			park_kill = park_kill,
			tone_options = tone_options_encoded,
		}
		SetResourceKvp(save_prefix .. 'profile_' .. profile_name .. '!', json.encode(profile_save_data))
		UTIL:Print('^4LVC ^5STORAGE: ^7saving profile_' .. profile_name .. '!')
		
		-- Save Audio Settings
		local audio_save_data = {
			radio_masterswitch = AUDIO.radio_masterswitch,
			button_sfx_scheme = AUDIO.button_sfx_scheme,
			on_volume = AUDIO.on_volume,
			off_volume = AUDIO.off_volume,
			upgrade_volume = AUDIO.upgrade_volume,
			downgrade_volume = AUDIO.downgrade_volume,
			activity_reminder_volume = AUDIO.activity_reminder_volume,
			hazards_volume = AUDIO.hazards_volume,
			lock_volume = AUDIO.lock_volume,
			lock_reminder_volume = AUDIO.lock_reminder_volume,
			airhorn_button_SFX = AUDIO.airhorn_button_SFX,
			manu_button_SFX = AUDIO.manu_button_SFX,
			activity_reminder_index = AUDIO:GetActivityReminderIndex(),
		}
		SetResourceKvp(save_prefix .. 'profile_' .. profile_name .. '_audio_data', json.encode(audio_save_data))
		UTIL:Print('^4LVC ^5STORAGE: ^7saving profile_' .. profile_name .. '_audio_data')
	else
		HUD:ShowNotification('~b~LVC: ~r~SAVE ERROR~s~: profile_name is nil.', true)
	end
	UTIL:Print('^4LVC ^5STORAGE: ^7Finished Saving Settings...')
end

------------------------------------------------
-- Loads all KVP values
function STORAGE:LoadSettings(profile_name)
	UTIL:Print('^4LVC ^5STORAGE: ^7Loading Settings...')
	local comp_version = GetResourceMetadata(GetCurrentResourceName(), 'compatible', 0)
	local save_version = GetResourceKvpString(save_prefix .. 'save_version')
	local incompatible = IsNewerVersion(comp_version, save_version) == 'older'

	if incompatible then
		AddTextEntry('lvc_mismatch_version', string.format('~y~~h~Warning:~h~ ~s~Luxart Vehicle Control Save Version Mismatch.\n~b~Compatible Version: %s\n~o~Save Version: %s~s~\nVerify settings and resave to prevent issues.', comp_version, save_version))
		SetNotificationTextEntry('lvc_mismatch_version')
		DrawNotification(false, true)
	end
	
	local hud_save_data = GetResourceKvpString(save_prefix .. 'hud_data')
	if hud_save_data then
		hud_save_data = json.decode(hud_save_data)
		HUD:SetHudState(hud_save_data.Show_HUD)
		HUD:SetHudScale(hud_save_data.HUD_Scale)
		HUD:SetHudPosition(hud_save_data.HUD_pos)
		HUD:SetHudBacklightMode(hud_save_data.HUD_backlight_mode)
		UTIL:Print('^4LVC ^5STORAGE: ^7loaded HUD data.')		
	end
	
	if save_version then
		-- Load Tone Names
		if main_siren_settings_masterswitch then
			local tone_names = GetResourceKvpString(save_prefix .. 'tone_names')
			if tone_names then
				tone_names = json.decode(tone_names)
				for i, name in pairs(tone_names) do
					if SIRENS[i] then
						SIRENS[i].Name = name
					end
				end
				UTIL:Print('^4LVC ^5STORAGE: ^7loaded custom tone names.')
			end
		end
		
		-- Load Profile Specific Settings
		local profile_name = profile_name or UTIL:GetVehicleProfileName():gsub(' ', '_')
		if profile_name then
			local profile_save_data = GetResourceKvpString(save_prefix .. 'profile_' .. profile_name .. '!')
			if profile_save_data then
				profile_save_data = json.decode(profile_save_data)
				UTIL:SetToneByID('PMANU', profile_save_data.PMANU)
				UTIL:SetToneByID('SMANU', profile_save_data.SMANU)
				UTIL:SetToneByID('AUX', profile_save_data.AUX)
				tone_airhorn_intrp = profile_save_data.airhorn_intrp
				tone_main_reset_standby = profile_save_data.main_reset_standby
				park_kill = profile_save_data.park_kill
				UTIL:LoadToneOptionsTable(json.decode(profile_save_data.tone_options))
				UTIL:Print('^4LVC ^5STORAGE: ^7loaded profile_' .. profile_name .. '!')
				
				-- Load Audio Settings
				local audio_save_data = GetResourceKvpString(save_prefix .. 'profile_' .. profile_name .. '_audio_data')
				if audio_save_data then
					audio_save_data = json.decode(audio_save_data)
					AUDIO.radio_masterswitch = audio_save_data.radio_masterswitch
					AUDIO.button_sfx_scheme = audio_save_data.button_sfx_scheme
					AUDIO.on_volume = audio_save_data.on_volume
					AUDIO.off_volume = audio_save_data.off_volume
					AUDIO.upgrade_volume = audio_save_data.upgrade_volume
					AUDIO.downgrade_volume = audio_save_data.downgrade_volume
					AUDIO.activity_reminder_volume = audio_save_data.activity_reminder_volume
					AUDIO.hazards_volume = audio_save_data.hazards_volume
					AUDIO.lock_volume = audio_save_data.lock_volume
					AUDIO.lock_reminder_volume = audio_save_data.lock_reminder_volume
					AUDIO.airhorn_button_SFX = audio_save_data.airhorn_button_SFX
					AUDIO.manu_button_SFX = audio_save_data.manu_button_SFX
					AUDIO.activity_reminder_index = audio_save_data.activity_reminder_index
					UTIL:Print('^4LVC ^5STORAGE: ^7loaded profile_' .. profile_name .. '_audio_data')
				end
			end
		else
			UTIL:Print('^4LVC ^5STORAGE: ^7No profile name provided for loading settings.')
		end
	else
		UTIL:Print('^4LVC ^5STORAGE: ^7No saved settings found.')
	end
	UTIL:Print('^4LVC ^5STORAGE: ^7Finished Loading Settings...')
end

-- Check if a newer version is available
IsNewerVersion = function(repo_ver, current_ver)
	local repo_split = split(repo_ver, '.')
	local current_split = split(current_ver, '.')
	
	for i = 1, #repo_split do
		repo_split[i] = tonumber(repo_split[i])
	end
	for i = 1, #current_split do
		current_split[i] = tonumber(current_split[i])
	end

	for i = 1, math.max(#repo_split, #current_split) do
		local repo_part = repo_split[i] or 0
		local current_part = current_split[i] or 0
		if repo_part > current_part then
			return 'newer'
		elseif repo_part < current_part then
			return 'older'
		end
	end
	return 'equal'
end
