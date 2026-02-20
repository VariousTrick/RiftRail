# Rift Rail - Mod Compatibility & API Guide

Welcome! This document is designed to help other mod developers achieve compatibility with Rift Rail.

## Core Mechanism: Destruction & Recreation

Understanding Rift Rail's core mechanism is crucial: when a train passes through a portal, it is not simply "moved"—the **old train entity is destroyed carriage by carriage, and a new train entity is recreated at the exit, also carriage by carriage**.

This means any variable or data table directly referencing the old train entity (`LuaEntity`) will become invalid after teleportation.

## How to Track Teleported Trains (Important!)

To maximize performance in specific scenarios, Rift Rail uses two different methods to create new trains depending on the portal's angle. This results in two different events being triggered.

**To ensure 100% compatibility, your mod must listen to both of the following events:**

1.  `defines.events.on_built_entity`
	*   When teleportation requires complex turning, Rift Rail uses the `create_entity` method, which triggers this standard build event.

2.  `defines.events.on_entity_cloned`
	*   When teleportation is a simple "turnaround return" (entry and exit are opposite directions), Rift Rail uses the high-performance `clone` method, which triggers this clone event.

### Recommended Event Handling

The most robust approach is to create a unified handler function and have both events call it.

By listening to both events, your mod can reliably capture all trains teleported by Rift Rail and interact with them.

If you have any questions, feel free to ask on our mod page.
