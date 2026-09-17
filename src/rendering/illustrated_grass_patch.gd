extends RefCounted

## A chunk's worth of TallGrass cells, rendered as GPU-instanced cards from
## the illustrated atlas -- one MultiMeshInstance2D draw call per Y-sort
## band, not one Sprite2D per card. See docs/concept/long_grass.md.
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

## One sheet per season (see docs/concept/long_grass.md's "Seasonal art"),
## superseding the single `grass_blades.png`. `grass_blades_summer.png` IS
## that original file's own art, unchanged -- the other three are new,
## real-drawn spring/autumn/winter variants sharing its exact grid.
const SEASON_ATLAS_PATHS := {
	"spring": "res://assets/sprites/grass_blades_spring.png",
	"summer": "res://assets/sprites/grass_blades_summer.png",
	"autumn": "res://assets/sprites/grass_blades_autumn.png",
	"winter": "res://assets/sprites/grass_blades_winter.png",
}
## What an unrecognised season falls back to -- same reasoning and same
## choice as `SeasonalFoliage.FALLBACK_SEASON`: unexpectedly green reads as
## an ordinary lawn, unexpectedly bare/frosted reads as dead ground.
const DEFAULT_SEASON := "summer"
## Each delivered sheet is 1254×1254 and contains 10×10 blade cells. Source
## art is roughly 128px per cell; regions derive from the true sheet size.
const ATLAS_COLUMNS := 10
const ATLAS_ROWS := 10
const DEFAULT_ATLAS_SIZE := Vector2i(1254, 1254)
## Individual Sprite2D cards used to be expensive enough that this stayed
## small (4). GPU instancing keeps this to ONE draw call regardless of card
## count -- but each card is still a translucent, alpha-blended, shaded quad the
## GPU must rasterize and blend, so cards are cheap in draw CALLS yet not in
## fill rate/overdraw. On a fill-rate-limited integrated GPU a dense field of
## 12-deep tufts was a measurable cost, so this trades a little volumetric
## density for a lot less overdraw (pinned by test_illustrated_grass_patch).
const CARD_COUNT := 8
const WORLD_SIZE := 16.0

## How many horizontal strips a chunk's grass splits into for Y-sorting.
## One draw call per (chunk, band) instead of one per card is the whole
## performance win; a single draw call can only Y-sort as ONE unit, so true
## per-blade sorting against the player needs each band to be thin enough
## that native Y-sort alone (no per-pixel alpha hack -- see the shader's own
## fragment() history below) never lets a band's own worst-case blade
## visually reach the player's real body.
##
## PREVIOUSLY 8 (CHUNK_SIZE=32 tiles / 8 bands = 4 tiles/band = 64 world
## units). That was too coarse: a band's own worst-case blade (its root at
## the far/top edge of an in-front band, its card then reaching another
## WORLD_SIZE past that) could visually reach 64+16=80 world units above
## the player's own root -- comfortably past the player's own real max
## reach (42 world units, `character_view.tscn`'s HeadSlot offset) -- so it
## painted straight over the player's upper body/head. Reported live, with
## a real screenshot.
##
## THEN 32 (1 tile/band = 16 world units) -- fixed the "painted over the
## head" symptom, but left a real, honest residual: a band still draws in
## front of the player for as long as the player is anywhere within its own
## full tile (band_anchor_world_y's own bottom-edge anchoring, "normal,
## expected concealment" by design). At a whole tile per band, that grace
## window is barely perceptible on sparse, mostly-transparent blade art but
## reads as glaringly broken on the atlas's own dense, near-opaque "bush"
## cards -- reported live again, the same day: "y ordering is correct only
## for some [tufts]... should work like the lower one for all."
##
## Now 64 (half a tile/band = 8 world units): halves that grace window
## again, AND (a second real effect this specific change unlocks) is now
## fine enough that a card's own real per-card offset (up to 6.8 world
## units, see `cards_for_cell`) CAN cross a band boundary -- so the
## per-card banding fix landed just before this one actually starts doing
## something at today's real production ratio, not just at a synthetic
## test-only band_count. Worst-case reach: 8 (band_height) + 6.8 (max card
## offset) + 16 (WORLD_SIZE) = 30.8, an 11.2-world-unit margin under the
## player's real 42 -- a real, tested (see
## test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach)
## and comfortable margin again. Another deliberate, honest draw-call cost
## for grass specifically (32 -> 64 per chunk, 8x the original pre-fix
## count of 8) -- correctness over raw draw-call count, the same reasoning
## every prior pass on this exact bug already used.
const BAND_COUNT := 64

## Bend profile: how far a pixel row is displaced, as a function of
## top_t (0 at the root, 1 at the tip). A straight vertex shear only ever
## produces a linear ramp (a flat parallelogram); an exponent above 1
## instead eases in, so the root barely moves while curvature - and
## displacement - concentrates near the tip, the way a real blade bends
## under wind load.
const BEND_CURVE_EXPONENT := 1.6
## Radians of wind-phase spread across a card's full UV.x width, so blades
## drawn side by side in the same tuft sway with a different timing instead
## of shearing the whole card as one rigid shape.
const PHASE_SPREAD := 2.4
## amplitude_scale(uv_x) = AMPLITUDE_BASE + AMPLITUDE_VARIATION * sin(...):
## kept strictly positive so no column of blades ever goes fully still.
const AMPLITUDE_BASE := 0.8
const AMPLITUDE_VARIATION := 0.2
const AMPLITUDE_FREQUENCY := 6.0
## Peak UV-space displacement (fraction of the card's width) at full bend.
## A rendered-pixel probe showed a small shift reads clearly against a
## sparse single-blade card (its moving silhouette edge is high-contrast)
## but is nearly invisible against a dense, busy bush card (a small shift
## of repetitive texture still looks like the same texture) even though the
## sampled pixels do change - reported live as "bigger bushes don't part".
## Both amplitudes are sized for the busier case.
const WIND_UV_AMPLITUDE := 0.09

## How far a walker may lay a blade over at the very hardest -- the tuned
## value for the walker's own push, expressed as the ANGLE it actually is
## now that the bend is a rotation (see bent_vertex).
##
## It used to be 1.5 CARD WIDTHS, climbed there across several live rounds
## (History #6) while the bend was still a UV slide that CLIPPED: past one
## card width, more amplitude bought more of the blade erased rather than
## more lean, so "more" kept reading as "still not enough". Against a
## rotation the same number says something else entirely -- 1.0 at the tip IS
## flat on the ground, and 1.5 is flat with room to spare, so every tuft a
## player walked past slammed flat and sprang back up behind them. Reported:
## "reduce the intensity of the bend... it feels wobbly as you walk through."
##
## Tuned to a real thing rather than a feeling, after 35 degrees read as
## "now the grassblades don't part enough they should visible part about the
## width of the char": a walker parts the grass by THEIR OWN WIDTH. The
## character's body is 26px at CharacterView's own computed SCALE, 12.45
## world units against a 16-unit card, and the lean whose tip travels that
## far is asin(12.45 / 16) = 51.1 degrees. At 35 a tip moved 9.2 units --
## three quarters of a character, which is what "not enough" was.
##
## Pinned from both sides: test_a_walker_parts_the_grass_by_about_their_own_
## width computes the character's real width and asserts the tip reaches it
## (so a change to the character's size fails here rather than drifting),
## and test_a_walkers_push_leans_a_blade_over_without_laying_it_flat holds
## it clear of both ends -- never flat, never subtle.
const MAX_WALKER_LEAN_DEGREES := 51.1

