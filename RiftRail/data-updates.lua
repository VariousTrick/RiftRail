-- this file modifies the recipe for Rift Rail if the Space Exploration mod is active and optionally if the K2 mod is also present.
-- loaded after data.lua form all mods
-- No thermofluid cant get it to work

--ceck if the items exist before changing recipe
local function item_exists(ingredients)
  for _, ingredient in pairs(ingredients) do
    if ingredient.type == "item" and not data.raw.item[ingredient.name] then
      return false
    end
  end
  return true
end

-- Modify Rift Rail recipe if Space Exploration mod is active
if mods["space-exploration"] then
  if data.raw.recipe["rift-rail-placer"] then
    data.raw.recipe["rift-rail-placer"].ingredients = {
      {type = "item", name = "se-space-rail", amount = 100},
      {type = "item" , name = "se-biological-insight", amount = 50},
      {type = "item" , name = "se-energy-insight", amount = 50},
      {type = "item" , name = "se-material-insight", amount = 50},
      {type = "item" , name = "se-astronomic-insight", amount = 50},
      {type = "item" , name = "se-quantum-processor", amount = 50},
      {type = "item" , name = "se-superconductive-cable", amount = 100},
      {type = "item" , name = "se-naquium-tessaract", amount = 8},
      {type = "item" , name = "se-nanomaterial", amount = 100}
    }
    -- If K2 mod is also present, add Energy Control Units and change Quantum Processor to AI Core to the recipe
    if mods["Krastorio2"] and mods["space-exploration"] then
      table.insert(data.raw.recipe["rift-rail-placer"].ingredients, {
        type = "item" ,
        name = "kr-energy-control-unit",
        amount = 50 -- change amount as needed
    })
      -- Change Quantum Processor to AI Core
      for i, ingredient in ipairs(data.raw.recipe["rift-rail-placer"].ingredients) do
        if ingredient.name == "se-quantum-processor" then
          data.raw.recipe["rift-rail-placer"].ingredients[i] = {
            type = "item",
            name = "kr-ai-core",
            amount = 50 -- change amount as needed
          }
          break
        end
      end
    end
  end
end


-- Technology Change for Rift Rail if Space Exploration mod is active
if data.raw.technology["rift-rail-tech"] and mods["space-exploration"] then
  data.raw.technology["rift-rail-tech"].prerequisites = {
    "se-space-rail",
    "se-naquium-tessaract"
  }
  -- add Krastorio2 prerequisite if Krastorio2 mod is present
  if mods["Krastorio2"] and mods["space-exploration"] then
    table.insert(data.raw.technology["rift-rail-tech"].prerequisites, "kr-energy-control-unit")
  end
end

-- Resarch Unit Change for Rift Rail if Space Exploration mod is active
if data.raw.technology["rift-rail-tech"] and mods["space-exploration"] then
  data.raw.technology["rift-rail-tech"].unit = {
    count = 4000, -- change amount as needed
    ingredients = {
      { "se-rocket-science-pack", 1 },
      { "se-astronomic-science-pack-4", 1 },
      { "se-biological-science-pack-4", 1 },
      { "se-energy-science-pack-4", 1 },
      { "se-material-science-pack-4", 1 },
      { "se-deep-space-science-pack-2", 1 }
    },
    time = 60 -- change time as needed
  }
end

-- recipe lock to Space Exploration Manufacturing ficility
if data.raw.recipe["rift-rail-placer"] and mods["space-exploration"] then
  data.raw.recipe["rift-rail-placer"].category = "space-manufacturing"
end
