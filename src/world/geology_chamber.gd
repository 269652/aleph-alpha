extends RefCounted

## Which local Strata cells a cave entrance reveals -- the underground
## equivalent of RoomDetector's room cells (see docs/concept/geology.md
## "Reveal-on-entry, reused recursively"). A small circular patch around
## the entrance rather than a flood-filled region: unlike a building
## interior, there is no wall data yet defining a real chamber shape, so
## this stands in as the initial "starter pocket" a shaft opens into --
## deliberately small and bounded rather than an arbitrary big reveal.
##
## Static, pure, and stateless, matching TerrainPassability's own
## namespace-style convention -- callers only ever need cells_for.

## Radius (tiles) of the revealed pocket around a cave entrance.
const CHAMBER_RADIUS := 3


## Local cells belonging to the chamber revealed by a cave entrance at
## `entrance_local_cell`, including the entrance cell itself. Circular
## (Euclidean distance <= CHAMBER_RADIUS, not a square block) so the pocket
## reads as a rounded cave chamber rather than a diggable square room.
static func cells_for(entrance_local_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-CHAMBER_RADIUS, CHAMBER_RADIUS + 1):
		for dx in range(-CHAMBER_RADIUS, CHAMBER_RADIUS + 1):
			if Vector2(dx, dy).length() <= float(CHAMBER_RADIUS) + 0.5:
				cells.append(entrance_local_cell + Vector2i(dx, dy))
	return cells
