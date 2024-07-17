--[[ 
---------------------------------------------------
LUXART VEHICLE CONTROL V3 (FOR FIVEM)
---------------------------------------------------
Coded by Lt.Caine
ELS Clicks by Faction
Additional Modification by TrevorBarns
---------------------------------------------------
FILE: cl_utils.lua
PURPOSE: Utilities for siren assignments and tables
         and other common functions.
---------------------------------------------------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
---------------------------------------------------
]]

UTIL = {}

local approved_tones, tone_options, profile
local tone_ids = { MAIN_MEM = nil, PMANU = nil, SMANU = nil, AUX = nil, ARHRN = nil }

---------------------------------------------------------------------
--[[ Return sub-table for sirens or plugin settings tables, given veh and name of whatever setting. ]]
function UTIL:GetProfileFromTable(print_name, tbl, veh, ignore_missing_default)
	local veh_name = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
	local lead_and_trail_wildcard = veh_name:gsub('%d+', '#')
	local lead = veh_name:match('%d*%a+')
	local trail = veh_name:gsub(lead, ''):gsub('%d+', '#')
	local trail_only_wildcard = string.format('%s%s', lead, trail)

	local profile_table = tbl and (tbl[veh_name] or tbl[trail_only_wildcard] or tbl[lead_and_trail_wildcard] or tbl['DEFAULT'])
	profile = veh_name

	if profile_table then
		UTIL:Print(Lang:t('info.profile_found', {ver = STORAGE:GetCurrentVersion(), tbl = print_name, profile = profile, model = veh_name}))
		return profile_table, profile
	else
		if not ignore_missing_default and tbl['DEFAULT'] then
			UTIL:Print(Lang:t('info.profile_default_console', {ver = STORAGE:GetCurrentVersion(), tbl = print_name, model = veh_name}))
			HUD:ShowNotification(Lang:t('info.profile_default_frontend', {model = veh_name}))
			return tbl['DEFAULT'], 'DEFAULT'
		else
			UTIL:Print(Lang:t('warning.profile_missing', {ver = STORAGE:GetCurrentVersion(), tbl = print_name, model = veh_name}), true)
			return {}, false
		end
	end
end

---------------------------------------------------------------------
--[[ Shorten oversized <gameName> strings in SIREN_ASSIGNMENTS. ]]
function UTIL:FixOversizeKeys(TABLE)
	for i, _ in pairs(TABLE) do
		if #i > 11 then
			local shortened_gameName = i:sub(1, 11)
			TABLE[shortened_gameName] = TABLE[i]
			TABLE[i] = nil
		end
	end
end

---------------------------------------------------------------------
--[[ Sets profile name and approved_tones table from SIREN_ASSIGNMENTS for this vehicle. ]]
function UTIL:UpdateApprovedTones(veh)
	approved_tones, profile = UTIL:GetProfileFromTable('SIRENS', SIREN_ASSIGNMENTS, veh)

	if profile == false then
		UTIL:Print(Lang:t('error.profile_none_found_console', {game_name = GetDisplayNameFromVehicleModel(GetEntityModel(veh))}), true)
		HUD:ShowNotification(Lang:t('error.profile_none_found_frontend'), true)
		return
	end

	for tone_key, position in pairs({ MAIN_MEM = 2, PMANU = 2, SMANU = 3, AUX = 2, ARHRN = 1 }) do
		if not UTIL:IsApprovedTone(tone_key) then
			UTIL:SetToneByPos(tone_key, position)
		end
	end
end

--[[ Getter for approved_tones table, used in RageUI ]]
function UTIL:GetApprovedTonesTable()
	if not approved_tones then
		UTIL:UpdateApprovedTones(veh or 'DEFAULT')
	end
	return approved_tones
end

---------------------------------------------------------------------
--[[ Build a table that we store tone_options in. ]]
function UTIL:BuildToneOptions()
	tone_options = {}
	for _, id in pairs(approved_tones) do
		if SIRENS[id] then
			tone_options[id] = SIRENS[id].Option or 1
		end
	end
end

--[[ Getter and Setter for tone_options ]]
function UTIL:SetToneOption(tone_id, option)
	tone_options[tone_id] = option
end

function UTIL:GetToneOption(tone_id)
	return tone_options[tone_id]
end

function UTIL:GetToneOptionsTable()
	return tone_options
end

---------------------------------------------------------------------
--[[ Builds a table layout required by RageUI. ]]
function UTIL:GetApprovedTonesTableNameAndID()
	local temp_array = {}
	for _, tone_id in pairs(approved_tones) do
		if tone_id ~= approved_tones[1] then
			table.insert(temp_array, { Name = SIRENS[tone_id].Name, Value = tone_id })
		end
	end
	return temp_array
