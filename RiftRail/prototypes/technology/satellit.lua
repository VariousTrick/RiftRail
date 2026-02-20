-- unlocks satellit recipe with rocket silo technology

if mods["space-age"] and data.raw.recipe["satellit"] then
    table.insert(data.raw.technology["rocket-silo"]
        and data.raw.technology["rocket-silo"].effects,
        {
            type = "unlock-recipe",
            recipe = "satellit"
        })
end
