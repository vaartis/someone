util = require("util")

describe "deep_merge", ->
  it "merges two tables", ->
    assert.are.same(
      util.deep_merge({ a: true, b: false }, { a: false, b: true, c: 1 }),
      { a: false, b: true, c: 1 }
    )

  it "merges embedded tables", ->
    assert.are.same(
      util.deep_merge({a: { b: 1 }}, {a: { c: 2 }}),
      { a: { b: 1, c: 2 } }
    )

  it "replaces non-table with a table", ->
    assert.are.same(
      util.deep_merge({a: 1}, {a: { c: 2 }}),
      { a: { c: 2 } }
    )

  it "merges an array with a 'false' value correctly", ->
    assert.are.same(
      util.deep_merge({}, { {"first_puzzle_lamp", "taken"}, false }),
      { {"first_puzzle_lamp", "taken"}, false }
    )    

describe "deep_equal", ->
  it "compares simple values", ->
    assert.is_true util.deep_equal(1, 1)
    assert.is_true util.deep_equal("a", "a")
    assert.is_false util.deep_equal("a", "b")

  it "compares tables", ->    
    assert.is_true util.deep_equal({1, 2}, {1, 2})
    assert.is_false util.deep_equal({1, 2}, {1, 2, 3})

  it "compares nested tables", ->
    assert.is_true util.deep_equal({1, { a: 2 } }, {1, { a: 2 }})
      
    assert.is_false util.deep_equal({1, { a: 2 } }, {1, { 2 }})
    assert.is_false util.deep_equal({1, { a: 2 } }, {1, { a: 3 }})

describe "get_or_default", ->
  it "gets a value by path", ->
    assert.are.equal(
      util.get_or_default({ a: { b: 1 } }, {"a", "b"}, false),
      1
    )
  it "returns a default if no value is found", ->
    assert.are.equal(
      util.get_or_default({ a: {} }, {"a", "b"}, false),
      false
    )    
