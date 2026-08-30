extends RefCounted

## Per-pixel river-flow DATA, not art -- mirrors
## procedural_hillshade_sprite.gd's "bake a data channel into a texture,
## sample it as data in the fragment shader" shape. See
## docs/concept/rivers.md's "Flow rendering" section.
##
## Four channels, each earning its place:
##   R  wrapped streak phase   -- the continuous phase potential along the
##                               river's own course (see RiverPhaseField).
##                               THE fix for the old shader's tile-lattice
##                               phase resets.
##   G  flow direction x       -- as a VECTOR COMPONENT, not a bearing
##   B  flow direction y       -- ditto
##   A  speed fraction         -- drives foam and contrast
##
## Direction is stored as a vector rather than the compass angle it used to
## be for two real reasons: it saves the shader a `radians` + `sin` + `cos`
## per fragment, and it removes the 0/360 wrap hazard entirely (a bearing
## interpolates catastrophically across north; a unit vector does not).

const SIZE := 32

## Quantisation of each baked dimension. Total atlas tiles is the product,
## so these are a real budget: every extra tile is another `create_tile`
## call at boot, and the atlas texture grows with it.
##
## PHASE_BINS is the one that trades directly against visual quality: the
## phase is continuous in principle, and binning it to 12 caps the worst
## seam between neighbouring tiles at 1/24 of a cycle (15 degrees of the
## streak's sine) -- far below the old construction's arbitrary reset, and
## small enough not to read as a lattice.
##
## SPEED_BINS is only 4 because speed no longer drives the streak GEOMETRY
## (see RiverPhaseField.STREAK_WAVELENGTH_TILES); it drives foam and
## contrast, where four steps is plenty.
const PHASE_BINS := 12
const DIRECTION_BINS := 16
const SPEED_BINS := 4

## 12 * 16 * 4 = 768 tiles. Laid out as a 2D grid rather than one row: a
## single row would be 768 * 32 = 24,576 px wide, past the 16,384
## GL_MAX_TEXTURE_SIZE common on the integrated GPUs this game targets.
const ATLAS_COLUMNS := 32


static func phase_bin_for(wrapped_phase: float) -> int:
	return int(clampf(fposmod(wrapped_phase, 1.0), 0.0, 0.999999) * PHASE_BINS)


static func phase_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(PHASE_BINS)


static func direction_bin_for(angle_deg: float) -> int:
	var wrapped := fposmod(angle_deg, 360.0)
	return int(clampf(wrapped / 360.0, 0.0, 0.999999) * DIRECTION_BINS)


static func angle_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(DIRECTION_BINS) * 360.0


static func speed_bin_for(speed_fraction: float) -> int:
	return int(clampf(speed_fraction, 0.0, 0.999999) * SPEED_BINS)


static func speed_for_bin(bin: int) -> float:
	return (float(bin) + 0.5) / float(SPEED_BINS)


## Flat index of a (phase, direction, speed) combination, and its position
## in the 2D atlas grid. One function owns the packing so the tile-set
## builder and the per-cell lookup can never disagree about it.
static func atlas_index_for(phase_bin: int, direction_bin: int, speed_bin: int) -> int:
	return (speed_bin * PHASE_BINS * DIRECTION_BINS) + (phase_bin * DIRECTION_BINS) + direction_bin


static func atlas_cell_for_index(index: int) -> Vector2i:
	return Vector2i(index % ATLAS_COLUMNS, index / ATLAS_COLUMNS)


static func total_tiles() -> int:
	return PHASE_BINS * DIRECTION_BINS * SPEED_BINS


func generate_texture(angle_deg: float, speed_fraction: float, wrapped_phase: float) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(angle_deg, speed_fraction, wrapped_phase))


## One data tile, uniform across its whole area like
## ProceduralHillshadeSprite's own tiles. Direction is encoded as a unit
## vector mapped from [-1,1] into the [0,1] a colour channel can hold.
func generate_image(angle_deg: float, speed_fraction: float, wrapped_phase: float) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var radians := deg_to_rad(fposmod(angle_deg, 360.0))
	# Godot 2D: +X east, +Y DOWN (screen space), so "north" is -Y.
	var direction := Vector2(sin(radians), -cos(radians))
	image.fill(Color(
		clampf(fposmod(wrapped_phase, 1.0), 0.0, 1.0),
		direction.x * 0.5 + 0.5,
		direction.y * 0.5 + 0.5,
		clampf(speed_fraction, 0.0, 1.0)
	))
	return image
