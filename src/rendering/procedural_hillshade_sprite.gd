extends RefCounted

## Per-pixel slope/aspect DATA, not art (see docs/concept/terrain_relief.md's
## "Hillshading" section) -- mirrors procedural_shore_distance_sprite.gd's
## exact "bake a data channel into a texture, sample it as data in the
## fragment shader" shape, just two channels (slope in red, aspect in
## green) instead of shore-distance's one.
##
## Unlike shore-distance (a small, genuinely enumerable set of shapes -- 16
## land-direction masks), real slope/aspect are CONTINUOUS per tile: every
## one of this project's real-Earth tiles has its own value
## (terrain_relief.gd). A unique atlas tile per position doesn't fit
## TileSet's bounded-atlas model at all, so this quantizes into a small,
## honestly-coarse grid instead -- SLOPE_BINS bands of steepness x
## ASPECT_BINS compass octants, plus one shared "flat" tile (aspect is
## meaningless at zero slope, matching terrain_relief.gd's own -1
## convention, so flat ground needs no aspect dimension at all). The same
## kind of honest simplification docs/concept/terrain_relief.md already
## accepts for tile-to-tile slope itself.

const SIZE := 32

## 8 bands across the full range terrain_passability.gd's soft-to-hard
## slope thresholds span -- fine enough that a mountainside reads as a real
## gradient rather than a handful of visible stripes, without needing
## hundreds of atlas tiles for a difference too subtle to see at this pixel
## scale anyway.
const SLOPE_BINS := 8
const MAX_SLOPE_DEG := 90.0

## 8 compass octants (N/NE/E/SE/S/SW/W/NW) -- the same granularity a real
## paper map's hillshade legend typically uses, plenty for a tile to read
## as facing "roughly that way".
const ASPECT_BINS := 8


## Which slope bin a real slope in degrees falls into. Clamped to the last
## bin for anything at or beyond MAX_SLOPE_DEG, so a genuine cliff face
## still reads as the darkest/lightest band available rather than being
## undrawable.
static func slope_bin_for(slope_deg: float) -> int:
	var t := clampf(slope_deg / MAX_SLOPE_DEG, 0.0, 0.999999)
	return int(t * SLOPE_BINS)


## Which aspect octant a real compass bearing falls into.
static func aspect_bin_for(aspect_deg: float) -> int:
	var wrapped := fposmod(aspect_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * ASPECT_BINS)


## The representative (bin-center) slope this bin bakes -- what actually
## gets encoded into the shared tile every slope in the bin draws from, not
## whichever raw sample happened to land in it.
static func slope_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(SLOPE_BINS) * MAX_SLOPE_DEG


static func aspect_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(ASPECT_BINS) * 360.0


func generate_texture(slope_deg: float, aspect_deg: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(slope_deg, aspect_deg))


## One data tile: red = normalized slope [0,1], green = normalized aspect
## [0,1] -- uniform across the whole tile, like
## ProceduralShoreDistanceSprite's own ring tiles (one tile can only hold
## one baked value). `aspect_deg` below 0 (terrain_relief.gd's flat-ground
## sentinel) bakes green as 0 rather than a fake direction -- harmless
## either way, since the hillshade shader's illumination term multiplies
## aspect's contribution by sin(slope), which is already 0 whenever this is
## called for genuinely flat ground.
func generate_image(slope_deg: float, aspect_deg: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var red := clampf(slope_deg / MAX_SLOPE_DEG, 0.0, 1.0)
	var green := 0.0 if aspect_deg < 0.0 else clampf(aspect_deg / 360.0, 0.0, 1.0)
	image.fill(Color(red, green, 0.0, 1.0))
	return image


## The single shared "flat ground" tile every slope-0 cell draws from.
func generate_flat_image() -> Image:
	return generate_image(0.0, -1.0)
