local interaction_components
local assets = require("components.assets")

local SoundPlayerComponent = Component.create("SoundPlayer", {"sound",  "activate_callback", "played"}, { played = false })

local SoundPlayerSystem = class("SoundPlayerSystem", System)
function SoundPlayerSystem:requires() return {"SoundPlayer"} end
function SoundPlayerSystem:update()
   for _, entity in pairs(self.targets) do
      local sound_comp = entity:get("SoundPlayer")
      if not sound_comp.played then
         local should_play = (sound_comp.activate_callback and sound_comp.activate_callback()) or true

         if should_play then
            sound_comp.sound:play()
            sound_comp.played = true
         end
      end
   end
end
function SoundPlayerSystem:onBeforeResetEngine()
   for _, entity in pairs(self.targets) do
      local sound_comp = entity:get("SoundPlayer")

      sound_comp.sound:stop()
   end
end

local M = {}

function M.process_components(new_ent, comp_name, comp, entity_name)
   if comp_name == "sound_player" then
      if not interaction_components then
         interaction_components = require("components.interaction")
      end

      local callback
      if comp.activatable_callback then
         callback = interaction_components.process_activatable(
            comp,
            "activatable_callback",
            { entity_name = entity_name, comp_name = comp_name, needed_for = "activatable" }
         )
      end

      local sound = Sound.new()
      sound.buffer = assets.assets.sounds[comp.sound_asset]
      if comp.volume then sound.volume = comp.volume end
      if comp.loop then sound.loop = comp.loop end
      if comp.position then sound.position = Vector3f.new(comp.position[1], comp.position[2], comp.position[3]) end

      new_ent:add(SoundPlayerComponent(sound, callback))

      return true
   end
end

function M.add_systems(engine)
   engine:addSystem(SoundPlayerSystem())
end

return M