## The displacement that reaches that lean -- sin of it, which is exactly
## what bent_vertex takes asin of to get the angle back. Derived rather than
## kept as a second number beside the angle, so the two cannot drift
## (test_the_push_amplitude_is_that_lean_and_not_a_number_of_its_own).
## A `static var` for the same reason NpcCondition's derived rates are: a
## const initializer cannot call a function.
static var WALKER_PUSH_UV_AMPLITUDE: float = sin(deg_to_rad(MAX_WALKER_LEAN_DEGREES))

## How finely a card's own quad is cut up so its GEOMETRY can follow the bend
## curve. `mesh()` feeds these straight to QuadMesh's own subdivide_width/
## subdivide_depth (PlaneMesh calls a quad's vertical axis "depth"), giving
## (WIDTH + 1) x (DEPTH + 1) = 4 x 8 cells, 45 vertices and 64 triangles per
## card.
##
## Why subdivide at all: the bend is applied to VERTEX.x in the shader's own
## vertex() (see _build_shader_code), because that is the only stage that can
## actually MOVE a blade -- and an undivided quad has only its own four
## corners to move, which can express nothing but the flat parallelogram
## shear docs/concept/long_grass.md's History #1 already rejected. Every
## vertex ROW here instead sits on the real eased-in curve, and every vertex
## COLUMN carries its own wind phase/amplitude, so the per-blade path-tracing
## survives the move from the sampling stage to the geometry.
##
## Why THESE numbers: what the mesh cannot represent between its own vertices
## falls back to the sampling stage, which is the only stage that can slide
## art past a card's edge and clip it (History "Where a bent blade actually
## goes"). Measured across the real worst case (storm wind, a walker standing
## on the card) that leftover is ~0.02 card widths -- about 1.3 screen px at
## the shipped 64-px-wide card -- versus the 1.66 CARD WIDTHS (106 px) the
## sampling stage used to carry on its own. Height gets more resolution than
## width because the eased-in curve runs UP a blade while the wind's own
## spread across a card is much gentler. Finer still is available but not
## free: 4 x 8 keeps a cell at ~16 x 8 screen px, comfortably above the ~4x4
## floor where small triangles start wasting whole rasterizer quads, and
## fill rate itself is unchanged either way (a sheared quad covers the same
## area it did upright). Pinned by
## test_bending_never_slides_a_blade_further_sideways_than_its_own_card_can_show
## and test_the_bend_mesh_is_subdivided_so_its_geometry_can_follow_the_curve.
const BEND_MESH_SUBDIVIDE_WIDTH := 3
const BEND_MESH_SUBDIVIDE_DEPTH := 7

## The shader's own wind_strength default: calibrated to
## WeatherModel.wind_strength_for("clear") == 1.0 (see weather_model.gd), the
## majority weather state (CLEAR_THRESHOLD), so WIND_UV_AMPLITUDE above stays
## exactly today's tuned look until a live value is pushed in via
## set_wind_strength (see EarthChunkManager.set_wind_strength). Deliberately
## does NOT scale WALKER_PUSH_UV_AMPLITUDE -- parting is the walker's own
## reaction, not ambient wind, and must not go weaker on a calm day.
const DEFAULT_WIND_STRENGTH := 1.0

static var SHADER_CODE: String = _build_shader_code()

static func bend_curve(top_t: float) -> float:
	return pow(clampf(top_t, 0.0, 1.0), BEND_CURVE_EXPONENT)

static func blade_phase(uv_x: float) -> float:
	return uv_x * PHASE_SPREAD

static func blade_amplitude_scale(uv_x: float) -> float:
	return AMPLITUDE_BASE + AMPLITUDE_VARIATION * sin(uv_x * AMPLITUDE_FREQUENCY)

## The shader's own bend_offset_at(), mirrored in GDScript so the split
## between what the MESH carries and what the SAMPLING stage is left with can
## be measured headlessly (the renderer under --headless is a null one, so
## the GLSL itself can only be compiled, never sampled -- see fill_band).
## Returns the horizontal displacement at one point on a card, in CARD
## WIDTHS, exactly as the shader computes it.
##
## `wind_phase` collapses the shader's own `TIME * wind_speed + root.x *
## 0.071 + root.y * 0.043` into one scalar: every term in it is constant
## across a single card, so a caller sweeping wind_phase over [0, TAU) covers
## every moment and every root position at once. `push` is likewise the
## shader's own `away.x * wake * WALKER_PUSH_UV_AMPLITUDE`, constant per card
## and bounded by +/-WALKER_PUSH_UV_AMPLITUDE.
static func bend_offset(uv: Vector2, wind_phase: float, push: float, wind_strength: float = DEFAULT_WIND_STRENGTH) -> float:
	var wind: float = sin(wind_phase + blade_phase(uv.x)) * WIND_UV_AMPLITUDE * wind_strength * blade_amplitude_scale(uv.x)
	return (wind + push) * bend_curve(uv.y)


## How much of that displacement the card's own GEOMETRY carries at `uv`:
## the mesh evaluates the exact curve at each of its own vertices (the shader
## displaces VERTEX.x by it) and the rasterizer interpolates between them, so
## this is bend_offset interpolated across whichever mesh cell `uv` falls in.
##
## Modelled BILINEARLY, while a GPU splits each cell into two triangles and
## interpolates each affinely -- the two differ by at most a quarter of that
## cell's own twist term (the bilinear uv coefficient), which is small enough
## here to add as an explicit correction where it matters rather than hide:
## see test_bending_never_slides_a_blade_further_sideways_than_its_own_card_
## can_show, which measures the twist off this same function's own corners
## instead of assuming it away. Exact (not a model) at every vertex, which is
## what makes the residual below meaningful.
static func mesh_bend_offset(uv: Vector2, wind_phase: float, push: float, wind_strength: float = DEFAULT_WIND_STRENGTH) -> float:
	var columns := BEND_MESH_SUBDIVIDE_WIDTH + 1
	var rows := BEND_MESH_SUBDIVIDE_DEPTH + 1
	var scaled_u: float = clampf(uv.x, 0.0, 1.0) * float(columns)
	var scaled_v: float = clampf(uv.y, 0.0, 1.0) * float(rows)
	var column := mini(int(scaled_u), columns - 1)
	var row := mini(int(scaled_v), rows - 1)
	var along_u: float = scaled_u - float(column)
	var along_v: float = scaled_v - float(row)
	var left: float = float(column) / float(columns)
	var right: float = float(column + 1) / float(columns)
	var bottom: float = float(row) / float(rows)
	var top: float = float(row + 1) / float(rows)
	var lower: float = lerpf(
		bend_offset(Vector2(left, bottom), wind_phase, push, wind_strength),
		bend_offset(Vector2(right, bottom), wind_phase, push, wind_strength),
		along_u
	)
	var upper: float = lerpf(
		bend_offset(Vector2(left, top), wind_phase, push, wind_strength),
		bend_offset(Vector2(right, top), wind_phase, push, wind_strength),
		along_u
	)
	return lerpf(lower, upper, along_v)


