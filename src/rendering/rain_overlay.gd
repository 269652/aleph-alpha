extends RefCounted

const Snowfall = preload("res://src/world/snowfall.gd")

## Visible falling rain: pale, slanted streaks drawn over the world while it
## rains (see docs/concept/weather.md's presentation section).
##
## Rain used to exist only as a `rain_intensity` uniform driving water
## ripples plus a word in the HUD -- during a downpour, nothing actually fell
## anywhere on screen (reported: "it's raining but there are no visible
## raindrops falling"). Water reacting to rain it doesn't appear to be
## receiving reads as a bug, not as weather.
##
## Deliberately SCREEN-space, not world-space: rain falls everywhere at once,
## so there is nothing to anchor to a world position.
##
## Like WindSway, this runs entirely on the GPU off TIME -- no per-frame
## script and no particle nodes.
##
## ## Why the drops are geometry rather than a full-screen shader
##
## The first version was one screen-covering ColorRect whose fragment shader
## carved streaks out of it, on the reasoning that a full-screen rect "costs
## one draw call regardless of how heavy the downpour is". Draw calls were
## never the constraint. Measured on this machine's integrated GPU: hiding
## that one rect took the game from 42 fps to 57.7 and took the frame spikes
## with it. Vsync turns "just over 16.7ms" into a dropped frame, which is why
## rain read as heavy lag rather than as a slightly slower frame.
##
## The cost was not the shader. Replacing the fragment body with a bare
## `COLOR = vec4(0.0)` cost the same 15 fps; so did a plain untextured
## translucent ColorRect with no material at all; adding `discard` for the
## ~99% of pixels between streaks changed nothing. Shrinking the SAME shader
## to a 64x64 rect gave nearly all of it back. What the pass costs is the
## screen AREA it rasterises.
##
## So the overlay now rasterises only the streaks: one MultiMesh instance per
## drop, each a STREAK_WIDTH x STREAK_LENGTH quad, animated down the screen by
## the vertex shader off TIME. Still one draw call, still no per-frame script,
## covering a few percent of the screen instead of all of it.

## Streams are laid out per COLUMN: each column of the screen carries its own
## endless stream of drops with a hashed speed, spacing and phase, so drops
## don't fall in lockstep rows. Density scales by gating whole columns rather
## than by spawning more work, so a drizzle and a downpour cost the same.
const SHADER_CODE := """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float slant = 0.16;
uniform float column_width = 24.0;
uniform float columns = 54.0;
uniform float fall_span = 870.0;
uniform float fall_speed = 620.0;
uniform float drop_spacing = 150.0;
uniform float min_speed_factor = 0.8;
uniform float speed_factor_range = 0.4;
uniform vec4 drop_color : source_color = vec4(0.74, 0.85, 0.97, 0.5);

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	// Which stream this drop belongs to. Derived from INSTANCE_ID rather than
	// stored, because instance custom data is only 8 bits per channel in this
	// renderer (a readback of a raw pixel x came back as 0), so a screen
	// coordinate stored there would snap to a 5px grid. What IS stored is
	// only ever a 0..1 fraction, scaled back up here by a uniform.
	float column = mod(float(INSTANCE_ID), columns);
	float x = column * column_width - column_width + INSTANCE_CUSTOM.x * column_width;

	// Columns whose hash sits above the cut carry no rain at all, so
	// intensity scales smoothly from a drizzle to a downpour without
	// changing the amount of work done. A gated drop collapses to a point
	// rather than being drawn transparent -- a degenerate quad rasterises
	// nothing, which is the entire reason this is geometry.
	if (hash11(column) > intensity) {
		VERTEX = vec2(0.0);
	} else {
		float speed = fall_speed * (min_speed_factor + speed_factor_range * INSTANCE_CUSTOM.z);
		// Endless stream. TIME is ADDED and screen y grows downward, so drops
		// travel DOWN the screen; getting this sign backwards shipped rain
		// that fell upward once already, which is why drop_head_y pins the
		// direction as a tested property.
		//
		// The wrap depends only on the instance, not on the vertex, so all
		// four corners of a streak wrap on the same frame -- wrapping
		// per-vertex would stretch one streak across the screen each cycle.
		float y = mod(
			INSTANCE_CUSTOM.y * fall_span + TIME * speed + INSTANCE_CUSTOM.w * drop_spacing,
			fall_span
		);
		// Lean the stream so streaks fall at an angle: horizontal drift is
		// proportional to how far down the screen the drop is.
		VERTEX += vec2(x + y * slant, y);
	}
}

void fragment() {
	// No per-pixel work at all: the streak shape IS the quad.
	COLOR = drop_color;
}
"""

