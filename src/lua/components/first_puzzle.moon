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

button_callback = (curr_state, n) ->
  if not WalkingModule.state_variables.first_puzzle
    WalkingModule.state_variables.first_puzzle = { first: "wrong", second: "wrong", third: "wrong", solved: false }

  unless lume.all(WalkingModule.state_variables.first_puzzle, (x) -> x == "right")
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
  else
    WalkingModule.state_variables.first_puzzle.solved = true

  WalkingModule.state_variables.first_puzzle[n]

{
  :FirstPuzzleButtonComponent,
  :FirstPuzzleButtonSystem,
  :process_components,
  :button_callback
}
