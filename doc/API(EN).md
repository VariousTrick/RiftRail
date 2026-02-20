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

-- Get the "train arrived" event ID
remote.call("RiftRail", "get_train_arrived_event")
```

Once you have the event ID, use script.on_event to listen for it.

### Custom Event Parameter Reference

The event table includes:

- `train`: LuaTrain, the train being teleported
- `train_id`: number, the train's ID
- `source_teleporter` / `destination_teleporter`: LuaEntity, entry/exit portal
- `source_surface` / `destination_surface`: LuaSurface, entry/exit surface
- `source_surface_index` / `destination_surface_index`: number, surface index
- `tick`: number, when the event was fired
- `old_train_id`: number, only in the arrival event, the original train ID

### Notes

Rift Rail custom events are fired once per full train teleport (start and end), with all relevant data in the event table. Standard events are fired for each carriage. Choose the approach that fits your needs, or use both for full coverage.

If you have any questions, feel free to ask on our mod page.
