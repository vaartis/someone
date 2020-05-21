local interaction_components
assets = require("components.assets")

SoundPlayerComponent = Component.create("SoundPlayer", {"sound", "activate_callback", "played"}, { played: false })
SoundPlayerSystem = _G.class("SoundPlayerSystem", System)
SoundPlayerSystem.requires = () => {"SoundPlayer"}
SoundPlayerSystem.update = () =>
  for _, entity in pairs @targets
    sound_comp = entity\get("SoundPlayer")
    unless sound_comp.played
      if sound_comp.activate_callback()
        sound_comp.sound\play()
        sound_comp.played = true

process_components = (new_ent, comp_name, comp, entity_name) ->
  switch comp_name
    when "sound_player"
      if not interaction_components
        interaction_components = require("components.interaction")

      callback = interaction_components.try_get_fnc_from_module(
        comp_name, comp, entity_name, "activatable_callback", "activatable_callbacks", "activatable"
      )

      sound = with Sound.new!
        .buffer = assets.assets.sounds[comp.sound_asset]

      new_ent\add(SoundPlayerComponent(sound, callback))

      true

add_systems = (engine) ->
  with engine
    \addSystem(SoundPlayerSystem())

{
  :SoundPlayerComponent, :SoundPlayerSystem,
  :process_components, :add_systems
}
