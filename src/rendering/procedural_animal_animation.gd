extends RefCounted

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## Frame-set generator for animated creature pixel art. Builds short
## per-action animations by post-processing the single 24x16 base image
## produced by ProceduralAnimalSprite (shifting pixel regions rather than
## re-drawing). Deterministic per (species, action, seed): no
## RandomNumberGenerator. Unknown actions fall back to "walk".

const AnimalSpriteScript := preload("res://src/rendering/procedural_animal_sprite.gd")
const AnimalAnatomy := preload("res://src/rendering/animal_anatomy.gd")
const QuadrupedGait := preload("res://src/rendering/quadruped_gait.gd")

const ACTIONS := ["walk", "attack", "eat", "swim", "drink"]

const FRAME_COUNTS := {
	"walk": 2,
	"attack": 2,
	"eat": 2,
	"swim": 2,
	"drink": 2,
}

## A serpent (see AnimalAnatomy.SERPENT_SPECIES) has zero leg_length, so
## _walk_frame's leg-band shift has nothing to move -- its "walk" animation
## was two pixel-identical frames, completely static. Its whole body
## undulates instead (see _slither_frame), which reads far better as a
## smoother ripple than a two-frame twitch.
const SERPENT_WALK_FRAME_COUNT := 6
## How far a point on the wave swings sideways, in art pixels -- scaled with
## resolution like FRAME_SHIFT so it reads as a real curve, not a sub-pixel
## shimmer.
const SERPENT_AMPLITUDE_PX := 1.0 * ArtResolution.DETAIL_MULTIPLIER
## Wave crests span this fraction of the sprite's width -- roughly one full
## S-curve along the body's length, like a real snake's travelling wave.
const SERPENT_WAVELENGTH_FRACTION := 0.6

## Legged (non-serpent) species get a real hip/knee walk cycle (see
## QuadrupedGait) instead of the old leg-shift hack -- drawn fresh each frame
## since the joints themselves move, not one static image with a region
## slid sideways. More frames than the generic 2 because an actual gait
## cycle needs the room: 2 frames of a swinging joint reads as a twitch, not
## a stride.
##
## Must be ODD. QuadrupedGait's angles are pure sin(), which is symmetric
## about its own peak/trough (sin(x) == sin(180 deg - x)): sampled at
## (i + 0.5)/N as generate_frames does below, an EVEN N always lands two
## samples on exactly-matching sine values, so two of the "distinct" frames
## come out pixel-identical (first found with N=6: frames 0 and 3 collided;
## re-centering the sample offset to dodge that moved the collision to
## frames 0 and 2 instead of removing it -- the symmetry is structural, not
## a sampling-offset bug). For this specific (i+0.5)/N formula, odd N has no
## exact collision: verified for N=5 by checking every pair of the 5 sample
## points sums to neither 0.5 nor 1.5 (mod 1), the two conditions under
## which sin() ties. Pinned by
## test_every_frame_of_a_walk_cycle_is_a_distinct_pose.
const WALK_FRAME_COUNT := 5

const WATER_COLOR := Color(0.2, 0.4, 0.85)
const WATER_SURFACE_COLOR := Color(0.35, 0.55, 0.95)
## Where the waterline sits, as a FRACTION of the sprite's height. This was a
## fixed pixel row tuned for the original 16px-tall canvas; at the 4x art
## resolution (see docs/concept/art_resolution.md) a literal row 10 sat near
## the animal's shoulder, so the swim frame flooded most of the body and
## both frames came out identical.
const WATER_TOP_FRACTION := 0.62
## Where the legs sit -- still used by _eat_frame/_drink_frame's head-dip,
## not by walking any more (see WALK_FRAME_COUNT above).
const LEG_TOP_FRACTION := 0.81

## How much a submerged BODY pixel blends toward water colour (0 = untouched,
## 1 = fully replaced) -- partial, so the animal's own coat still shows
## through the water rather than being erased by it.
const SWIM_TINT_STRENGTH := 0.55
## How much alpha a submerged pixel loses, so the silhouette genuinely reads
## as underwater rather than merely recoloured.
const SWIM_ALPHA_FADE := 0.25

