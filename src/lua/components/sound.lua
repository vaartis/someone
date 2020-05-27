local interaction_components
local assets = require("components.assets")

local SoundPlayerComponent = Component.create("SoundPlayer", {"sound",  "activate_callback", "played"}, { played = false })

local SoundPlayerSystem = class("SoundPlayerSystem", System)
function SoundPlayerSystem:requires() return {"SoundPlayer"} end
function SoundPlayerSystem:update()
   for _, entity in pairs(self.targets) do
      local sound_comp = entity:get("SoundPlayer")
      if not (sound_comp.played) then
         if sound_comp.activate_callback() then
            sound_comp.sound:play()
            sound_comp.played = true
         end
      end
   end
end

local M = {}

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "sound_player" then
      if not interaction_components then
         interaction_components = require("components.interaction")
      end

      local callback =
         interaction_components.try_get_fnc_from_module(comp_name, comp, entity_name, "activatable_callback", "activatable_callbacks", "activatable")

      local sound = Sound.new()
      sound.buffer = assets.assets.sounds[comp.sound_asset]
      if comp.volume then
         sound.volume = comp.volume
      end

      new_ent:add(SoundPlayerComponent(sound, callback))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(SoundPlayerSystem())
end

return M
