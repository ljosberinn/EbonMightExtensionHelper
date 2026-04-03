local addonName, Private = ...

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	if select(3, UnitClass("player")) ~= Constants.UICharacterClasses.Evoker then
		return
	end

	-- enum
	do
		Private.Enum = {}

		---@enum SoundChannel
		Private.Enum.SoundChannel = {
			Master = MASTER_VOLUME,
			Music = MUSIC_VOLUME,
			SFX = FX_VOLUME,
			Ambience = AMBIENCE_VOLUME,
			Dialog = DIALOG_VOLUME,
		}
	end

	-- i18n
	do
		Private.L = {}
		local L = Private.L
		L.Settings = {}

		L.Settings.ClickToOpenSettingsLabel = "Click to open settings"
		L.Settings.SoundChannelLabel = "Sound Channel"
		L.Settings.SoundChannelTooltip = nil
		L.Settings.SoundChannelLabels = {
			[Private.Enum.SoundChannel.Master] = MASTER_VOLUME,
			[Private.Enum.SoundChannel.Music] = MUSIC_VOLUME,
			[Private.Enum.SoundChannel.SFX] = FX_VOLUME,
			[Private.Enum.SoundChannel.Ambience] = AMBIENCE_VOLUME,
			[Private.Enum.SoundChannel.Dialog] = DIALOG_VOLUME,
		}

		L.Settings.EnabledLabel = "Enabled"
		L.Settings.EnabledTooltip = nil
		L.Settings.DisabledLabel = "Disabled"

		L.Settings.SoundLabel = "Sound"
		L.Settings.SoundCategoryCustom = "Custom"
		L.Settings.SoundTooltip = "Click to change, but also click to preview sound. Warning: Master channel volume!"

		L.Settings.AddonCompartmentTooltipLine1 =
			string.format("%s is %s", WrapTextInColorCode("Ebon Might Extension Helper", "ffeda55f"), "%s")
	end

	-- Utils
	do
		Private.Utils = {}

		local handle = nil
		local channels = tInvert(Private.Enum.SoundChannel)

		function Private.Utils.AttemptToPlaySound(sound, channel)
			if handle ~= nil then
				StopSound(handle)
				handle = nil
			end

			local channelToUse = channels[channel]
			local isFile = Private.Settings.SoundIsFile(sound)

			if not isFile and type(sound) == "number" then
				handle = select(3, pcall(PlaySound, sound, channelToUse, false))
			else
				handle = select(3, pcall(PlaySoundFile, sound, channelToUse))
			end
		end
	end

	-- Settings
	do
		local LibSharedMedia = LibStub("LibSharedMedia-3.0")

		do
			local customSounds = {
				{ name = "EbonMightExtensionHelper Punch", path = "PUNCH.ogg" },
			}

			for i, sound in pairs(customSounds) do
				LibSharedMedia:Register(
					"sound",
					sound.name,
					string.format("Interface\\AddOns\\EbonMightExtensionHelper\\Media\\Sounds\\%s", sound.path)
				)
			end
		end

		Private.Settings = {}

		Private.Settings.Keys = {
			Enabled = "ENABLED",
			Sound = "SOUND",
			SoundChannel = "SOUND_CHANNEL",
		}

		function Private.Settings.GetDefaultSettings()
			return {
				Enabled = true,
				Sound = "Interface\\AddOns\\EbonMightExtensionHelper\\Media\\Sounds\\PUNCH.ogg",
				SoundChannel = Private.Enum.SoundChannel.Master,
			}
		end

		---@class CustomSound
		---@field soundKitID number|string
		---@field text string

		---@class SoundInfo
		---@field soundCategoryKeyToLabel table<string, string>
		---@field data table<string, CustomSound[]>

		-- this follows the structure of `CooldownViewerSoundData` in `Blizzard_CooldownViewer/CooldownViewerSoundAlertData.lua` for ease of function reuse
		function Private.Settings.GetCustomSoundGroups(groupSizeThreshold)
			---@type SoundInfo
			local soundInfo = {
				data = {},
				soundCategoryKeyToLabel = {},
			}

			local source = LibSharedMedia:HashTable(LibSharedMedia.MediaType.SOUND)
			local groupedSounds = {}

			---@param str string
			---@param prefix string
			---@return boolean
			local function StartsWith(str, prefix)
				return str:find(prefix, 1, true) == 1
			end

			for label, path in pairs(source) do
				if path ~= 1 then
					---@type string
					local key = Private.L.Settings.SoundCategoryCustom

					if type(path) == "string" and StartsWith(path, "Interface") then
						-- path is case insensitive, normalize it
						path = path:gsub([[\Addons\]], "\\AddOns\\")

						---@type string|nil
						local maybeAddonName = path:match([[AddOns[\/]([^\/]+)]])

						if maybeAddonName then
							key = maybeAddonName
						end
					elseif StartsWith(label, "BigWigs") then -- BW ships a couple game sound id references that are still prefixed with "BigWigs: (...)"
						key = "BigWigs"
					end

					-- some sounds are labelled e.g. `Plater Steel` and get patched to only render `Steel`
					if string.find(label, key) ~= nil then
						label = label:gsub(key .. ": ", ""):gsub(key, ""):trim()
					end

					if groupedSounds[key] == nil then
						groupedSounds[key] = {}
					end

					table.insert(groupedSounds[key], {
						name = label,
						path = path,
					})
				end
			end

			for groupName, sounds in pairs(groupedSounds) do
				local needsSplitting = groupSizeThreshold ~= nil and #sounds > groupSizeThreshold or false
				local groupCount = 0
				local isCustomGroup = groupName == Private.L.Settings.SoundCategoryCustom
				local tableKey = groupName

				-- edit mode dropdowns need splitting as there's a max amount of elements to render within a dropdown
				if needsSplitting then
					groupCount = groupCount + 1
					tableKey = isCustomGroup
							and string.format("%s %d", Private.L.Settings.SoundCategoryCustom, groupCount)
						or string.format("%s %d", groupName, groupCount)
				end

				if soundInfo.data[tableKey] == nil then
					soundInfo.data[tableKey] = {}
					soundInfo.soundCategoryKeyToLabel[tableKey] = tableKey
				end

				local targetTable = soundInfo.data[tableKey]

				for _, sound in pairs(sounds) do
					if groupSizeThreshold ~= nil then
						if #targetTable >= groupSizeThreshold then
							groupCount = groupCount + 1

							tableKey = isCustomGroup
									and string.format("%s %d", Private.L.Settings.SoundCategoryCustom, groupCount)
								or string.format("%s %d", groupName, groupCount)

							if soundInfo.data[tableKey] == nil then
								soundInfo.data[tableKey] = {}
								soundInfo.soundCategoryKeyToLabel[tableKey] = tableKey
							end

							targetTable = soundInfo.data[tableKey]
						end
					end

					table.insert(targetTable, {
						soundKitID = sound.path,
						text = sound.name,
					})
				end
			end

			return soundInfo
		end

		do
			---@type table<string|number, true>
			local soundIsFileCache = {}

			function Private.Settings.SoundIsFile(sound)
				return soundIsFileCache[sound] or false
			end

			local soundInfo = Private.Settings.GetCustomSoundGroups()

			for group, sounds in pairs(soundInfo.data) do
				for _, sound in pairs(sounds) do
					soundIsFileCache[sound.soundKitID] = true
				end
			end

			LibSharedMedia.RegisterCallback(Private, "LibSharedMedia_Registered", function(_, mediaType, key)
				if mediaType ~= "sound" then
					return
				end

				local path = LibSharedMedia:Fetch("sound", key)

				if path == nil or path == 1 then
					return
				end

				soundIsFileCache[path] = true
			end)
		end

		local L = Private.L
		local settingsName = C_AddOns.GetAddOnMetadata(addonName, "Title")
		local category, layout = Settings.RegisterVerticalLayoutCategory(settingsName)

		local function CreateSetting(key, defaults)
			if key == Private.Settings.Keys.Enabled then
				local function GetValue()
					return EbonMightExtensionHelperSaved.Settings.Enabled
				end

				local function SetValue(value)
					EbonMightExtensionHelperSaved.Settings.Enabled = not EbonMightExtensionHelperSaved.Settings.Enabled
				end

				local setting = Settings.RegisterProxySetting(
					category,
					key,
					Settings.VarType.Boolean,
					L.Settings.EnabledLabel,
					Settings.Default.True,
					GetValue,
					SetValue
				)

				local initializer = Settings.CreateCheckbox(category, setting, L.Settings.EnabledTooltip)

				return {
					initializer = initializer,
					hideSteppers = false,
					IsSectionEnabled = nil,
				}
			end

			if key == Private.Settings.Keys.SoundChannel then
				local function GetValue()
					return EbonMightExtensionHelperSaved.Settings.SoundChannel
				end

				local function SetValue(value)
					EbonMightExtensionHelperSaved.Settings.SoundChannel = value
				end

				local function GetOptions()
					local container = Settings.CreateControlTextContainer()

					for label, value in pairs(Private.Enum.SoundChannel) do
						local translated = L.Settings.SoundChannelLabels[value]
						container:Add(value, translated)
					end

					return container:GetData()
				end

				local setting = Settings.RegisterProxySetting(
					category,
					key,
					Settings.VarType.String,
					L.Settings.SoundChannelLabel,
					defaults.SoundChannel,
					GetValue,
					SetValue
				)

				local initializer =
					Settings.CreateDropdown(category, setting, GetOptions, L.Settings.SoundChannelTooltip)

				return {
					initializer = initializer,
					hideSteppers = false,
				}
			end

			if key == Private.Settings.Keys.Sound then
				local function GetValue()
					return tostring(EbonMightExtensionHelperSaved.Settings.Sound)
				end

				local function IsNumeric(str)
					return tonumber(str) ~= nil
				end

				local function SetValue(value)
					local sound = IsNumeric(value) and tonumber(value) or value

					Private.Utils.AttemptToPlaySound(sound, Private.Enum.SoundChannel.Master)

					if EbonMightExtensionHelperSaved.Settings.Sound ~= sound then
						EbonMightExtensionHelperSaved.Settings.Sound = sound
					end
				end

				---@param soundCategoryKeyToText table<string, string>
				---@param currentTable table<string, CustomSound[]> | CustomSound[]
				---@param categoryName string?
				local function RecursiveAddSounds(container, soundCategoryKeyToText, currentTable, categoryName)
					for tableKey, value in pairs(currentTable) do
						if value.soundKitID and value.text then
							container:Add(
								tostring(value.soundKitID),
								string.format("%s - %s", categoryName, value.text)
							)
						elseif type(value) == "table" and soundCategoryKeyToText[tableKey] then
							RecursiveAddSounds(
								container,
								soundCategoryKeyToText,
								value,
								soundCategoryKeyToText[tableKey]
							)
						end
					end
				end

				local function AddCustomSounds(container)
					local soundInfo = Private.Settings.GetCustomSoundGroups()

					RecursiveAddSounds(container, soundInfo.soundCategoryKeyToLabel, soundInfo.data)
				end

				local function GetOptions(owner, rootDescription)
					local container = Settings.CreateControlTextContainer()

					AddCustomSounds(container)

					return container:GetData()
				end

				local setting = Settings.RegisterProxySetting(
					category,
					key,
					Settings.VarType.String,
					L.Settings.SoundLabel,
					tostring(defaults.Sound),
					GetValue,
					SetValue
				)

				-- a bit icky but there's no native way of making the dropdown scrollable without introducing a template and this is easier
				-- ty to .numy
				hooksecurefunc(
					Settings,
					"InitDropdown",
					function(dropdown, settingBeingCreated, elementInserter, initTooltip)
						if setting ~= settingBeingCreated then
							return
						end

						dropdown:SetupMenu(function(_dropdown, rootDescription)
							local extent = 20
							local maxCharacters = 20
							local maxScrollExtent = extent * maxCharacters
							rootDescription:SetScrollMode(maxScrollExtent)

							elementInserter(settingBeingCreated, rootDescription)
						end)
					end
				)

				local initializer = Settings.CreateDropdown(category, setting, GetOptions, L.Settings.SoundTooltip)

				return {
					initializer = initializer,
					hideSteppers = false,
				}
			end

			error(string.format("CreateSetting not implemented for key '%s'", key))
		end

		do
			local generalCategoryEnabledInitializer

			local function IsSectionEnabled()
				return EbonMightExtensionHelperSaved.Settings.Enabled
			end

			local settingsOrder = {
				Private.Settings.Keys.Enabled,
				Private.Settings.Keys.Sound,
				Private.Settings.Keys.SoundChannel,
			}
			local defaults = Private.Settings.GetDefaultSettings()

			for i, key in ipairs(settingsOrder) do
				local config = CreateSetting(key, defaults)

				if key == Private.Settings.Keys.Enabled then
					generalCategoryEnabledInitializer = config.initializer
				else
					if config.hideSteppers then
						config.initializer.hideSteppers = true
					end

					config.initializer:SetParentInitializer(generalCategoryEnabledInitializer, IsSectionEnabled)
				end
			end
		end

		Settings.RegisterAddOnCategory(category)

		local function OpenSettings()
			Settings.OpenToCategory(category.ID)
		end

		AddonCompartmentFrame:RegisterAddon({
			text = settingsName,
			icon = C_AddOns.GetAddOnMetadata(addonName, "IconTexture"),
			registerForAnyClick = true,
			notCheckable = true,
			func = OpenSettings,
			funcOnEnter = function(button)
				MenuUtil.ShowTooltip(button, function(tooltip)
					tooltip:SetText(settingsName, 1, 1, 1)
					tooltip:AddLine(L.Settings.ClickToOpenSettingsLabel)
					tooltip:AddLine(" ")

					local enabledColor = "FF00FF00"
					local disabledColor = "00FF0000"

					tooltip:AddLine(L.Settings.AddonCompartmentTooltipLine1:format(WrapTextInColorCode(
						string.lower(
							---@diagnostic disable-next-line: param-type-mismatch
							EbonMightExtensionHelperSaved.Settings.Enabled and L.Settings.EnabledLabel
								or L.Settings.DisabledLabel
						),
						EbonMightExtensionHelperSaved.Settings.Enabled and enabledColor or disabledColor
					)))
				end)
			end,
			funcOnLeave = function(button)
				MenuUtil.HideTooltip(button)
			end,
		})

		local uppercased = string.upper(settingsName)
		local lowercased = string.lower(settingsName)

		SlashCmdList[uppercased] = function(message)
			local command, rest = message:match("^(%S+)%s*(.*)$")

			if command == "options" or command == "settings" then
				OpenSettings()
			end
		end

		_G[string.format("SLASH_%s1", uppercased)] = string.format("/%s", lowercased)
	end

	EbonMightExtensionHelperSaved = EbonMightExtensionHelperSaved or {}
	EbonMightExtensionHelperSaved.Settings = EbonMightExtensionHelperSaved.Settings or {}

	for key, value in pairs(Private.Settings.GetDefaultSettings()) do
		if EbonMightExtensionHelperSaved.Settings[key] == nil then
			EbonMightExtensionHelperSaved.Settings[key] = value
		end
	end

	local frame = CreateFrame("Frame")
	frame.expirationTime = 0
	frame.lastEbonMightCast = 0
	frame.customEventName = "EbonMightExtensionHelperEvent"
	frame:RegisterEvent("LOADING_SCREEN_DISABLED")
	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

	function frame:RegisterSpecSpecificEvents()
		frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
		frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		frame:RegisterUnitEvent("UNIT_AURA", "player")
	end

	function frame:UnregisterSpecSpecificEvents()
		frame:UnregisterEvent("UNIT_SPELLCAST_START")
		frame:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_START")
		frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
		frame:UnregisterEvent("UNIT_AURA")
	end

	---@param spellId number
	---@return boolean
	function frame:IsExtender(spellId)
		return spellId == 395160 -- Eruption
			or spellId == 408092 -- Upheaval with Font of Magic
			or spellId == 382266 -- Fire Breath with Font of Magic
			or spellId == 396286 -- Upheaval
			or spellId == 357208 -- Fire Breath
	end

	---@param spellId number
	---@return number
	function frame:GetCastTime(spellId)
		if spellId == 395160 then
			return C_Spell.GetSpellInfo(spellId).castTime / 1000
		end

		return GetUnitEmpowerMinHoldTime("player") / 1000
	end

	function frame:GetEbonMightExpirationTime()
		local auraData = C_UnitAuras.GetPlayerAuraBySpellID(395296)

		return auraData and auraData.expirationTime or 0
	end

	function frame:Queue(callback)
		RunNextFrame(callback)
	end

	function frame:PlaySound()
		Private.Utils.AttemptToPlaySound(
			EbonMightExtensionHelperSaved.Settings.Sound,
			EbonMightExtensionHelperSaved.Settings.SoundChannel
		)
	end

	local function OnEvent(self, event, ...)
		if not EbonMightExtensionHelperSaved.Settings.Enabled then
			return
		end

		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
			local unit, castGUID, spellId = ...

			if spellId < 100000 and event == "UNIT_SPELLCAST_EMPOWER_START" then
				spellId = select(4, ...)
			end

			if not self:IsExtender(spellId) then
				return
			end

			local now = GetTime()

			if self.expirationTime == 0 then
				-- queueing up a spell directly after EM will not have the buff yet
				if now == self.lastEbonMightCast then
					return
				end

				self:PlaySound()
				return
			end

			local castTime = self:GetCastTime(spellId)
			-- the game does not send refresh events when you extend so we have to
			-- poll for the latest expiration time. luckily, this appears to be cheap
			self.expirationTime = self:GetEbonMightExpirationTime()

			local result = now + castTime > self.expirationTime

			if result and self.expirationTime - now < 2 then
				-- forward the expected cast end time since between this and the
				-- next check, an aura change may lead to haste changes

				self:Queue(function()
					OnEvent(self, self.customEventName, now + castTime, self.expirationTime, 1)
				end)
				return
			end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, castGUID, spellId = ...

			if spellId == 395152 then
				self.lastEbonMightCast = GetTime()
			end
		elseif event == "UNIT_AURA" then
			self.expirationTime = self:GetEbonMightExpirationTime()
		elseif event == self.customEventName then
			local expectedCastEnd, previousExpirationTime, count = ...
			local spellId = select(9, UnitCastingInfo("player")) or select(8, UnitChannelInfo("player"))

			if spellId == nil then
				return
			end

			-- cast that triggered the queue may be aborted by now
			if not self:IsExtender(spellId) then
				return
			end

			self.expirationTime = self:GetEbonMightExpirationTime()

			-- buff faded since then. unlikely but possible
			if self.expirationTime == 0 then
				self:PlaySound()

				return
			end

			local result = expectedCastEnd > self.expirationTime

			-- after 5 attempts OR the update indicates we can savely extend
			if count == 5 or not result then
				if result then
					self:PlaySound()
				end

				return
			end

			-- no changes observed, the remaining expirationTime is still within 2s
			if previousExpirationTime == self.expirationTime and self.expirationTime - GetTime() < 2 then
				self:Queue(function()
					OnEvent(self, self.customEventName, expectedCastEnd, previousExpirationTime, count + 1)
				end)

				return
			end

			if result then
				self:PlaySound()
			end
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "LOADING_SCREEN_DISABLED" then
			---@type number
			local currentSpecId = PlayerUtil.GetCurrentSpecID()

			-- only Augmentation. see ID columns here: https://wago.tools/db2/ChrSpecialization
			if currentSpecId == 1473 then
				self:RegisterSpecSpecificEvents()

				if event == "LOADING_SCREEN_DISABLED" then
					self.expirationTime = self:GetEbonMightExpirationTime()
				end
			else
				self:UnregisterSpecSpecificEvents()
			end
		end
	end

	frame:SetScript("OnEvent", OnEvent)
end)