## How far parts move between animation frames, in art pixels. Scaled with
## the resolution so a step still reads as a step rather than as a
## sub-pixel twitch.
const FRAME_SHIFT := 2 * ArtResolution.DETAIL_MULTIPLIER

## How far an idling creature's whole silhouette settles on its second idle
## frame -- read as a slow breath, not a stride or a swim bob (both far more
## energetic actions that already use the full FRAME_SHIFT for their own
## two-frame cycles). Half of FRAME_SHIFT, same "scaled with resolution"
## reasoning.
const IDLE_BREATH_SHIFT := FRAME_SHIFT / 2

## Frame 0 is the neutral standing pose "idle" has always used; frame 1
## settles the whole silhouette by IDLE_BREATH_SHIFT (see _idle_frame). A
## single frozen frame read fine back when idle was rare, but grazing pauses
## and a boxed-in creature with nowhere to go (CreatureWander.is_pausing,
## creature_movement_gate.gd) made standing still a common state, not a rare
## one -- and a creature that spends real time standing still needs
## somewhere to go beyond one photograph.
const IDLE_FRAME_COUNT := 2

## How long a full idle cycle (through all IDLE_FRAME_COUNT frames) takes to
## play, in seconds -- much slower than ANIMATION_FRAME_DURATION
## (creature_marker.gd)'s gait/action cadence, since a breath is a slow,
## ambient motion, not a gait frame. Used by idle_frame_index below.
const IDLE_FRAME_DURATION := 1.2


func generate_frames(species: String, action: String, seed_value: int) -> Array[Image]:
	var sprite := AnimalSpriteScript.new()

	if action == "idle":
		# Frame 0 is a static neutral pose (gait_phase 0.0 -- the same
		# standing silhouette every other non-walk action's base image
		# already uses), for a creature that isn't actually moving right
		# now. CreatureMarker used to keep cycling "walk"'s gait frames
		# purely off elapsed time regardless of whether the creature had
		# actually advanced, so legs kept swinging mid-stride while it stood
		# still (reported: "their legs are animated even when they stand
		# still"). This is what it asks for instead.
		#
		# A single frame forever still read as frozen once standing still
		# became a common state rather than a rare one (see
		# IDLE_FRAME_COUNT's own doc comment) -- idle now cycles through
		# IDLE_FRAME_COUNT frames (see _idle_frame). idle_frame_index below
		# is how CreatureMarker picks between them without a whole herd
		# breathing in lockstep.
		var base: Image = sprite.generate_image(species, seed_value)
		var idle_frames: Array[Image] = []
		for frame_index in IDLE_FRAME_COUNT:
			idle_frames.append(_idle_frame(base, frame_index))
		return idle_frames

	var key: String = action if FRAME_COUNTS.has(action) else "walk"

	if key == "walk":
		if AnimalAnatomy.SERPENT_SPECIES.has(species):
			var base: Image = sprite.generate_image(species, seed_value)
			var slither_frames: Array[Image] = []
			for frame_index in SERPENT_WALK_FRAME_COUNT:
				slither_frames.append(_slither_frame(base, frame_index, SERPENT_WALK_FRAME_COUNT))
			return slither_frames
		# Legged species: pose the hip/knee fresh each frame (see
		# QuadrupedGait) rather than shifting a leg-shaped pixel region of
		# one static image -- there is no rigid region to shift, the joints
		# themselves move through the stride.
		#
		# Sampled at (i + 0.5)/N, not i/N: sin() crosses zero at BOTH
		# phase 0.0 and phase 0.5 (every leg is briefly neutral twice per
		# real gait cycle too), and WALK_FRAME_COUNT is even, so i/N lands
		# exactly on phase 0.5 partway through -- two of six "distinct"
		# frames came out pixel-identical. The half-step offset avoids both
		# degenerate points entirely.
		var gait_frames: Array[Image] = []
		for frame_index in WALK_FRAME_COUNT:
			var phase := (float(frame_index) + 0.5) / float(WALK_FRAME_COUNT)
			gait_frames.append(sprite.generate_image(species, seed_value, phase))
		return gait_frames

	var base: Image = sprite.generate_image(species, seed_value)
	var frames: Array[Image] = []
	for frame_index in int(FRAME_COUNTS[key]):
		frames.append(_build_frame(base, key, frame_index))
	return frames


