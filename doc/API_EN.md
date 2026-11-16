# Rift Rail - Mod Compatibility & API Guide

Welcome! This document is designed to help other mod developers achieve compatibility with Rift Rail.

## Core Mechanism: Destruction & Recreation

Understanding Rift Rail's core mechanism is crucial: when a train passes through a portal, it is not simply "moved"—the **old train entity is destroyed carriage by carriage, and a new train entity is recreated at the exit, also carriage by carriage**.

This means any variable or data table directly referencing the old train entity (`LuaEntity`) will become invalid after teleportation.


## Event Listening Recommendations & Custom Events

Rift Rail triggers Factorio's standard `on_entity_cloned` event during teleportation:

- These events are fired for each new carriage created, making them suitable for mods that need to process individual carriages.

Additionally, Rift Rail fires custom events at the start and end of a full train teleportation. These custom events (IDs available via remote.call) provide high-level information about the entire train and are ideal for mods that need to track the overall teleportation process or perform cross-mod interactions.

### Listening Strategy

- Need per-carriage details? → Listen to standard events (`on_entity_cloned`)
- Need whole-train or cross-mod info? → Listen to Rift Rail custom events
- For maximum compatibility, you may listen to both

### How to Get Rift Rail Custom Event IDs

Use remote.call to get the event IDs:

```lua
-- Get the "train departing" event ID
remote.call("RiftRail", "get_train_departing_event")

-- Get the "train teleport transfer" event ID
remote.call("RiftRail", "get_train_teleport_transfer_event")

-- Get the "train arrived" event ID
remote.call("RiftRail", "get_train_arrived_event")
```

Once you have the event ID, use script.on_event to listen for it.

### Custom Event Parameter Reference

### Notes
The event table includes the following fields:

#### `TrainDeparting`
*Trigger timing: Fired at the moment the teleport session is initialized and the portal locking sequence begins. The train is still completely intact in the entry portal. Ideal for general mods to clear station logic as the train begins its departure.*
*   `train`: [LuaTrain] The complete old train entity.
*   `train_id`: [number] The ID of the old train.
*   `source_teleporter`: [LuaEntity] The source teleporter entity.
*   `source_teleporter_id`: [number] The ID of the source teleporter.
*   `source_surface`: [LuaSurface] The source surface.
*   `source_surface_index`: [number] The index of the source surface.

#### `TrainTeleportTransfer`
*Trigger timing: Fired at the exact microsecond the first new carriage is cloned at the destination, and the old carriage has not yet been destroyed. This event is specifically designed for logistics mods (like LTN/Cybersyn) to seamlessly assign deliveries from the old train ID to the new train ID in the same tick. To satisfy fundamental API constraints of third-party logistics mods, this event provides both IDs and the actual new train entity object.*
*   `old_train_id`: [number] The ID of the complete old train.
*   `new_train_id`: [number] The ID of the newly generated train at the exit (currently containing only the first carriage).
*   `new_train`: [LuaTrain] The newly generated train entity object at the exit.
*   `entry_unit_number`: [number] The unit_number of the entry (source) teleporter.
*   `exit_unit_number`: [number] The unit_number of the exit (destination) teleporter.

#### `TrainArrived`
*   `train`: [LuaTrain] The complete, newly created train entity.
*   `train_id`: [number] The ID of the new train.
*   `old_train_id`: [number] **[Key]** The ID of the old train that was teleported, used to link with the `TrainDeparting` event.
*   `source_surface`: [LuaSurface] The origin surface.
*   `source_surface_index`: [number] The index of the origin surface.
*   `destination_teleporter`: [LuaEntity] The destination teleporter entity.
*   `destination_teleporter_id`: [number] The ID of the destination teleporter.
*   `destination_surface`: [LuaSurface] The destination surface.
*   `destination_surface_index`: [number] The index of the destination surface.
*   `entry_unit_number`: [number] The unit_number of the entry (source) teleporter.
*   `exit_unit_number`: [number] The unit_number of the exit (destination) teleporter.
*   `restored_guis`: [table] (An object table used internally for GUI restoration).

### Notes

Rift Rail custom events are fired once per full train teleport (start and end), with all relevant data in the event table. Standard events are fired for each carriage. Choose the approach that fits your needs, or use both for full coverage.

---

## Remote Interface

In addition to custom events, Rift Rail provides `remote.call` interfaces for third-party mods to query topology data or coordinate actions.

### Portal Pairing Topology Query

#### 1. `get_paired_portals`
Queries all paired entries and exits for a given portal, returning a structured pure data table (with ID placed first in each item).

```lua
local data = remote.call("RiftRail", "get_paired_portals", portal_or_id)
```

- **Parameter `portal_or_id`** (optional):
  - `number`: Custom numeric portal ID (e.g., `1`).
  - `string`: String format of the ID (e.g., `"1"`).
  - `LuaEntity`: Portal entity object (supports shell `rift-rail-entity`, core `rift-rail-core`, or any child entity).
  - `nil`: Defaults to the entity currently selected by the player (`game.player.selected`).
- **Return Value**: Returns `nil` if not found; otherwise returns a table structured as follows:
  ```lua
  {
      id = 1,                                -- [number] Custom ID of the portal
      name = "Main Base Depot",              -- [string] Custom name (empty string if unnamed)
      mode = "entry",                        -- [string] Operating mode: "entry" | "exit" | "neutral"
      gps = "[gps=10.5,20.0,nauvis]",        -- [string] Rich text GPS hyperlink
      entries = {                            -- [table] List of paired entries (sorted ascending by ID)
          {
              id = 2,
              name = "Remote Input",
              mode = "entry",
              gps = "[gps=-50.0,80.0,nauvis]",
          },
      },
      exits = {                              -- [table] List of paired exits (sorted ascending by ID)
          {
              id = 3,
              name = "Smelting Area Exit",
              mode = "exit",
              gps = "[gps=120.0,-35.0,vulcanus]",
          },
      },
  }
  ```

#### 2. `print_paired_portals`
Formats and prints the pairing topology of a given portal to a player's chat console (or game console) using localized rich text. Items include entry/exit subheadings, item counts, and clickable map GPS hyperlinks at the end of each entry.

```lua
remote.call("RiftRail", "print_paired_portals", portal_or_id, target_player)
-- Also supports reversed argument order:
-- remote.call("RiftRail", "print_paired_portals", target_player, portal_or_id)
```

- **Parameters**:
  - `portal_or_id`: Same as `get_paired_portals` (supports numeric/string ID, entity, or portaldata table).
  - `target_player` (optional): `LuaPlayer` object. If omitted or called without a player context, safely falls back to console output.
- **Output Sample**:
  ```text
  [RiftRail] ID: 1 · Nauvis Entry [Entry] -> [gps=10.5,20.0,nauvis]
  ▼ Paired Exits (Total 2):
    [1] ID: 2 · Vulcanus Foundry Exit -> [gps=-100.0,55.5,vulcanus]
    [2] ID: 3 · Gleba Bio Farm Exit -> [gps=32.0,-80.0,gleba]
  ```

---

If you have any questions, feel free to ask on our mod page.