## Where one of a card's own mesh vertices actually lands once the bend has
## moved it -- the shader's vertex() stage mirrored in GDScript so the
## geometry can be measured headlessly. `local_position` is the vertex in the
## mesh's own local space (root at y=0, tip at y=-WORLD_SIZE, x across the
## card) and `bend_offset` is that point's displacement in CARD WIDTHS.
##
## The whole card ROTATES about its own root; nothing is displaced along a
## line. This took two live reports to get right, and both were the same
## error measured against a different reference point:
##
## 1. "The grassblades elongate and stretch instead of only bending."
##    Displacing VERTEX.x alone is a SHEAR -- every row keeps the height it
##    started at, so a tip pushed 26 world units sideways while staying 16 up
##    draws a 31-unit blade where a 16-unit one is planted.
## 2. "But it's still super elongated", with a screenshot. That first fix
##    held each vertex's own HEIGHT fixed, which rotates every COLUMN of the
##    card about the point directly beneath it. Right for a blade drawn
##    straight up one column; wrong for the art this atlas actually holds, a
##    fan of long leaves radiating DIAGONALLY from the tuft's base. A leaf
##    from the root to the top corner is 17.9 units long, and with its far
##    end swinging sideways while its base stayed put it drew up to 24 --
##    dragged out sideways, exactly what the screenshot showed.
##
## What has to stay fixed is every point's distance from THE CARD'S OWN ROOT
## (the local origin, the bottom centre the instance is planted at), and a
## rotation about that root gives exactly that -- for every point at once, in
## every column, whichever direction the art drew its leaves in.
##
## The lean is taken as an ANGLE from the same tuned displacement everything
## else here is expressed in: asin(sideways / radius) is the rotation that
## puts a point on the card's centre line the intended distance across.
## Clamping that ratio to +/-1 before the asin is what stops a blade bending
## past flat -- as far as a blade goes -- and keeps the angle real.
##
## HONEST about the model: a real blade bends into a curve, its tip ending
## slightly nearer the root than a rigid rotation puts it. This is the
## standard cheap billboard bend; the property that was wrong twice over --
## a blade drawing longer than it is -- is exact here.
static func bent_vertex(local_position: Vector2, bend_offset: float) -> Vector2:
	var radius: float = local_position.length()
	if radius < 0.0001:
		return local_position  # the root itself, which never moves
	# The lean that puts a point on the card's own centre line exactly the
	# intended distance sideways -- so every amplitude above still means what
	# its own test says -- applied as a rotation to every point, whatever
	# column it sits in.
	var lean: float = asin(clampf(bend_offset * WORLD_SIZE / radius, -1.0, 1.0))
	# Clamped at the horizon, per POINT rather than per card: a leaf already
	# pointing up and to the side starts at a real angle from upright, so it
	# reaches flat before the ones above it and would carry on past, swinging
	# below the ground its own roots stand on and folding the card under
	# itself. A blade lies flat; it does not grow into the ground.
	var from_upright: float = clampf(
		atan2(local_position.x, -local_position.y) + lean, -PI * 0.5, PI * 0.5
	)
	return Vector2(radius * sin(from_upright), -radius * cos(from_upright))


## What is left for the SAMPLING stage once the geometry has moved: the exact
## curve minus what the mesh actually carried (the shader's fragment() does
## precisely this subtraction, reading the geometry's own interpolated
## displacement back out of a varying). The two add up to the exact curve at
## every pixel, so path-tracing per pixel row is preserved -- but only this
## remainder can slide art sideways INSIDE a card that is not moving with it,
## so only this remainder can run a blade off its own region edge and be
## discarded (the edge-smear guard in fragment()). That makes it the number
## worth bounding, and it is: see BEND_MESH_SUBDIVIDE_WIDTH's own doc comment
## for the measured worst case.
static func sampled_bend_offset(uv: Vector2, wind_phase: float, push: float, wind_strength: float = DEFAULT_WIND_STRENGTH) -> float:
	return bend_offset(uv, wind_phase, push, wind_strength) - mesh_bend_offset(uv, wind_phase, push, wind_strength)


## Which Y-band (0..BAND_COUNT-1) a row at `local_y` (within its own chunk,
## 0..chunk_size-1) belongs to. `local_y` is `float`, not `int`: a CELL's
## own raw row is always a whole number, but a CARD's real, offset-adjusted
## position (see `cards_for_cell`/`local_row_for_world_y`) is not -- one
## fractional function serves both cell-level and card-level callers (a
## plain `int` widens to `float` automatically at any existing call site).
static func band_index_for_local_y(local_y: float, chunk_size: int, band_count: int = BAND_COUNT) -> int:
	if chunk_size <= 0 or band_count <= 0:
		return 0
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	return clampi(int(local_y / band_height), 0, band_count - 1)


## The chunk-local row-equivalent (the same fractional units `cell.y`
## already lives in) of a real world Y -- the inverse of how a cell's own
## `ground_position` is built (`(tile.y + 0.5) * tile_size`, where
## `tile.y = chunk_origin_y + local_y`). Lets a CARD's real world Y (its
## cell's ground position plus its own random offset -- see
## `cards_for_cell`) be converted back into that same coordinate space and
## handed to `band_index_for_local_y`, for genuine per-card banding instead
## of the cell's own un-offset raw row.
static func local_row_for_world_y(world_y: float, chunk_origin_y: int, tile_size: float) -> float:
	return world_y / tile_size - float(chunk_origin_y)

## The world Y a band's MultiMeshInstance2D should sit at for Y-sorting --
## the band's own BOTTOM edge (its largest row's world Y), not its vertical
## center. A single draw call can only Y-sort as ONE unit (see BAND_COUNT's
## own doc comment), and a center anchor left every row in a band's lower
## half sitting BELOW (a larger world Y than) the anchor -- so a player
## standing on one of those rows, having already walked past every blade in
## the band's upper half, still Y-sorted BEHIND the whole band. Since a
## blade card renders upward from its own root and is a full tile tall (see
## `mesh()`'s WORLD_SIZE), that read as exactly the reported bug: "the
## player's head is behind the long grass blades when the feet already are
## past it." Anchoring at the bottom edge instead means any entity standing
## anywhere within or above the band always sorts behind the whole band
## (grass draws in front while you're walking through it -- normal,
## expected concealment, see docs/concept/combat.md), and the band only
## pops behind the entity once genuinely past its very last row. Trades
## "occasionally covered a beat longer than a single blade's own root would
## justify" for "never shows a body part behind grass it has unambiguously
## already passed" -- pinned by
## test_band_anchor_world_y_is_never_smaller_than_any_row_actually_in_that_band.
static func band_anchor_world_y(band_index: int, chunk_origin_y: int, chunk_size: int, tile_size: float, band_count: int = BAND_COUNT) -> float:
	var band_height: float = maxf(float(chunk_size) / float(band_count), 0.0001)
	var local_y_bottom: float = (float(band_index) + 1.0) * band_height
	return (float(chunk_origin_y) + local_y_bottom) * tile_size