func generate_textures(species: String, action: String, seed_value: int) -> Array[ImageTexture]:
	var textures: Array[ImageTexture] = []
	for frame in generate_frames(species, action, seed_value):
		textures.append(ImageTexture.create_from_image(frame))
	return textures


## How many distinct individual looks a species has. Generation is bounded by
## this rather than by how many animals are alive: drawing a frame set costs
## ~47ms, and every CreatureMarker used to draw its own the first time it
## played an action. Measured live, a herd of 25 crossing into "eat" together
## spent 1.18 SECONDS generating inside one 5-second window -- the 130-145ms
## frame spikes reported as lag.
##
## Eight is enough that a herd doesn't read as clones (pinned by
## test_a_species_still_shows_more_than_one_look) while capping the work at
## species x action x 8, paid once for the whole session.
const LOOK_VARIANTS := 8

static var _texture_cache: Dictionary = {}


## The cached counterpart of generate_textures, and what animation callers
## should use: individuals sharing a look share one frame set. Instance method
## over a STATIC cache because every CreatureMarker holds its own generator,
## so a per-instance cache would still redraw once per animal.
func textures_for(species: String, action: String, seed_value: int) -> Array[ImageTexture]:
	var variant := absi(seed_value) % LOOK_VARIANTS
	var key := "%s/%s/%d" % [species, action, variant]
	if not _texture_cache.has(key):
		_texture_cache[key] = generate_textures(species, action, variant)
	return _texture_cache[key]


## Which of an idling creature's `frame_count` idle frames to show right now.
##
## Idle used to render frame 0 of a single-frame set forever: frozen, since
## there was nothing else to show, and -- once IDLE_FRAME_COUNT grew past 1
## -- would have stayed IDENTICAL across an entire herd too, since frame
## selection read only elapsed_time: every creature's own clock starts at
## 0.0 and advances by the same per-frame delta absent an LOD stagger, so a
## herd that spawned together would breathe in perfect unison. `seed_value`
## is hashed into a per-individual phase offset in [0, IDLE_FRAME_DURATION)
## and folded in before the cycle position is computed -- the same
## deterministic, per-individual, reproducible hash-of-seed shape
## CreatureWander.is_pausing already uses for its own seeded roll -- so two
## creatures of the same look, idling at the exact same elapsed_time, can
## land on different frames, and the SAME creature reproduces the same frame
## on replay (same seed, same elapsed_time -> same result, always).
##
## `frame_count` <= 1 (every illustrated species' idle -- see
## IllustratedAnimalSprite, which has no per-individual variation at all)
## always returns 0: nothing to cycle through, whatever the seed says.
func idle_frame_index(elapsed_time: float, seed_value: int, frame_count: int) -> int:
	if frame_count <= 1:
		return 0
	var phase_offset := (
		float(absi(hash("%d_idle_phase" % seed_value)) % 1000) / 1000.0 * IDLE_FRAME_DURATION
	)
	var cycle_position := fmod(elapsed_time + phase_offset, IDLE_FRAME_DURATION * float(frame_count))
	return int(cycle_position / IDLE_FRAME_DURATION) % frame_count


## Never called with action=="walk": generate_frames handles walk entirely
## itself (slither for serpents, gait for everyone else) before reaching
## this, since neither is "shift a static image's pixels" like these are.
func _build_frame(base: Image, action: String, frame_index: int) -> Image:
	match action:
		"attack":
			return _attack_frame(base, frame_index)
		"eat":
			return _eat_frame(base, frame_index)
		"swim":
			return _swim_frame(base, frame_index)
		"drink":
			return _drink_frame(base, frame_index)
	return _copy(base)