## The HUD's own CanvasLayer index (see world.tscn's UI node, which leaves
## `layer` at Godot's default of 1). Rain mounts strictly below it so a
## downpour never washes over the HUD.
const UI_CANVAS_LAYER := 1
const OVERLAY_CANVAS_LAYER := 0

## The viewport the drop field is laid out for (see project.godot's
## window/size -- the stretch mode is "viewport", so this is the real render
## resolution whatever the window is doing).
const DESIGN_WIDTH := 1280.0
const DESIGN_HEIGHT := 720.0

## Drop tuning. Pushed into the shader as uniforms rather than duplicated as
## shader literals, so these constants are the single source of truth and can
## be pinned by tests instead of eyeballed.
## Fall rate in screen pixels per second, and the spread of per-stream rates
## around it -- streams do not all fall at one rate.
const FALL_SPEED := 620.0
const MIN_SPEED_FACTOR := 0.8
const SPEED_FACTOR_RANGE := 0.4
## Horizontal drift per pixel fallen -- rain leans, it doesn't fly sideways.
const SLANT := 0.16
## How far apart the drop streams are across the screen.
const COLUMN_WIDTH := 24.0
## Vertical gap between successive drops within one stream.
const DROP_SPACING := 150.0
## A drop is a streak, not a dot: clearly longer than it is wide.
const STREAK_LENGTH := 11.0
## Chunky enough to read as pixel art rather than a hairline scratch (see
## docs/concept/pixel_art_engine.md).
const STREAK_WIDTH := 2.0
## Pale blue-white and translucent -- opaque drops would punch holes through
## the world behind them.
const DROP_COLOR := Color(0.74, 0.85, 0.97, 0.5)

## How far a drop falls before wrapping back to the top: the screen plus one
## drop spacing, so a streak leaves the bottom completely before it reappears
## at the top rather than popping out of existence at the last visible row.
const FALL_SPAN := DESIGN_HEIGHT + DROP_SPACING

var _shared_material: ShaderMaterial


## Streams across the screen. The extra column covers the lean: a slanted
## stream has to come from off the left edge to cover the bottom-left.
static func column_count() -> int:
	return int(ceil(DESIGN_WIDTH / COLUMN_WIDTH)) + 1


## Drops in flight per stream -- enough that as one leaves the bottom the
## next is already on screen, so a stream reads as continuous rain.
static func drops_per_column() -> int:
	return int(ceil(FALL_SPAN / DROP_SPACING))


static func instance_count() -> int:
	return column_count() * drops_per_column()


## Where drop `index` starts before TIME carries it down: its column's x, and
## its own slot in that column's stream. Deterministic and hash-scattered so
## two columns don't fall in step -- the same "the same individual always
## rolls the same" idiom the rest of the world sim uses.
static func placement_for(index: int) -> Vector2:
	var column := index % column_count()
	# Started one column-width left of the screen so the leaned stream still
	# covers the left edge on its way across. Mirrors the vertex shader's own
	# derivation from INSTANCE_ID exactly -- this is the specification of it.
	var x := float(column) * COLUMN_WIDTH - COLUMN_WIDTH + jitter_fraction_for(index) * COLUMN_WIDTH
	return Vector2(x, start_fraction_for(index) * FALL_SPAN)


## How far down its stream this drop starts, 0..1 of the fall span. Slots are
## spread evenly down the column and nudged per column so two streams do not
## fall in step.
static func start_fraction_for(index: int) -> float:
	var column := index % column_count()
	var slot := index / column_count()
	var offset := float(slot) * DROP_SPACING + _hash01(column * 41 + 3) * DROP_SPACING
	return fposmod(offset, FALL_SPAN) / FALL_SPAN


## This column's fall speed.
static func speed_for(index: int) -> float:
	return FALL_SPEED * (MIN_SPEED_FACTOR + SPEED_FACTOR_RANGE * speed_fraction_for(index))


## The 0..1 form of speed_for, which is what actually reaches the GPU: instance
## custom data is 8 bits per channel here, so everything stored in it is a
## fraction scaled back up by a uniform in the shader.
static func speed_fraction_for(index: int) -> float:
	return _hash01((index % column_count()) * 17 + 11)