static func _build_shader_code() -> String:
	return """
shader_type canvas_item;
uniform vec2 player_world_position = vec2(-100000.0);
uniform float walker_radius = 22.0;
uniform float wind_speed = 1.6;
// Live wind conditions (see WeatherModel.wind_strength_for, forwarded via
// EarthChunkManager.set_wind_strength) -- WIND_UV_AMPLITUDE is the BASE
// ambient sway at wind_strength == 1.0 ("clear"), scaled up in rougher
// weather and down in none. Deliberately does NOT touch the walker-push
// term below (see `push`): parting is the walker's own reaction, not wind.
uniform float wind_strength = 1.0;
// The season's multiplier on living green (see SeasonalFoliage, forwarded via
// EarthChunkManager.set_season_tint) -- the same value the terrain layer
// under these blades wears, so a field and the ground it stands in turn
// together instead of a green lawn showing through straw-coloured grass.
// Identity by default, so a caller that never pushes a season renders exactly
// today's high-summer picture.
uniform vec3 season_tint = vec3(1.0);

varying vec2 v_root;
// Per-card atlas sub-rect (normalized), packed into MultiMesh's dedicated
// per-instance custom-data channel on the CPU side. NOT `instance uniform`
// (see docs/concept/long_grass.md: that draws from one global, hardware-
// capped buffer shared by the whole scene). Also NOT plain per-instance
// COLOR read directly in fragment(): under this project's gl_compatibility
// renderer, that produced a dithered/checkerboard mix of neighboring
// instances' data instead of a clean per-instance constant - reading
// INSTANCE_CUSTOM in vertex() and carrying it via varying is the path that
// actually renders cleanly (verified with a real render: raw COLOR read in
// fragment gave visible speckle noise even with zero bend math involved;
// INSTANCE_CUSTOM via a varying gave a clean, solid, correct sample).
varying vec4 v_region;
// How far this card's own geometry was ACTUALLY displaced at this point, in
// card widths -- written in vertex() right where it moves VERTEX.x, so the
// rasterizer interpolates it between vertices exactly the way it interpolates
// the displaced vertices themselves. fragment() subtracts it from the exact
// curve and sample-shifts only the remainder, so the two stages add up to the
// bend instead of both applying it.
varying float v_geometry_bend;

// ONE bend formula, read by BOTH stages -- vertex() to move the geometry,
// fragment() to resolve whatever the mesh could not carry, per pixel. A
// single seam, so the two can never drift into disagreeing about where a
// blade is (the same reasoning cards_for_cell uses for banding-vs-placement).
// `blade_uv` is the card's own local UV (root at y=0, tip at y=1) and `root`
// its instance origin in world space: a global function cannot read either
// stage's own built-ins, so each stage passes its own.
float bend_offset_at(vec2 blade_uv, vec2 root) {
	// Path-trace the blade along a curve rather than a straight shear: the
	// exponent is above 1, so this eases in -- the root stays essentially
	// pinned and displacement concentrates near the tip, the way a real blade
	// bends under wind load. Phase and amplitude both vary with blade_uv.x,
	// so blades drawn side by side within one card sway with different timing
	// instead of moving as one rigid shape.
	float bend = pow(clamp(blade_uv.y, 0.0, 1.0), %s);
	float phase = blade_uv.x * %s;
	float amplitude_scale = %s + %s * sin(blade_uv.x * %s);

	vec2 from_walker = root - player_world_position;
	float distance_to_walker = length(from_walker);
	vec2 away = from_walker / max(distance_to_walker, 0.001);
	float wake = 1.0 - smoothstep(0.0, walker_radius, distance_to_walker);

	float wind = sin(TIME * wind_speed + root.x * 0.071 + root.y * 0.043 + phase) * %s * wind_strength * amplitude_scale;
	float push = away.x * wake * %s;
	return (wind + push) * bend;
}

void vertex() {
	// A card's ROOT, in world space: read off the local origin (this
	// instance's own transform origin - MultiMesh folds per-instance
	// transforms into MODEL_MATRIX per draw) rather than off VERTEX, so it
	// keeps naming the card's own ground position even now that VERTEX
	// itself moves with the bend below.
	v_root = (MODEL_MATRIX * vec4(vec2(0.0), 0.0, 1.0)).xy;
	v_region = INSTANCE_CUSTOM;

	// The bend happens HERE, to real geometry, because a bent blade has to
	// have somewhere to go: displacing the SAMPLED column instead slides art
	// around inside a quad that never moves, so the quad's own edge cuts the
	// blade off (reported live: "the long grass blades are clipped on the
	// left and right when they bend"). Roots still never translate --
	// bend_offset_at is exactly 0 at blade_uv.y == 0, so this quad's own
	// bottom row of vertices stays put however hard the tip leans. Converted
	// from card widths into the mesh's own local units (its instance
	// transform is a pure translation, so local units ARE world units here).
	// The card ROTATES about its own root (its local origin, the bottom
	// centre it is planted at), so every point keeps its distance from that
	// root and no leaf can draw longer than it is, whichever direction the
	// art drew it in. Displacing x alone shears the card and stretches every
	// blade; holding each COLUMN's own height instead stretches the diagonal
	// leaves this atlas is full of. Both were reported live, in that order.
	// Mirrored exactly by bent_vertex() in illustrated_grass_patch.gd, which
	// is where it is measured, since a shader cannot be.
	v_geometry_bend = bend_offset_at(UV, v_root);
	float radius = length(VERTEX);
	if (radius > 0.0001) {
		float lean = asin(clamp(v_geometry_bend * %s / radius, -1.0, 1.0));
		// Clamped at the horizon per POINT: a leaf that already points up and
		// to the side reaches flat before the ones above it, and would carry
		// on below the ground its roots stand on, folding the card under
		// itself. A blade lies flat; it does not grow into the ground.
		float from_upright = clamp(
			atan(VERTEX.x, -VERTEX.y) + lean, -radians(90.0), radians(90.0)
		);
		VERTEX = vec2(radius * sin(from_upright), -radius * cos(from_upright));
	}
}

void fragment() {
	// UV is the shared quad's own local 0..1 (root at UV.y=0, tip at
	// UV.y=1 - verified empirically for QuadMesh + MultiMeshInstance2D's
	// TRANSFORM_2D; this differs from a region-mapped Sprite2D's UV, which
	// is atlas-relative). This card's own atlas sub-rect arrives packed
	// into v_region (region_uv0 in r,g and region_uv1 in b,a).
	vec2 region_uv0 = v_region.rg;
	vec2 region_uv1 = v_region.ba;
	vec2 region_size = max(region_uv1 - region_uv0, vec2(0.0001));

	// Whatever the mesh's own vertices could NOT represent of the curve: the
	// exact displacement at this pixel, minus the interpolated one the
	// geometry already applied (v_geometry_bend). Resolving that remainder
	// per pixel row keeps the total exactly on the curve at every fragment,
	// not just at a vertex -- while leaving the sampling stage a sliver
	// (measured: ~0.02 card widths, about 1.3 screen px, at storm wind with a
	// walker standing on the card) instead of the whole 1.66-card-width bend
	// it used to slide on its own, which is what ran blades clean off their
	// own card edge. See sampled_bend_offset.
	float bend_offset = bend_offset_at(UV, v_root) - v_geometry_bend;

	// Sample-space Y is flipped relative to mesh-space UV.y (the atlas art
	// is authored root-at-bottom-of-cell/tip-at-top, but mesh UV.y=0 is the
	// root) - see illustrated_grass_patch.gd's band_index_for_local_y-
	// adjacent comment trail for the empirical verification.
	float raw_local_x = UV.x - bend_offset;
	float local_x = clamp(raw_local_x, 0.0, 1.0);
	vec2 atlas_uv = region_uv0 + vec2(local_x, 1.0 - UV.y) * region_size;

	// SUPERSEDED (2026-08-26): a blade whose own root the player has already
	// walked past used to fade to transparent here instead of being
	// properly occluded (a per-pixel alpha hack standing in for real
	// Y-sort, reusing walker_radius from the unrelated push effect above).
	// That both under-corrected (a blade more than walker_radius behind the
	// player never faded, so it kept drawing solid on top of the player's
	// upper body/head) and over-corrected (any blade within walker_radius
	// faded to fully invisible just from the player standing near it,
	// reported separately as "grass becomes transparent when walking over
	// it") -- two symptoms of the same wrong mechanism. BAND_COUNT is now
	// fine-grained enough (see its own doc comment) that native Y-sort
	// alone -- the same mechanism every ordinary Sprite2D already uses --
	// places each band in the correct draw order without any alpha
	// modulation: grass is either genuinely behind the player (drawn
	// first, correctly covered) or genuinely in front (drawn after,
	// correctly covering), always fully opaque either way.
	COLOR = texture(TEXTURE, atlas_uv);
	// At extreme bend, raw_local_x can run past [0,1] for many consecutive
	// fragments at once -- local_x's own clamp keeps the SAMPLE safely
	// in-bounds, but everything past the true edge would otherwise repeat
	// whatever single edge pixel the clamp landed on, stretching it into a
	// visible smear (reported live: "all seasons except summer produce
	// artifacts when parting" -- three of the four delivered sheets have a
	// real, non-transparent pixel sitting exactly at that edge; see this
	// shader's own history/test for the measurement). A fragment whose true,
	// unclamped position has bent past its own region's edge shows nothing
	// instead of that stretched pixel -- not a proximity-based fade (see the
	// SUPERSEDED note above): it fires identically for ambient wind alone,
	// with no player nearby, and never reduces opacity anywhere the bend
	// actually stays in-bounds.
	if (raw_local_x < 0.0 || raw_local_x > 1.0) {
		COLOR.a = 0.0;
	}
	// Gated on greenness for the same reason GroundTint is, and with the same
	// gain: the illustrated atlas already carries dry/brown blades, and those
	// must not be turned again by a season they are already wearing.
	float greenness = clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0);
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * season_tint, greenness);
}
""" % [BEND_CURVE_EXPONENT, PHASE_SPREAD, AMPLITUDE_BASE, AMPLITUDE_VARIATION, AMPLITUDE_FREQUENCY, WIND_UV_AMPLITUDE, WALKER_PUSH_UV_AMPLITUDE, WORLD_SIZE, SeasonalFoliage.GREENNESS_GAIN]

