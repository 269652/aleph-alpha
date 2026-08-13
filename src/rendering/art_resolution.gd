extends RefCounted

## The single factor separating "how many PIXELS OF ART a thing is drawn
## with" from "how much WORLD it occupies" (see docs/concept/
## art_resolution.md).
##
## Phase 1 of the resolution pass learned this the hard way on the ground
## plane: bumping the tile size constant raised art detail AND world
## footprint together, so every tile suddenly covered 4x the world area
## ("water squares are gigantic compared to the player"). The fix is to
## author art at DETAIL_MULTIPLIER times the world size and draw it scaled
## back down by SPRITE_SCALE -- more pixels per world unit, identical
## world layout.
##
## Entity sprites (trees, creatures, the hero, items) reference this
## directly; TerrainRenderer derives its own ART_TILE_SIZE/LAYER_SCALE from
## the same multiplier so terrain and the things standing on it never
## disagree about how much detail a world unit carries.

## How many art pixels are painted per world unit.
##
## 2, not 4. A first version used 4, which quadrupled the pixel COUNT but
## also made one art pixel land on exactly one SCREEN pixel at the game's
## camera zoom -- so nothing looked pixelated at all, reported as "the char
## doesn't look like pixel art". More pixels literally means LESS
## pixelated: 16-bit art needs each art pixel to cover several screen
## pixels so the grid stays visible and chunky.
##
## 2 is the balance: 4x the pixel count of the original art (2x linear),
## while each art pixel still covers 2 screen pixels. Pinned from both
## sides by test_one_art_pixel_covers_several_screen_pixels and
## test_art_is_still_more_detailed_than_before_the_pass.
const DETAIL_MULTIPLIER := 2

## What a sprite drawn with DETAIL_MULTIPLIER-times-oversized art must be
## scaled by so it occupies its intended world size.
const SPRITE_SCALE := 1.0 / float(DETAIL_MULTIPLIER)


## The art canvas size needed to draw something that should occupy
## `world_size` world units.
static func art_size(world_size: Vector2i) -> Vector2i:
	return world_size * DETAIL_MULTIPLIER


## The world footprint of art authored at `art_size` pixels, once drawn at
## SPRITE_SCALE.
static func world_size(art_size_pixels: Vector2i) -> Vector2:
	return Vector2(art_size_pixels) * SPRITE_SCALE