## Where in its column this drop sits, 0..1 across the column's width.
static func jitter_fraction_for(index: int) -> float:
	return _hash01((index % column_count()) * 73 + 5)


## This drop's own offset down its stream, 0..1 of one drop spacing.
static func phase_fraction_for(index: int) -> float:
	return _hash01(index * 31 + 7)


static func drop_mesh_size() -> Vector2:
	return Vector2(STREAK_WIDTH, STREAK_LENGTH)


static func _hash01(value: int) -> float:
	return float(absi(hash(value)) % 10000) / 10000.0


## Screen-space y of a drop's head at `time_seconds`, mirroring the vertex
## shader's wrap (the drop travels down and wraps at the fall span).
##
## Exists so fall DIRECTION is a tested property rather than something only
## visible by eye: screen y grows downward, so this must INCREASE with time.
## Getting the sign backwards shipped rain that fell upward.
static func drop_head_y(
	time_seconds: float, speed: float = FALL_SPEED, spacing: float = DROP_SPACING
) -> float:
	return fposmod(time_seconds * speed, spacing)


func make_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("slant", SLANT)
	material.set_shader_parameter("column_width", COLUMN_WIDTH)
	material.set_shader_parameter("columns", float(column_count()))
	material.set_shader_parameter("fall_span", FALL_SPAN)
	material.set_shader_parameter("fall_speed", FALL_SPEED)
	material.set_shader_parameter("drop_spacing", DROP_SPACING)
	material.set_shader_parameter("min_speed_factor", MIN_SPEED_FACTOR)
	material.set_shader_parameter("speed_factor_range", SPEED_FACTOR_RANGE)
	material.set_shader_parameter("drop_color", DROP_COLOR)
	return material


func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = make_material()
	return _shared_material


## How heavy the rain is, 0 (dry) .. 1 (downpour). Driven from the live
## weather model alongside the water overlay's own rain response, so the
## water starts rippling and the sky starts falling together.
func set_intensity(intensity: float) -> void:
	shared_material().set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))


## Switches the falling weather between rain and snow.
##
## The same drop field either way -- one MultiMesh, one draw call -- with the
## colour, speed and slant swapped. Snow is white, falls far slower and drifts
## instead of slanting; reusing rain unchanged would give WHITE RAIN, which
## reads as a recolour rather than as weather.
func set_snowing(snowing: bool) -> void:
	var material := shared_material()
	material.set_shader_parameter(
		"drop_color", Snowfall.FLAKE_COLOR if snowing else DROP_COLOR
	)
	material.set_shader_parameter(
		"fall_speed", Snowfall.FLAKE_FALL_SPEED if snowing else FALL_SPEED
	)
	material.set_shader_parameter("slant", Snowfall.FLAKE_SLANT if snowing else SLANT)


## The drop field: one quad per drop in flight, all in a single MultiMesh so
## the whole downpour is still one draw call.
func build_drops() -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = drop_mesh_size()
	# Anchored at its top-left rather than its centre, so a drop's placement
	# is the head of the streak.
	quad.center_offset = Vector3(drop_mesh_size().x * 0.5, drop_mesh_size().y * 0.5, 0.0)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = instance_count()
	for i in instance_count():
		# The transform stays at the origin: every drop is placed by the
		# vertex shader, which has to move it each frame anyway.
		multimesh.set_instance_transform_2d(i, Transform2D.IDENTITY)
		# Every channel is a 0..1 FRACTION, scaled back up by a uniform in the
		# shader: custom data is 8 bits per channel in this renderer, so a raw
		# screen coordinate stored here reads back as 0 (measured).
		multimesh.set_instance_custom_data(
			i,
			Color(
				jitter_fraction_for(i),
				start_fraction_for(i),
				speed_fraction_for(i),
				phase_fraction_for(i)
			)
		)

	var drops := MultiMeshInstance2D.new()
	drops.name = "RainDrops"
	drops.multimesh = multimesh
	drops.material = shared_material()
	return drops


## A ready-to-add screen-space rain layer. Caller adds it to the scene; it
## needs no positioning and no per-frame updates.
func build_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "RainOverlay"
	layer.layer = OVERLAY_CANVAS_LAYER
	layer.add_child(build_drops())
	return layer