var _material: ShaderMaterial
## Lazily-loaded, cached per season (see SEASON_ATLAS_PATHS) -- replaces a
## single shared `_texture` now that there are four sheets to choose between.
var _textures: Dictionary = {}
var _mesh: QuadMesh
## Last live wind strength pushed in (see set_wind_strength) -- applied to
## material() at BUILD time too, so a caller that sets the live wind before
## the material has been lazily built yet doesn't lose it.
var _wind_strength := DEFAULT_WIND_STRENGTH
## Last season tint pushed in (see set_season_tint) -- applied in material()
## at BUILD time too, so a caller that sets the season before the material has
## been lazily built doesn't lose it (same reasoning as _wind_strength above).
var _season_tint := Color(1.0, 1.0, 1.0)

## Some of the delivered sheets' taller "bush"/wheat-ear variants (the
## denser rows) draw their own plant art past their own cell's nominal
## bottom edge, bleeding into the TOP of the next row down -- a real
## property of the sheets themselves, not a rendering bug: a mechanically-
## sliced region with no inset hands a recipient card a fragment of the row
## ABOVE's plant sitting right at its own top edge. Because the shader flips
## root-at-bottom/tip-at-top (a card's local Y=0 is the ground, growing up),
## that fragment renders at the TIP -- the point farthest from the ground --
## genuinely detached from the card's own body by a real transparent gap.
## Reported live: "the grass now has floating artefacts above it" (snow gave
## the white background enough contrast to show it clearly, but the bleed
## itself is independent of snow).
##
## MEASURED, not eyeballed, against each real shipped sheet at its native
## 1254x1254 resolution, using the EXACT integer arithmetic atlas_region_
## for's own from/to computation uses (row * atlas_size.y / ATLAS_ROWS
## truncates, it does not round -- measuring with float rounding instead
## gives a subtly different, wrong nominal_top and was the source of a whole
## false trail of apparent cross-season mismatches before this was caught).
## Summer alone reproduces the table this was originally measured against
## pixel-for-pixel (`grass_blades.png`, now shipped as `grass_blades_summer.
## png`'s own pixels -- see docs/concept/long_grass.md), which is itself a
## real check that this measurement methodology is correct.
##
## PER-SEASON, not one table shared across all four: rows 0-5's own values
## are identical across every season (copied verbatim from the single shared
## table this superseded, not re-measured -- a shared value already covers
## them cleanly, so re-measuring them per season was out of scope for the
## investigation that split this table), but rows 6-9 (the four densest
## rows) measurably do NOT converge on one shared value -- the least-bled
## season's own real minimum sits well under the most-bled season's, so a
## single number either under-crops the worst season (real donor bleed still
## shows) or over-crops the best one (destroying real art that needed little
## or no inset). Splitting this by season lets each sheet use its OWN real
## minimum instead of the worst case across all four.
##
## Verified against all four real sheets by
## test_atlas_region_for_never_includes_the_previous_rows_bled_over_content_
## on_any_season_sheet, with exactly ONE remaining exception: winter's own
## row 9, whose art fills nearly its entire cell height (confirmed with a
## direct visual crop, not just measured) -- no inset, however large, lands
## its region's own top edge in a genuinely transparent zone across every
## column without cropping the row to a sliver. winter[9] below (12px) is
## still the real, measured BEST available value (a substantial improvement
## over the old shared table's 30px -- see
## test_winter_row_9_bleed_is_narrowed_but_not_fully_closed_by_the_per_
## season_table), just genuinely short of the 90% bar the other 35 (season,
## row) combinations in 6-9 all clear. A known, narrowed gap (see
## docs/concept/long_grass.md's Status), not a bug in this function.
const ROW_TOP_BLEED_PX_BY_SEASON := {
	"spring": [0, 3, 6, 11, 16, 19, 20, 26, 27, 12],
	"summer": [0, 3, 6, 11, 16, 19, 15, 20, 23, 7],
	"autumn": [0, 3, 6, 11, 16, 19, 19, 22, 27, 10],
	"winter": [0, 3, 6, 11, 16, 19, 20, 25, 27, 12],
}

