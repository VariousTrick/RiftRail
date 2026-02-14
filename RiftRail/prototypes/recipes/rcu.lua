-- add recipe for rcu

data:extend({
    {
        type = "recipe",
        name = "rcu",
        enabled = false,
        energy_required = 30,
        ingredients = {
            { "advanced-circuit", 10 },
            { "processing-unit", 5 },
            { "speed-module-2", 12 }, -- 12 speed module 2 equivalent to 3 speed module 3
        },
        result = { { type = "item", name = "rcu", amount = 10 } },
    },
})
