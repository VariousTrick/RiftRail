# Rift Rail - Mod Compatibility & API Guide

Welcome! This document is designed to help other mod developers achieve compatibility with Rift Rail.

## Core Mechanism: Destruction & Recreation

Understanding Rift Rail's core mechanism is crucial: when a train passes through a portal, it is not simply "moved"—the **old train entity is destroyed carriage by carriage, and a new train entity is recreated at the exit, also carriage by carriage**.

This means any variable or data table directly referencing the old train entity (`LuaEntity`) will become invalid after teleportation.


## Event Listening Recommendations & Custom Events

Rift Rail triggers Factorio's standard `on_built_entity` and `on_entity_cloned` events depending on the teleportation method:

- These events are fired for each new carriage created, making them suitable for mods that need to process individual carriages.

Additionally, Rift Rail fires custom events at the start and end of a full train teleportation. These custom events (IDs available via remote.call) provide high-level information about the entire train and are ideal for mods that need to track the overall teleportation process or perform cross-mod interactions.

### Listening Strategy

- Need per-carriage details? → Listen to standard events (`on_built_entity`/`on_entity_cloned`)
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
*Trigger timing: Fired at the exact microsecond the first new carriage is cloned at the destination, and the old carriage has not yet been destroyed. This event is specifically designed for logistics mods (like LTN/Cybersyn) to seamlessly assign deliveries from the old train ID to the new train ID in the same tick. To prioritize extreme performance and minimum GC overhead, this event solely passes the IDs of the two train entities.*
*   `old_train_id`: [number] The ID of the complete old train.
*   `new_train_id`: [number] The ID of the newly created train at the destination (containing only the first carriage).

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

### Notes

Rift Rail custom events are fired once per full train teleport (start and end), with all relevant data in the event table. Standard events are fired for each carriage. Choose the approach that fits your needs, or use both for full coverage.

If you have any questions, feel free to ask on our mod page.