## The atlas cell for a card of the given growth stage and variant seed --
## see docs/concept/long_grass.md's "Seasonal art" for why these are two
## independent axes rather than one flat hash across all 100 cells: `growth`
## (0..1, from `TallGrass.get_growth`) selects the ROW, a real drawn growth
## stage from a bare shoot (row 0) to a full flowering clump (last row);
## `seed_value` selects the COLUMN, the same per-card visual-variant hash as
## before. Growth is clamped, not wrapped -- a card never cycles back to a
## shoot once past the last row, it just stays on it.
##
## `season` selects which of `ROW_TOP_BLEED_PX_BY_SEASON`'s own rows to
## inset by -- an unrecognized name falls back to DEFAULT_SEASON, mirroring
## `_texture_for`'s own fallback. Defaulting to DEFAULT_SEASON rather than a
## required argument keeps every existing call site (this file's own
## `instances_for_cards` included, when it isn't told a season either)
## behaving exactly as before.
static func atlas_region_for(seed_value: int, growth: float, atlas_size: Vector2i = DEFAULT_ATLAS_SIZE, season: String = DEFAULT_SEASON) -> Rect2i:
	var column := posmod(seed_value, ATLAS_COLUMNS)
	var row := clampi(int(clampf(growth, 0.0, 1.0) * ATLAS_ROWS), 0, ATLAS_ROWS - 1)
	var bleed_table: Array = ROW_TOP_BLEED_PX_BY_SEASON.get(season, ROW_TOP_BLEED_PX_BY_SEASON[DEFAULT_SEASON])
	# The bleed table above is measured in native pixels of the REAL
	# 1254x1254 sheet; expressed as a fraction of one cell's own height so a
	# caller passing a differently-sized atlas_size (e.g. a smaller test
	# fixture) still gets a proportionally correct inset rather than an
	# oversized or negative-height region.
	var native_cell_height := float(DEFAULT_ATLAS_SIZE.y) / float(ATLAS_ROWS)
	var bleed_fraction := float(bleed_table[row]) / native_cell_height
	var cell_height := float(atlas_size.y) / float(ATLAS_ROWS)
	var top_inset := int(round(bleed_fraction * cell_height))
	var from := Vector2i(column * atlas_size.x / ATLAS_COLUMNS, row * atlas_size.y / ATLAS_ROWS + top_inset)
	var to := Vector2i((column + 1) * atlas_size.x / ATLAS_COLUMNS, (row + 1) * atlas_size.y / ATLAS_ROWS)
	return Rect2i(from, to - from)

## Offsets used to cluster into a small sub-region (±3.3 x ±1.4 world units)
## hugging the tile's own center - visually one clump sitting somewhere on
## the tile rather than grass filling its whole footprint (reported live:
## "make grass blades volumetric... more than one entity spawns on the same
## tile not only at bottom corner"). 21x17 buckets spread the root across
## most of WORLD_SIZE (±6.8, comfortably inside the ±8 tile-bounds half) on
## both axes independently, so cards read as filling the tile rather than
## clumping in one corner of it - see test_card_offsets_spread_across_most_
## of_a_full_tile_not_a_small_corner / ..._stay_within_the_tiles_own_bounds.
static func card_specs_for_seed(seed_value: int) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for index in CARD_COUNT:
		var h := hash("%d_grass_card_%d" % [seed_value, index])
		var offset := Vector2(float(posmod(h, 21) - 10) * 0.68, float(posmod(h / 21, 17) - 8) * 0.85)
		specs.append({"seed": h, "offset": offset, "depth": CARD_COUNT - index})
	return specs


## Large, arbitrary odd ints mixed into a card's own atlas_seed BEFORE
## hashing, one per independent threshold this file derives from that same
## seed -- see turn_threshold_for_seed's own doc comment for why a plain
## string-salted re-hash (the previous approach) is not enough on its own.
## Two DIFFERENT constants, not one reused: mixing in the same salt for both
## thresholds would make them the same number, defeating the whole point of
## keeping a card's calendar-turn speed and its snow-overlay speed
## independent (see snow_overlay_threshold_for_seed's own doc comment).
const _TURN_THRESHOLD_SALT := 0x9E3779B1
const _SNOW_OVERLAY_THRESHOLD_SALT := 0x85EBCA77

## A stable [0, 1) pseudo-random threshold derived from a card's own atlas
## seed -- a SEPARATE hash from the one that already picks its column/variant
## (atlas_region_for), so the two never correlate: two cards sharing a column
## must still be free to turn at different points in a season transition, or
## every card in that column would turn in lockstep. Compared against
## SeasonTransition's shared, quantised progress (see split_cards_by_turn)
## to decide whether this ONE card has turned to the next season's sheet
## yet -- the same "one shared clock, many independently-timed units" shape
## ProceduralTreeSprite's per-pixel _sweep_rank turns a canopy with, at card
## granularity instead of per-pixel (see docs/concept/long_grass.md's
## "Seasonal art").
##
## Hashes atlas_seed as an INT (`hash(atlas_seed + salt)`), not a STRING
## (`hash("%d_..." % atlas_seed)`, the previous approach) -- a real bug,
## found and fixed the same day this doc comment was written: a cell's own
## CARD_COUNT cards all come from card_specs_for_seed's `hash("%d_grass_
## card_%d" % [seed_value, index])` for index 0..7, a shared prefix with
## only a single trailing digit varying, and Godot's String hash does NOT
## avalanche on that shape -- confirmed directly, it returned exactly
## `base+0, base+1, base+2, ... base+7`, a linear sequence, not a hash at
## all. Re-hashing that already-near-sequential atlas_seed through ANOTHER
## string built the same vulnerable way ("%d_grass_turn" % atlas_seed) does
## not recover independence either (confirmed the same way: also a near-
## constant step between consecutive cards). The practical effect: a cell's
## 8 real cards landed suspiciously close together and tended to cross any
## given progress threshold together, reading as a whole tuft ("entity")
## turning at once rather than blade by blade -- reported live: "The long
## grass sprites don't change season color per blade but instead per
## entity." `hash(int)` does not share this weakness (confirmed the same
## way: consecutive integers hash to wildly different, well-spread values) --
## see test_turn_threshold_for_seed_shows_real_per_cell_variance_not_a_
## suspiciously_narrow_band, which pins this against the REAL card-generation
## path (card_specs_for_seed/cards_for_cell), not arbitrary sequential seeds.
static func turn_threshold_for_seed(atlas_seed: int) -> float:
	return float(posmod(hash(atlas_seed + _TURN_THRESHOLD_SALT), 10000)) / 10000.0


