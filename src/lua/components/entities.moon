toml = require("toml")
util = require("util")

shared_components = require("components.shared")
player_components = require("components.player")
first_puzzle = require("components.first_puzzle")
collider_components = require("components.collider")
note_components = require("components.note")
local interaction_components
sound_components = require("components.sound")

load_prefab = (prefab_name_or_conf, base_data) ->
  local prefab_name, removed_components
  -- Allow prefab to either be just a name or a table with more info
  switch type(prefab_name_or_conf)
    when "table"
      prefab_name = prefab_name_or_conf.name
      removed_components = prefab_name_or_conf.removed_components
    when "string"
      prefab_name = prefab_name_or_conf

  prefab_data = do
    local data
    with io.open("resources/rooms/prefabs/#{prefab_name}.toml", "r")
      data = toml.parse(\read("*all"))
      \close()
    data

  base_data = util.deep_merge(prefab_data, base_data)

  -- Clear the components requested by removed_components
  if removed_components
    for _, name_to_remove in pairs removed_components
      base_data[name_to_remove] = nil

  -- Remove the mention of the prefab from the entity
  base_data.prefab = nil

  base_data


instantiate_entity = (entity_name, entity, parent) ->
  -- Has to be required from here to avoid recursive dependency
  if not interaction_components
    interaction_components = require("components.interaction")

  new_ent = Entity(parent)

  if entity.prefab
    entity = load_prefab(entity.prefab, entity)

  add_transformable_actions = {}
  add_collider_actions = {}

  for comp_name, comp in pairs entity
    switch comp_name
      when "transformable"
        table.insert(
          add_transformable_actions,
          ->
            unless new_ent\has("Transformable")
              -- If there's no transformable component, create and add it
              new_ent\add(shared_components.TransformableComponent(Transformable.new()))
            tf_component = new_ent\get("Transformable")

            with tf_component.transformable
              if parent
                parent_tf = parent\get("Transformable").transformable
                relative_position = Vector2f.new(comp.position[1], comp.position[2])
                -- Apply the position in relation to the parent position
                .position = parent_tf.position + relative_position

                tf_component.local_position = relative_position
              else
                .position = Vector2f.new(comp.position[1], comp.position[2])

              .origin = Vector2f.new(comp.origin[1], comp.origin[2]) if comp.origin
              .scale = Vector2f.new(comp.scale[1], comp.scale[2]) if comp.scale
        )
      when "collider"
        table.insert(
          add_collider_actions,
          -> collider_components.process_collider_component(new_ent, comp, entity_name)
        )
      when "tags"
        -- TODO: this tag system doesn't seem like a very good solution, maybe
        -- it should be changed somehow to allow selecting entities by tags directly,
        -- though it is likely that this change has to be done in the ECS itself
        for _, tag in pairs comp
          switch tag
            when "interaction_text"
              new_ent\add(interaction_components.InteractionTextTag())
            else
              error("Unknown tag in #{entity_name}.#{comp_name}: #{tag}")
      when "children"
        continue
      else
        component_processors = {
          shared_components,
          player_components,
          interaction_components,
          sound_components,
          note_components,
          first_puzzle
        }

        processed = false
        for _, processor in pairs component_processors
          if processor.process_components(new_ent, comp_name, comp, entity_name)
            processed = true
            break
        if not processed
          error("Unknown component: #{comp_name} on #{entity_name}")

  -- Call all the "after all inserted" actions
  for _, actions in pairs {add_transformable_actions, add_collider_actions}
      for _, action in pairs actions
        action!

  util.rooms_mod!.engine\addEntity(new_ent)
  if entity.children
    for name, data in pairs(entity.children)
      instantiate_entity(name, data, new_ent)
  new_ent

{:instantiate_entity}
