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
##
## Was 3 (a 7-tile-diameter, ~37-cell disk) until reported live (playtest,
## 2026-08-28): at the shipped camera zoom (Player.TARGET_TILE_SCREEN_PX =
## 64px/tile) that disk renders at ~448px against the project's own 720px-
## tall default viewport -- ~62% of the visible screen's shorter side,
## read as "a dense grid covering most of the visible ground," not the
## small starter pocket this file's own doc comment claimed. Since Strata
## cells are SOLID/ORE by default until mined (see strata.gd), the chamber
## fills essentially 100% on first reveal -- there is no scatter to thin
## it out the way StonePlacement's surface density does, so radius alone
## is the only lever. 1 (a 3x3, 9-cell pocket) is the largest radius that
## still clears test_chamber_diameter_stays_a_small_fraction_of_the_
## visible_screen's screen-relative bound, while staying more than just
## the entrance cell (test_chamber_is_small_and_bounded's own lower
## bound).
const CHAMBER_RADIUS := 1


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