## Splits `card_specs` (each {atlas_seed:int, position:Vector2, growth:float},
## see cards_for_cell) into {"from": [...], "to": [...]} by comparing each
## card's own turn_threshold_for_seed against `progress` -- a card samples
## the OLD season's sheet while progress is still below its own threshold,
## the NEW season's once progress reaches it. `progress <= 0.0` puts every
## card in "from" and `progress >= 1.0` puts every card in "to" without
## touching turn_threshold_for_seed at all, so a settled (non-transitioning)
## season -- the common case -- collapses to a single, cheap bucket. Cards
## are never dropped or duplicated: every input card lands in exactly one
## of the two returned arrays.
static func split_cards_by_turn(card_specs: Array, progress: float) -> Dictionary:
	var from: Array = []
	var to: Array = []
	if progress <= 0.0:
		from = card_specs.duplicate()
	elif progress >= 1.0:
		to = card_specs.duplicate()
	else:
		for card in card_specs:
			if turn_threshold_for_seed(card.atlas_seed) <= progress:
				to.append(card)
			else:
				from.append(card)
	return {"from": from, "to": to}


## The season a card's BASE render actually samples from -- see docs/concept/
## long_grass.md's "Winter's own sheet is a snow overlay, not a calendar
## destination": real dormant-season grass stands senescent (the same dried
## character `_autumn.png` already draws) for as long as the ground is bare,
## not uniformly frosted white the instant the calendar ticks into winter --
## the dedicated `grass_blades_winter.png` sheet is reserved for the snow-
## triggered overlay below, not the calendar's own default per-card look.
## Every OTHER season name (including one this function has never heard of)
## passes straight through unchanged -- this is not a validating/fallback
## function like `_texture_for`'s DEFAULT_SEASON substitution, it only ever
## special-cases the one literal string "winter".
static func base_render_season(season: String) -> String:
	if season == "winter":
		return "autumn"
	return season


## A stable [0, 1) pseudo-random threshold derived from a card's own atlas
## seed, for the snow-overlay split below -- mirrors `turn_threshold_for_seed`
## exactly but mixes in a DIFFERENT salt constant, so a card's calendar-turn
## speed and its snow-overlay speed never correlate (the same reasoning
## `turn_threshold_for_seed`'s own doc comment gives for staying independent
## of the seed/column hash: two conceptually unrelated mechanisms sharing one
## hash would silently move in lockstep). Hashes atlas_seed as an INT, not a
## STRING, for the identical real-bug reason `turn_threshold_for_seed`'s own
## doc comment now documents in full -- this function had the exact same
## vulnerability (a shared-prefix, single-trailing-digit string salt that
## Godot's String hash does not avalanche on).
static func snow_overlay_threshold_for_seed(atlas_seed: int) -> float:
	return float(posmod(hash(atlas_seed + _SNOW_OVERLAY_THRESHOLD_SALT), 10000)) / 10000.0


## Splits `card_specs` into `{"base": [...], "winter": [...]}` by comparing
## each card's own `snow_overlay_threshold_for_seed` against `snow_depth`
## (`EarthChunkManager.snow_depth()` -- the identical live global scalar
## ground snow and canopy sparkle already read, not a new coverage concept;
## see docs/concept/snow_cover.md). Mirrors `split_cards_by_turn` exactly:
## `snow_depth <= 0` collapses to an all-"base" single bucket (every real-
## world case with no snow lying, the overwhelming common one, costs
## nothing), and a card that has caught snow stays caught as depth only
## climbs, never reverting mid-comparison.
static func split_cards_by_snow_overlay(card_specs: Array, snow_depth: float) -> Dictionary:
	var base: Array = []
	var winter: Array = []
	if snow_depth <= 0.0:
		base = card_specs.duplicate()
	elif snow_depth >= 1.0:
		winter = card_specs.duplicate()
	else:
		for card in card_specs:
			if snow_overlay_threshold_for_seed(card.atlas_seed) <= snow_depth:
				winter.append(card)
			else:
				base.append(card)
	return {"base": base, "winter": winter}


func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("wind_strength", _wind_strength)
		_material.set_shader_parameter("season_tint", _season_tint_vector())
	return _material

func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(WORLD_SIZE, WORLD_SIZE)
		# Shifts the quad so local (0,0) sits at its BOTTOM edge (root at
		# the ground, growing upward) - the MultiMesh analogue of Sprite2D's
		# offset=(0,-h/2) trick, empirically verified: a positive Y here
		# pushes the quad toward larger screen/world Y (down), so this
		# needs to be negative to grow up.
		_mesh.center_offset = Vector3(0.0, -WORLD_SIZE * 0.5, 0.0)
		# The bend moves this mesh's own vertices now (see the shader's
		# vertex()), so it needs vertices to move: four corners can only ever
		# shear flat, and everything they cannot express falls back to the
		# sampling stage, which is what used to clip bent blades off at a
		# card's edge. See BEND_MESH_SUBDIVIDE_WIDTH's own doc comment.
		_mesh.subdivide_width = BEND_MESH_SUBDIVIDE_WIDTH
		_mesh.subdivide_depth = BEND_MESH_SUBDIVIDE_DEPTH
	return _mesh

func set_walker_position(world_position: Vector2) -> void:
	material().set_shader_parameter("player_world_position", world_position)


## Pushes the live wind strength (see WeatherModel.wind_strength_for, via
## EarthChunkManager.set_wind_strength) onto the shared ambient-sway uniform
## -- see the shader's own wind_strength doc comment for why the walker-push
## term is deliberately left untouched.
func set_wind_strength(strength: float) -> void:
	_wind_strength = strength
	material().set_shader_parameter("wind_strength", strength)


## Pushes the season's tint on living green (see SeasonalFoliage, via
## EarthChunkManager.set_season_tint) onto the shared blade material.
## Deliberately does NOT touch growth or spread: this is what a field LOOKS
## like in November, not how fast it grows then (see docs/concept/seasons.md's
## still-open "seasonal scaling of vegetation growth rate" -- a rendering fix
## must not smuggle a sim change in with it).
func set_season_tint(tint: Color) -> void:
	_season_tint = tint
	material().set_shader_parameter("season_tint", _season_tint_vector())


func _season_tint_vector() -> Vector3:
	return Vector3(_season_tint.r, _season_tint.g, _season_tint.b)

