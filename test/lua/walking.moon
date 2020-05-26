require("busted.runner")()

rooms = require("components.rooms")
entities = require("components.entities")
lume = require("lume")

describe "ECS", ->
  before_each ->
    rooms.reset_engine!

  describe "TransformableComponent", ->
    describe "without a parent", ->
      local ent
      before_each ->
        ent = entities.instantiate_entity(
          "test",
          {transformable: { position: { 100, 100 } }}
        )

      it "has a global position", ->
        tf = ent\get("Transformable")
        assert.are.equal Vector2f.new(100, 100), tf.transformable.position

    describe "with a parent", ->
      local ent, tf, child, child2, child_tf, child2_tf
      before_each ->
        ent = entities.instantiate_entity(
          "test",
           {
            transformable: { position: { 100, 100 } }
            children: {
              child: {
                transformable: { position: { 100, 100 } },
                children: {
                  child2: {
                    transformable: { position: { 100, 100 } }
                  }
                }
              }
            }
           }
        )
        tf = ent\get("Transformable")

        child = rooms.engine.entities[2]
        child_tf = child\get("Transformable")

        child2 = rooms.engine.entities[3]
        child2_tf = child2\get("Transformable")

      it "can be created created", ->
        assert.are.equal 1, lume.count(ent.children)
        assert.are.equal 1, lume.count(child.children)
      it "has a relative position", ->
        assert.are.equal Vector2f.new(200, 200), child_tf\world_position(child)
        assert.are.equal Vector2f.new(100, 100), child_tf.local_position

        assert.are.equal Vector2f.new(300, 300), child2_tf\world_position(child2)
        assert.are.equal Vector2f.new(100, 100), child2_tf.local_position
      it "updates entity's and children positions when the world position is set", ->
        tf\set_world_position(ent, Vector2f.new(200, 200))

        assert.are.equal Vector2f.new(300, 300), child_tf\world_position(child)
        assert.are.equal Vector2f.new(400, 400), child2_tf\world_position(child2)

        child_tf\set_world_position(child, Vector2f.new(200, 200))

        assert.are.equal Vector2f.new(200, 200), child_tf\world_position(child)
        -- Should update
        assert.are.equal Vector2f.new(0, 0), child_tf.local_position

        assert.are.equal Vector2f.new(300, 300), child2_tf\world_position(child2)
        -- Should remain the same
        assert.are.equal Vector2f.new(100, 100), child2_tf.local_position

      it "updates entity's and children position when the local position is set", ->
        tf\set_local_position(ent, Vector2f.new(200, 200))

        assert.are.equal Vector2f.new(300, 300), child_tf\world_position(child)
        assert.are.equal Vector2f.new(400, 400), child2_tf\world_position(child2)

        child_tf\set_local_position(child, Vector2f.new(200, 200))

        assert.are.equal Vector2f.new(400, 400), child_tf\world_position(child)
        assert.are.equal Vector2f.new(200, 200), child_tf.local_position

        assert.are.equal Vector2f.new(500, 500), child2_tf\world_position(child2)

  describe "RenderSystem", ->
    local ent, ent2, drawable, drawable2
    before_each ->
      ent = entities.instantiate_entity(
        "test1",
        {
          drawable: { kind: "text", text: { text: "Test 1" }, z: 2 }
        }
      )
      ent2 = entities.instantiate_entity(
        "test2",
        {
          drawable: { kind: "text", text: { text: "Test 2" }, z: 1 }
        }
      )
      drawable = ent\get("Drawable")
      drawable2 = ent2\get("Drawable")

    it "sorts entities by Z level", ->
      assert.are.same { ent2, ent }, rooms.engine.systemRegistry["RenderSystem"]._sorted_targets
