lovetoys = require("lovetoys")
lume = require("lume")

FirstPuzzleButtonComponent = Component.create(
  "FirstPuzzleButton", {"n"}
)

FirstPuzzleButtonSystem = _G.class("FirstPuzzleButtonSystem", System)
FirstPuzzleButtonSystem.requires = () =>
  {"FirstPuzzleButton", "Interaction"}
FirstPuzzleButtonSystem.update = () =>
  for _, entity in pairs @targets
    if WalkingModule.state_variables.first_puzzle
      entity\get("Interaction").current_state = WalkingModule.state_variables.first_puzzle[entity\get("FirstPuzzleButton").n]

process_components = (new_ent, comp_name, comp) ->
  switch comp_name
    when "first_puzzle_button"
      new_ent\add(FirstPuzzleButtonComponent(comp.n))

      true

add_systems = (engine) ->
  with engine
    \addSystem(FirstPuzzleButtonSystem())

button_callback = (curr_state, n) ->
  with WalkingModule.state_variables.first_puzzle
    switch n
      when "first"
        .first = if .first == "right" then "wrong" else "right"
        .third = if .third == "right" then "wrong" else "right"
      when "second"
        .second = if .second == "right" then "wrong" else "right"
        .first = if .first == "right" then "wrong" else "right"
      when "third"
        .third = if .third == "right" then "wrong" else "right"
  with WalkingModule.state_variables.first_puzzle
    if lume.all({.first, .second, .third}, (x) -> x == "right")
      WalkingModule.state_variables.first_puzzle.solved = true

  WalkingModule.state_variables.first_puzzle[n]

first_puzzle_solved = () ->
  if not WalkingModule.state_variables.first_puzzle
    WalkingModule.state_variables.first_puzzle = { first: "wrong", second: "wrong", third: "wrong", solved: false }

  WalkingModule.state_variables.first_puzzle.solved

first_puzzle_not_solved = () -> not first_puzzle_solved()

{
  :FirstPuzzleButtonComponent,
  :FirstPuzzleButtonSystem,
  :process_components, :add_systems,
  :button_callback,
  :first_puzzle_solved, :first_puzzle_not_solved
}