end

---------------------------------------------------------------------
--[[ Getter for tone id by passing string abbreviation. ]]
function UTIL:GetToneID(tone_string)
	return tone_ids[tone_string]
end

--[[ Setter for ToneID by passing string abbreviation and position. ]]
function UTIL:SetToneByPos(tone_string, pos)
	if profile and approved_tones[pos] then
		tone_ids[tone_string] = approved_tones[pos]
	else
		HUD:ShowNotification(Lang:t('warning.too_few_tone_frontend', {code = 403}), false)
		UTIL:Print(Lang:t('warning.too_few_tone_console', {ver = STORAGE:GetCurrentVersion(), code = 403, tone_string = tone_string, pos = pos}), true)
	end
end

--[[ Getter for position of passed tone string. ]]
function UTIL:GetTonePos(tone_string)
	local current_id = UTIL:GetToneID(tone_string)
	for i, tone_id in pairs(approved_tones) do
		if tone_id == current_id then
			return i
		end
	end
	return -1
end

--[[ Getter for Tone ID at index/pos in approved_tones ]]
function UTIL:GetToneAtPos(pos)
	return approved_tones[pos] or nil
end

--[[ Setter for ToneID by passing string abbreviation and specific ID. ]]
function UTIL:SetToneByID(tone_string, tone_id)
	if UTIL:IsApprovedTone(tone_id) then
		tone_ids[tone_string] = tone_id
	else
		HUD:ShowNotification(Lang:t('warning.tone_id_nil_frontend', {ver = STORAGE:GetCurrentVersion()}), false)
		UTIL:Print(Lang:t('warning.tone_id_nil_console', {ver = STORAGE:GetCurrentVersion(), tone_string = tone_string, tone_id = tone_id}), true)
	end
end

---------------------------------------------------------------------
--[[ Gets the next tone based on vehicle profile and current tone. ]]
function UTIL:GetNextSirenTone(current_tone, veh, main_tone, last_pos)
	local temp_pos = last_pos or (table.indexOf(approved_tones, current_tone) or 1)

	temp_pos = (temp_pos < #approved_tones) and (temp_pos + 1) or 2
	local result = approved_tones[temp_pos]

	if main_tone and tone_options[result] > 2 then
		return UTIL:GetNextSirenTone(result, veh, main_tone, temp_pos)
	end

	return result
end

---------------------------------------------------------------------
--[[ Get count of approved tones. ]]
function UTIL:GetToneCount()
	return #approved_tones
end

---------------------------------------------------------------------
--[[ Ensure not all sirens are disabled/button only. ]]
function UTIL:IsOkayToDisable()
	local count = 0
	for _, option in pairs(tone_options) do
		if option < 3 then count = count + 1 end
	end
	return count > 1
end

------------------------------------------------
--[[ Handle changing of tone_table custom names. ]]
function UTIL:ChangeToneString(tone_id, new_name)
	STORAGE:SetCustomToneStrings(true)
	SIRENS[tone_id].Name = new_name
end

------------------------------------------------
--[[ Verify tone is allowed before playing. ]]
function UTIL:IsApprovedTone(tone)
	return table.indexOf(approved_tones, tone) ~= nil
end

---------------------------------------------------------------------
--[[ Returns String <gameName> used for saving, loading, and debugging. ]]
function UTIL:GetVehicleProfileName()
	return profile
end

---------------------------------------------------------------------
--[[ Prints to FiveM console with debug flag control. ]]
function UTIL:Print(msg, override)
	if debug_mode or override then
		print(msg)
	end
end

---------------------------------------------------------------------
--[[ Finds index of element in table. ]]
function UTIL:IndexOf(tbl, tgt)
	for i, v in pairs(tbl) do
		if v == tgt then return i end
	end
	return nil
end

---------------------------------------------------------------------
--[[ Toggles vehicle extras based on config structure. ]]
function UTIL:TogVehicleExtras(veh, extra_id, state, repair)
	if type(extra_id) == 'table' then
		if extra_id.toggle then
			for _, id in pairs(extra_id) do
				if id.toggle then
					SetVehicleExtra(veh, id.id, state)
				end
			end
		end
	else
		SetVehicleExtra(veh, extra_id, state)
	end

	if repair then
		UTIL:RepairVehicle(veh)
	end
end

---------------------------------------------------------------------
--[[ Function to repair vehicle. ]]
function UTIL:RepairVehicle(veh)
	SetVehicleDirtLevel(veh, 0)
	SetVehicleEngineHealth(veh, 1000)
	SetVehicleBodyHealth(veh, 1000)
end

return UTIL