## Expands ONE cell spec ({seed:int, ground_position:Vector2, growth:float})
## into its CARD_COUNT real per-card specs: {atlas_seed:int, position:
## Vector2, growth:float} -- each card's own real, offset-adjusted ground
## position (`ground_position + this card's own random offset`, see
## `card_specs_for_seed`). THE single seam for turning a cell into its
## cards -- both `EarthChunkManager`'s own Y-sort banding (which needs each
## card's own real position to bucket it correctly, via
## `local_row_for_world_y` -- see docs/concept/long_grass.md) and
## `instances_for_cards`' own final placement math read from here, so the
## two can never drift apart from each other.
static func cards_for_cell(cell_spec: Dictionary) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var ground_position: Vector2 = cell_spec.ground_position
	for spec in card_specs_for_seed(cell_spec.seed):
		cards.append({
			"atlas_seed": spec.seed,
			"position": ground_position + (spec.offset as Vector2),
			"growth": cell_spec.growth,
		})
	return cards

## Pure data prep for fill_band, headlessly testable on its own: computes
## every given CARD's instance transform (root pinned exactly at its own
## real position, regardless of growth scale) and packed atlas-region
## color, from plain per-card data only - no MultiMesh/Texture2D access.
## `card_specs` is an array of {atlas_seed:int, position:Vector2,
## growth:float}, one entry per CARD (see `cards_for_cell` -- the caller
## expands cells into cards and buckets them by real Y-sort band BEFORE
## calling this, so a cell whose own cards land in different bands can be
## split across separate calls without any card drawn twice or dropped).
## Sorted back-to-front by ground Y so overlapping alpha-blended cards
## within a band blend in roughly the right order.
##
## `season` forwards straight into `atlas_region_for` so its own per-season
## bleed inset (`ROW_TOP_BLEED_PX_BY_SEASON`) actually takes effect -- without
## this, that table could be as correct as it likes and never affect what a
## card actually samples, since this is the only place `atlas_region_for` is
## called from. Defaults to DEFAULT_SEASON so every existing caller/test that
## never mentions a season keeps behaving exactly as before.
static func instances_for_cards(card_specs: Array, band_anchor: Vector2, atlas_size: Vector2i, season: String = DEFAULT_SEASON) -> Array[Dictionary]:
	var flat: Array[Dictionary] = []
	for card_spec in card_specs:
		flat.append({
			"region": atlas_region_for(card_spec.atlas_seed, card_spec.growth, atlas_size, season),
			"position": card_spec.position,
		})
	flat.sort_custom(func(a, b): return a.position.y < b.position.y)

	var texture_size := Vector2(atlas_size)
	var instances: Array[Dictionary] = []
	for entry in flat:
		var region: Rect2i = entry.region
		var local_pos: Vector2 = entry.position - band_anchor
		var region_uv0 := Vector2(region.position) / texture_size
		var region_uv1 := Vector2(region.position + region.size) / texture_size
		instances.append({
			# Full, undamped size regardless of growth -- growth now picks
			# WHICH row's art is sampled (see atlas_region_for), so scaling
			# on top of that would double-damp an already-smaller-drawn
			# shoot. See docs/concept/long_grass.md's "Seasonal art".
			"transform": Transform2D(Vector2(1.0, 0.0), Vector2(0.0, 1.0), local_pos),
			"custom_data": Color(region_uv0.x, region_uv0.y, region_uv1.x, region_uv1.y),
		})
	return instances

## Only `grass_blades_summer.png` (the original shipped art) was ever
## authored with a real alpha channel -- the three new seasonal sheets
## (spring/autumn/winter) were delivered as plain opaque RGB, background and
## all (measured: Image.FORMAT_RGB8, corner/gutter pixels reading alpha=1.0
## uniformly). Loaded as-is, every card would render as a solid near-black
## rectangle instead of a cutout blade. BACKGROUND_KEY/BACKGROUND_KEY_
## TOLERANCE key that background out via SpriteSheetSlicer.chroma_keyed,
## which also upgrades the format to RGBA8 -- applied to every season
## uniformly (a no-op on a sheet already keyed to alpha=0, like summer's own
## background, so this never double-processes the one sheet that didn't need
## it). Tolerance measured against real sampled background pixels (up to
## ~0.012 per channel of compression noise around pure black); a visual
## check of the keyed result at this tolerance (spring/autumn/winter, saved
## and inspected directly) showed the background cleanly gone with no
## visible damage to the actual blade art.
const BACKGROUND_KEY := Color(0.0, 0.0, 0.0)
const BACKGROUND_KEY_TOLERANCE := 0.05

## Lazily loads and caches the atlas texture for one season, falling back to
## DEFAULT_SEASON for a name SEASON_ATLAS_PATHS doesn't recognise (mirrors
## SeasonalFoliage.tint_for_season's own fallback).
func _texture_for(season: String) -> Texture2D:
	if not _textures.has(season):
		var path: String = SEASON_ATLAS_PATHS.get(season, SEASON_ATLAS_PATHS[DEFAULT_SEASON])
		var image := SpriteSheetLoader.load_image(path)
		if image != null:
			image = SpriteSheetSlicer.chroma_keyed(image, BACKGROUND_KEY, BACKGROUND_KEY_TOLERANCE)
			_textures[season] = ImageTexture.create_from_image(image)
		else:
			_textures[season] = null
	return _textures[season]


## Rebuilds `mmi` (wiring its MultiMesh/material on first use if needed, and
## re-pointing its texture whenever `season` changes) so it renders every
## CARD in `card_specs` - each a {atlas_seed:int, position:Vector2,
## growth:float} (see `cards_for_cell`) - sampled from `season`'s own sheet,
## using that SAME season's own bleed inset for the region math too
## (forwarded into `instances_for_cards`, see its own doc comment) - not
## just which texture is bound.
##
## `band_anchor` must already be `mmi`'s own `position` (it drives this
## band's Y-sort key against the player/creatures); instance transforms are
## stored relative to it. Thin engine glue over instances_for_cards - see
## that function for the actual (headlessly-tested) placement math. This
## wrapper itself needs a real renderer to verify: MultiMesh per-instance
## transform/color storage is backed by the dummy renderer under
## `--headless` and silently doesn't round-trip there.
func fill_band(mmi: MultiMeshInstance2D, band_anchor: Vector2, card_specs: Array, season: String = DEFAULT_SEASON) -> void:
	var texture := _texture_for(season)
	if texture == null:
		push_error("Missing long-grass atlas for season '%s': %s" % [season, SEASON_ATLAS_PATHS.get(season)])
		return
	if mmi.multimesh == null:
		var new_mm := MultiMesh.new()
		new_mm.mesh = mesh()
		new_mm.transform_format = MultiMesh.TRANSFORM_2D
		new_mm.use_custom_data = true
		mmi.multimesh = new_mm
		mmi.material = material()
	mmi.texture = texture
	var mm: MultiMesh = mmi.multimesh
	var instances := instances_for_cards(card_specs, band_anchor, Vector2i(texture.get_size()), season)
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform_2d(i, instances[i].transform)
		mm.set_instance_custom_data(i, instances[i].custom_data)