## A serpent's whole-body walk cycle: every opaque pixel's column shifts
## vertically by a traveling sine wave along the body's length (x axis), so
## the body reads as one continuous S-curve rather than a leg swap -- there
## are no legs. The wave depends only on x, so every pixel in a column
## shares the same shift and the body stays a solid, unbroken ribbon (no
## gaps between rows). `frame_index`/`frame_count` advance the phase, so
## played back in sequence the curve visibly travels down the body like a
## real slither.
func _slither_frame(base: Image, frame_index: int, frame_count: int) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wavelength := maxf(float(w) * SERPENT_WAVELENGTH_FRACTION, 1.0)
	var phase := TAU * float(frame_index) / float(frame_count)
	for x in w:
		var shift := int(round(sin(TAU * float(x) / wavelength + phase) * SERPENT_AMPLITUDE_PX))
		if shift == 0:
			for y in h:
				var c := base.get_pixel(x, y)
				if c.a > 0.0:
					image.set_pixel(x, y, c)
			continue
		for y in h:
			var c := base.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var ny := y + shift
			if ny >= 0 and ny < h:
				image.set_pixel(x, ny, c)
	return image


## Frame 0 is the untouched neutral pose; frame 1 settles the whole
## silhouette up by IDLE_BREATH_SHIFT -- the same _shifted-a-whole-image
## shape _swim_frame's bob already uses for its own two-frame cycle, just a
## smaller shift played back at IDLE_FRAME_DURATION's far slower cadence so
## it reads as a breath, not a bob.
func _idle_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	return _shifted(base, 0, -IDLE_BREATH_SHIFT)


## Body lunges forward (toward +x) a couple of pixels on the off frame.
func _attack_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	return _shifted(base, FRAME_SHIFT, 0)


## Head dips down: the top half of the sprite shifts down one row.
func _eat_frame(base: Image, frame_index: int) -> Image:
	if frame_index == 0:
		return _copy(base)
	var frame := _copy(base)
	var w := base.get_width()
	var half := base.get_height() / 2
	_clear_rows(frame, 0, half)
	for y in half:
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a > 0.0:
				frame.set_pixel(x, y + 1, c)
	return frame


## The body itself is tinted/faded below the waterline rather than painted
## over -- this used to fill the full tile width from water_top down in flat
## WATER_COLOR, which included every TRANSPARENT background pixel too, and
## is exactly why it read as a solid blue rectangle rather than water
## covering part of an animal (reported: "remove the blue rectangle ... make
## the water realistically cover parts of the body"). Background stays
## transparent; only the animal's own silhouette changes below the line, and
## it still bobs on the off frame.
func _swim_frame(base: Image, frame_index: int) -> Image:
	var shifted := _shifted(base, 0, FRAME_SHIFT if frame_index != 0 else 0)
	var w := shifted.get_width()
	var h := shifted.get_height()
	var water_top := int(float(h) * WATER_TOP_FRACTION)
	var frame := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := shifted.get_pixel(x, y)
			if y < water_top or c.a <= 0.0:
				frame.set_pixel(x, y, c)  # dry, or background -- untouched
				continue
			var tinted := c.lerp(WATER_COLOR, SWIM_TINT_STRENGTH)
			tinted.a = c.a * (1.0 - SWIM_ALPHA_FADE)
			frame.set_pixel(x, y, tinted)
	# A bright waterline stroke, but only where the BODY actually crosses
	# it -- not a full-width bar across empty background either.
	for x in w:
		var c := shifted.get_pixel(x, water_top)
		if c.a > 0.0:
			frame.set_pixel(x, water_top, WATER_SURFACE_COLOR)
	return frame


## Head dips like eat, with a blue water accent at the ground line.
func _drink_frame(base: Image, frame_index: int) -> Image:
	var frame := _eat_frame(base, frame_index)
	var h := frame.get_height()
	for x in range(2, 6):
		frame.set_pixel(x, h - 1, WATER_COLOR)
	return frame


func _copy(base: Image) -> Image:
	var image := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	image.blit_rect(base, Rect2i(0, 0, base.get_width(), base.get_height()), Vector2i.ZERO)
	return image


func _shifted(base: Image, dx: int, dy: int) -> Image:
	var w := base.get_width()
	var h := base.get_height()
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := base.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < w and ny >= 0 and ny < h:
				image.set_pixel(nx, ny, c)
	return image


func _clear_rows(image: Image, from_row: int, to_row: int) -> void:
	for y in range(from_row, to_row):
		for x in image.get_width():
			image.set_pixel(x, y, Color(0, 0, 0, 0))
