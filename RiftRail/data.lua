-- =================================================================================================
-- Rift Rail - data.lua
-- rift rail only require(...) when adding content
-- =================================================================================================

if mods["space-age"] then
    require("prototypes.items.satellit")
    require("prototypes.recipes.satellit")
    -- require("prototypes.items.rcu")
    -- require("prototypes.recipes.rcu")
    require("prototypes.technology.satellit")
end

-- =================================================================================================

local util = require("prototypes.util.util")
local sprites = require("prototypes.sprites.rift-rail-sprites")

require("prototypes.items.rift-rail-station")
require("prototypes.recipes.rift-rail-placer")

require("prototypes.entities.placer")
require("prototypes.entities.main")
require("prototypes.entities.lamp")
require("prototypes.entities.collider")
require("prototypes.entities.blocker")
require("prototypes.entities.leader-train")

require("prototypes.internal.station")
require("prototypes.internal.signal")
require("prototypes.internal.rails")
require("prototypes.internal.core")

require("prototypes.technology.rift-rail")

require("prototypes.virtual-signal.goto-id")
require("prototypes.tips-and-tricks.tips-and-tricks")
-- =================================================================================================
