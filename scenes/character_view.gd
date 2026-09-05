extends Node2D
class_name CharacterView

const WeaponSwing = preload("res://src/gameplay/weapon_swing.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")
const LegGaitCycle = preload("res://src/rendering/leg_gait_cycle.gd")

## Reusable placeholder character rendering: a body/head/legs/arms made of
## flat colored shapes, a directional facing, walk and swim animations, and a
## small set of equipment slots (visual only -- not tied to gameplay
## inventory yet). Meant for both the player and, later, NPCs; swap the
## placeholder textures for real art without touching the API.

enum Facing { DOWN, UP, LEFT, RIGHT }
enum MovementState { IDLE, WALKING, SWIMMING }

const WALK_CYCLE_SPEED := 10.0
const LEG_SWING_AMPLITUDE := 3.0
const SWIM_CYCLE_SPEED := 6.0
const ARM_STROKE_AMPLITUDE := 4.0
## A smaller sway for walking than the swim stroke uses (reported live:
## "hands should also slightly sway when walking") -- real arms swing less
## dramatically than a swimming stroke, roughly the same restraint
## LEG_SWING_AMPLITUDE already shows relative to ARM_STROKE_AMPLITUDE.
const ARM_SWAY_AMPLITUDE := 1.5
const TOOL_SLOT_SIDE_OFFSET := 8.0
## How far below ArmRight's own centre a held weapon's grip sits -- roughly
## the arm's own half-height (ARM_SIZE.y / 2 = 4.5), reaching toward where
## a hand at the bottom of the arm sprite would hold a hilt, not the arm's
## own midpoint.
const GRIP_OFFSET_Y := 4.0

## The fused leg pair's own vertical walk motion, in world units -- the
## THIRD attempt at this (see FUSED_LEG_BOB_AMPLITUDE/FUSED_LEG_ROCK_
## AMPLITUDE below for the first two). The second attempt (a rock) was
## itself superseded by a real hip+knee ROTATION gait (LegGaitCycle.
## hip_angle/knee_angle) — biomechanically real angle math, deliberately
## reduced below anatomical values for this exact concern (see both
## constants' own doc comments: "on a front-on silhouette the full real
## angle reads as an exaggerated snap") — but reported live even after
## that reduction: "legs still move left and right instead of up and
## down". Rotating a front-facing leg around its hip pivot displaces its
## tip mostly HORIZONTALLY for any angle, full stop — a real human's own
## visible motion walking straight toward/away from a camera is a
## vertical knee-lift, not a side-to-side swing. LegGaitCycle.
## swing_lift_fraction reuses the exact same phase-timing research
## (still correct) as a [0,1] lift fraction instead of an angle; this is
## what that fraction gets multiplied by. Originally set to 1.0 (this now
## drives the WHOLE leg -- thigh AND the shin riding along via the
## parent-child chain -- so a smaller amplitude than the very first bob
## attempt's 1.2 seemed reasonable), but reported live as reading as
## almost no motion at all: "legs now barely move at all... there should
## be visible natural walking motion". Bumped to 3.0 -- roughly 15% of
## LEG_SIZE.y (20), a real, legible lift rather than a barely-there
## wobble, while still well short of the leg's own full height so it
## doesn't read as a hop.
const FUSED_LEG_LIFT_AMPLITUDE := 3.0

## SUPERSEDED by a real hip+knee gait (see FUSED_LEG_ROCK_AMPLITUDE's own
## doc comment, and leg_gait_cycle.gd) -- kept only as a historical pointer;
## no code reads it any more. It WAS the fused leg pair's whole-body walk
## bob, in world units -- gentler than LEG_SWING_AMPLITUDE (a single sprite
## bobbing reads as a smaller motion than two legs swinging apart) since
## there was no per-leg swing art for it yet to make a bigger motion read as
## a real stride rather than a wobble (reported at the time: "the legs
## aren't animated").
const FUSED_LEG_BOB_AMPLITUDE := 1.2
## SUPERSEDED by a real hip+knee gait (see leg_gait_cycle.gd / _apply_legs /
## _process) -- kept only as a historical pointer for the doc comments below
## that still narrate how this constant used to work; no code reads it any
## more. It WAS an interim stride cue for the fused pair (reported live at
## the time: real per-leg knee-jointed animation) -- the fused drawing can't
## split into two independently-swinging legs at all without new source art
## (see docs/concept/character_art_brief.md's "Four bugs" section), so a
## small whole-pair hip-pivot rock, in RADIANS, on top of a vertical bob was
## the closest a single rigid transform could get. Reported live again
## later, still asking for a REAL knee: replaced by LegGaitCycle.hip_angle/
## knee_angle driving a genuine two-piece hip+knee pivot chain instead (see
## IllustratedCharacterSprite.composite_leg_segments for the crop that makes
## that chain possible without new art) -- which was ITSELF then reported as
## reading wrong ("legs still move left and right instead of up and down")
## and replaced by FUSED_LEG_LIFT_AMPLITUDE above driving vertical position
## instead of rotation, reusing the same LegGaitCycle phase timing as a
## [0,1] fraction (see LegGaitCycle.swing_lift_fraction).
const FUSED_LEG_ROCK_AMPLITUDE := 0.12

## Bumped from the original 10x14/8x8 (see the character sprite engine's
## hero head/tunic detail -- hairstyles, brows, eyes, belt/collar trim): at
## the old resolution none of that detail had enough pixels to read at all,
## just a flat colored blob under a smaller blob (reported "the in game char
## looks horrible"). These proportions match the tscn's part positions below.
##
## BODY_SIZE.x widened 13 -> 26 once hero_composite.png's torso replaced the
## flat rectangle this box was originally sized for: the shirt's short
## sleeves are drawn as part of the same silhouette (see
## docs/concept/character_art_brief.md), so its measured content comes out
## noticeably wider than tall (64x47 for the most common outfit row) --
## height-matching alone (the rule composite_part_scale_for/
## _width_bounded_scale both apply -- see _apply_body) rendered the torso
## roughly 2x the OLD BODY_SIZE.x wide (reported live: "proportions are
## awfully wrong"). 26 is measured directly from that row (19 * 64/47,
## rounded), not eyeballed -- it lets the most common row render at its
## real intended HEIGHT without the width clamp fighting it, while still
## giving unusually short/wide outfit rows (see the survey behind this
## pass) a real, bounded ceiling instead of the old ~2x overflow. Some rows
## still end up shorter than BODY_SIZE.y as a result -- a real compromise
## between "never distort the art" and "always hit the exact target height"
## when a row's own aspect doesn't match this box's, not a bug.
const BODY_SIZE := Vector2i(26, 19)
const HEAD_SIZE := Vector2i(12, 12)
## Winter's "Biomechanics and Motor Control of Human Movement" segment-length
## table -- the same book stone_size.gd's LEG_MASS_FRACTION already cites,
## for a different table -- gives thigh length as ~0.245x standing height and
## shank length as ~0.246x. Together, ~49.1% of a real person's standing
## height is leg, hip joint to floor (thigh and shank are close enough to
## equal that the knee sits at essentially the leg's own midpoint -- see
## IllustratedCharacterSprite.KNEE_LINE_FRACTION, which reuses this same
## number rather than a second eyeballed split).
const WINTER_THIGH_FRACTION_OF_HEIGHT := 0.245
const WINTER_SHANK_FRACTION_OF_HEIGHT := 0.246
const LEG_TO_HEIGHT_FRACTION := WINTER_THIGH_FRACTION_OF_HEIGHT + WINTER_SHANK_FRACTION_OF_HEIGHT

## Everything ABOVE the hip line -- torso, neck, head -- held fixed while the
## legs below stretch (see LEG_SIZE below), so this pass grows the character
## by lengthening legs specifically (reported live: "the players walk
## animation and overall appearance looks like a dwarf... stretch legs so he
## becomes taller"), a real Y-axis stretch, not a bigger overall SCALE
## multiplier that would leave every proportion (and the dwarf look) exactly
## as it was, just bigger. Measured from this rig's own PRE-stretch layout:
## the old HEAD_TOP_Y (-33.0) minus the old LEG_SIZE.y (12).
const ABOVE_HIP_HEIGHT := 21.0


## The leg height (world units) that makes legs LEG_TO_HEIGHT_FRACTION of the
## character's own total height (legs + ABOVE_HIP_HEIGHT) -- i.e. solves
## `leg / (above_hip_height + leg) = LEG_TO_HEIGHT_FRACTION` for `leg`. Pure
## and tested (test_leg_size_matches_the_anthropometric_leg_to_height_
## fraction) rather than an eyeballed literal, per this project's own
## tuned-constants rule (CLAUDE.md) -- LEG_SIZE.y below is this function's
## own output, rounded to the nearest whole pixel (Vector2i has no float
## component), which GDScript's const-expression rules don't allow calling
## directly inside LEG_SIZE's own literal below.
static func _anthropometric_leg_height(above_hip_height: float) -> float:
	return LEG_TO_HEIGHT_FRACTION * above_hip_height / (1.0 - LEG_TO_HEIGHT_FRACTION)


## .y widened 8 -> 12 -> 20 across two passes. The first (8 -> 12, reported
## live: "the legs are too short") only got partway to a real anthropometric
## share (~36%, still eyeballed against a rough "45-50%" reading rather than
## a cited table) before the SECOND pass (12 -> 20, reported live: "looks
## like a dwarf") replaced that eyeballed target with the real formula above:
## _anthropometric_leg_height(21.0) = 20.26, rounded to 20 (~49%, see
## test_the_resulting_leg_share_of_total_height_is_within_the_cited_
## anthropometric_range). LegLeft/LegRight's own .tscn position moved
## -6 -> -10 alongside this (half the new height, the same rule the first
## pass's -4 -> -6 move already followed) so the fused pair's feet still
## land exactly on the character's own origin, per
## test_the_characters_feet_sit_at_its_own_origin. Growing the legs alone
## (not every part) also means HEAD_TOP_Y grows by the same 8-unit delta
## (33 -> 41) and Body/Neck/Head/Arms/HeadSlot's own .tscn positions all
## shift up by that same delta, so the now-taller legs read as the whole
## character growing taller from the hips down, not the torso/head sinking
## into overlapping legs.
##
## .x widened 5 -> 10 once the hip+knee leg-gait split (see leg_gait_
## cycle.gd) exposed a real, previously-hidden bug: composite_part_scale_for
## matches CONTENT HEIGHT alone (see _width_bounded_scale's own doc comment
## on why that isn't automatically also correct for width), and nothing
## clamped the thigh/shin split's own width the way _apply_body's own
## _width_bounded_scale call already does for the torso -- measured
## rendering the fused pair 42-64 world units wide against the OLD
## LEG_SIZE.x's target of 10 (5*2), nearly as wide as the torso itself
## (reported live: "unproportional ... walks like a duck"). 10 is measured,
## not eyeballed, the same way BODY_SIZE.x was: outfit row 0's legs measure
## 64x64 (a 1:1 aspect), so LEG_SIZE.y(20) * 64/64 / 2 = 10 lets THAT row's
## fused pair hit its full anthropometric HEIGHT with no width clamp needed
## at all, while shorter/wider rows (the other 7) still compromise toward
## width the same way BODY_SIZE.x's own rows do -- a real trade-off between
## "never distort the art" and "always hit the exact target height," not a
## bug, when a row's own aspect doesn't match this box's.
const LEG_SIZE := Vector2i(10, 20)
const ARM_SIZE := Vector2i(4, 9)
const SLOT_SIZE := Vector2i(7, 7)
const EYE_COLOR := Color(0.1, 0.1, 0.1)

## The ART canvases each part is actually painted on: DETAIL_MULTIPLIER
## times the world sizes above (see docs/concept/art_resolution.md). Every
## part sprite is drawn at ArtResolution.SPRITE_SCALE, so the hero gains
## real pixel detail -- a face with actual features rather than a few
## suggestive pixels -- while staying exactly the same size in the world
## and keeping character_view.tscn's part positions (which are in world
## units) valid unchanged.
const ART_BODY_SIZE := Vector2i(52, 38)
const ART_HEAD_SIZE := Vector2i(24, 24)
const ART_LEG_SIZE := Vector2i(20, 40)
const ART_ARM_SIZE := Vector2i(8, 18)
const ART_SLOT_SIZE := Vector2i(14, 14)

## The character's own origin sits at its feet (y=0, see the feet-anchoring
## tests in test_character_view.gd) -- this is the top of the HEAD relative
## to that, i.e. the character's own total height. Computed as
## ABOVE_HIP_HEIGHT + LEG_SIZE.y (torso/neck/head plus the now-stretched
## legs) rather than a second independent literal, so the two can't silently
## drift apart the way an eyeballed pair could -- pinned by
## test_head_top_y_equals_above_hip_height_plus_the_new_leg_height. Mirrors
## character_view.tscn's Head position (-35) minus half HEAD_SIZE.y (6);
## also pinned against the live scene by
## test_head_top_y_matches_the_actual_head_nodes_top_edge so a .tscn layout
## change can't silently drift out of sync with the scale computed from it
## below.
const HEAD_TOP_Y := -(ABOVE_HIP_HEIGHT + float(LEG_SIZE.y))

## The character (and every NPC, who shares this same scene -- see
## VillageRenderer) reads at this fraction of a full-grown tree's height,
## rather than looming as tall as (or taller than) the trees around it
## (reported originally: "shrink the character and npcs so they are 2/3 the
## height of a tree").
##
## Raised from the original 2/3 once hero_composite.png's shaded,
## multi-tone illustrated parts replaced the old flat-color procedural ones:
## at 2/3, a leg's own measured content rendered at ~4 screen pixels tall
## (reported: "legs are not wired" -- they were, but detailed art doesn't
## survive that downscale the way a single flat color does; it just
## smears into a muddy blob that blends with the ground). Asked directly
## how to fix it (raise the whole character's size vs. legs specifically):
## raising the whole character keeps every part's proportions -- and every
## part's own legibility, not just legs' -- consistent. 0.85 is a real
## compromise, not a full fix: it stays deliberately short of 1.0 (as tall
## as a tree) to preserve the ORIGINAL ask this constant exists for
## (character visibly smaller than the trees around it), which caps how far
## this lever alone can go -- the art itself was drawn assuming a larger
## viewing size than this project's tile-scale budget affords, and closing
## that gap the rest of the way is a real follow-up, not solved here.
const TARGET_HEIGHT_FRACTION_OF_TREE := 0.85

## Computed, not eyeballed (see CLAUDE.md): the character's own total
## on-screen height (feet to head-top, -HEAD_TOP_Y) times this scale must
## equal TARGET_HEIGHT_FRACTION_OF_TREE of a tree's real WORLD height
## (already resolution-corrected -- see TreeRenderer.TREE_SIZE, itself
## just ProceduralTreeSprite.WORLD_SIZE). Pinned by
## test_scaled_character_height_matches_its_target_fraction_of_a_trees_height.
const SCALE := (
	TARGET_HEIGHT_FRACTION_OF_TREE * float(ProceduralTreeSprite.WORLD_SIZE.y) / -HEAD_TOP_Y
)

var facing := Facing.DOWN
var movement_state := MovementState.IDLE
## Whether the character is actually being driven right now (nonzero input),
## as opposed to just being in water. SWIMMING used to stroke the arms
## unconditionally off a free-running clock, so treading water in place
## looked identical to actually swimming (reported: "the arms should only
## animate when moving not when standing"). Legs/arm visibility and tool
## stowing stay keyed off movement_state alone -- you're still submerged
## while treading water -- only the STROKE ANIMATION additionally checks
## this.
var is_moving := false
var leg_swing_offset := 0.0
var arm_stroke_offset := 0.0

var _cycle_time := 0.0
var _equipped_slots: Dictionary = {}  # slot_name (String) -> bool

var _weapon_swing := WeaponSwing.new()
var _leg_gait := LegGaitCycle.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _illustrated := IllustratedCharacterSprite.new()
var _submersion := SubmersionShader.new()
var _swing_time_remaining := 0.0
var _swing_duration := 0.0
var _swing_facing := "down"
## A look requested before this view entered the tree (see
## apply_appearance), applied in _ready.
var _pending_appearance: Dictionary = {}

## Draw order is the .tscn's own child order (later siblings draw on top):
## LegLeft, LegRight, Body, ArmLeft, ArmRight, Head, HeadSlot, ToolSlot.
## Body sits BEFORE Arms specifically -- arms now stay visible in every
## movement state (see _process), and hero_composite.png's torso art is
## noticeably wide (short sleeves drawn as part of the same silhouette, see
## docs/concept/character_art_brief.md's proportions note), wide enough to
## otherwise horizontally overlap where ArmLeft/ArmRight sit -- drawing Body
## first keeps a hand always in front of the torso instead of risking it
## being painted over by the torso's own sleeve fabric.
@onready var _body: Sprite2D = $Body
@onready var _neck: Sprite2D = $Neck
@onready var _head: Sprite2D = $Head
@onready var _leg_left: Sprite2D = $LegLeft
@onready var _leg_right: Sprite2D = $LegRight
## The knee pivot (Node2D, not Bone2D -- see IllustratedCharacterSprite's own
## doc comment on "Leg hip/knee segments" for why plain Bone2D nodes without
## a real Skeleton2D-driven Polygon2D skin were set aside as more nominal
## than useful here) and the shin crop it carries, both children of LegLeft
## so they automatically inherit the hip's own rotation (see _apply_legs/
## _process). Unused (left at rest, hidden) on the procedural fallback path.
@onready var _leg_knee: Node2D = $LegLeft/LegLeftKnee
@onready var _leg_shin: Sprite2D = $LegLeft/LegLeftKnee/LegLeftShin
@onready var _arm_left: Sprite2D = $ArmLeft
@onready var _arm_right: Sprite2D = $ArmRight
@onready var _head_slot: Sprite2D = $HeadSlot
@onready var _tool_slot: Sprite2D = $ToolSlot
## Real worn-armor slots (see docs/concept/item_illustrations.md and
## Equipment.SLOTS) -- ChestSlot/LegsSlot/FeetSlot sit alongside HeadSlot,
## each drawn immediately after the body part(s) it covers (ChestSlot right
## after Body, still behind Arms; FeetSlot/LegsSlot right after LegRight,
## still behind Body -- see character_view.tscn's node order), the same
## "draw over what it covers" rule ToolSlot's own doc comment already states.
@onready var _chest_slot: Sprite2D = $ChestSlot
@onready var _legs_slot: Sprite2D = $LegsSlot
@onready var _feet_slot: Sprite2D = $FeetSlot

var _leg_left_base_position: Vector2
var _leg_right_base_position: Vector2
var _arm_left_base_position: Vector2
var _arm_right_base_position: Vector2
var _tool_slot_base_position: Vector2
## Body/Head never move on their own (unlike the parts above, which bob/
## swing) -- these exist purely so _apply_submersion_depth's visual sink
## has a stable rest value to sink FROM, the same role the _base_position
## vars above already play for legs/arms.
var _body_base_position: Vector2
var _head_base_position: Vector2
## Captured at the end of _apply_neck instead of once in _ready, since
## unlike Body/Head, Neck's own rest position is computed per-appearance
## (see _apply_neck) rather than fixed in the .tscn.
var _neck_base_position: Vector2

## Real, continuous water depth in meters, set every frame by a caller that
## has one (Player -- see set_submersion_depth). -1.0 is a sentinel for "no
## caller has ever set a real depth", not "zero depth" -- see
## _submersion_fraction's own doc comment for why that distinction matters
## for callers (the character-creator diorama, village NPCs) that only
## ever say "swimming or not" via movement_state.
var _submersion_depth_meters := -1.0
## Which side of the body ToolSlot's grip point offsets toward -- 1.0/-1.0
## for RIGHT/LEFT facing, 0.0 otherwise (see set_facing). Stored rather than
## applied directly there: _process now recomputes ToolSlot's position every
## frame from ArmRight's OWN current position (see GRIP_OFFSET's own doc
## comment), which changes continuously while walking, not just on a facing
## change.
var _tool_side := 0.0

## True while LegLeft is wearing the illustrated fused leg PAIR in place of
## two independently-tinted/animated procedural legs (see _apply_legs) --
## LegRight is hidden and unused in that state, and _process must not apply
## the opposite-direction walk-swing offset to either leg, or the single
## fused sprite would visibly split into two vertically-offset copies of
## itself. Neither part is true "no legs at all" -- see legs_visible().
var _legs_are_fused := false
## The fused pair's centred rest position (set in _apply_legs) -- _process
## bobs around this rather than around _leg_left_base_position, which is the
## UN-centred single-leg tscn position the fused pair never actually sits at.
var _leg_fused_rest_position: Vector2

## This outfit row's own real walk-cycle frames for the fused leg pair (see
## IllustratedCharacterSprite's own top-level doc comment on the second
## hero_composite.png regeneration: up to 5 real drawn poses per row now,
## not one static image) -- set once in _apply_legs, cycled through by
## _process/_apply_leg_frame while WALKING. SUPERSEDES the hip/knee
## crop-and-hinge rig (_leg_knee/_leg_shin, leg_gait_cycle.gd) that used to
## fake motion out of a single pose -- real art beats a synthetic
## approximation of it, so that whole system is retired (its own nodes stay
## in the .tscn, just permanently hidden -- see _apply_legs) rather than
## restructuring the scene file over it.
var _leg_walk_frames: Array[ImageTexture] = []

## Which of hero_composite.png's 8 pre-colored outfit rows this view is
## currently wearing on body/legs/arms -- rolled once per apply_appearance
## call (see IllustratedCharacterSprite.outfit_variant_for) rather than once
## per part, so all three stay visually matched to the same outfit.
var _outfit_variant := 0


func _ready() -> void:
	# Every part's art is authored DETAIL_MULTIPLIER times oversized for
	# pixel detail; scaling the sprites back down is what keeps the hero at
	# their world size and keeps this scene's part positions (in world
	# units) correct (see docs/concept/art_resolution.md).
	for part in [
		_body, _head, _leg_left, _leg_right, _arm_left, _arm_right, _head_slot, _tool_slot,
		_chest_slot, _legs_slot, _feet_slot,
	]:
		part.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE

	# Shrinks the whole rig (this node, not the individual parts above) down
	# to SCALE's fraction of a tree's height -- see SCALE's own doc comment.
	# Applied on the CharacterView node itself so it scales every part AND
	# their .tscn positions uniformly, rather than needing every offset
	# constant in this file re-tuned by hand.
	scale = Vector2.ONE * SCALE

	# Torso submersion (see SubmersionShader) -- the player used to have NO
	# visual for being partway underwater at all: legs simply vanished and
	# the torso rendered exactly as it does on dry land (reported: "half the
	# torso should be under water"). Legs now share the SAME material
	# instance (see set_submersion_depth's own doc comment) rather than
	# being hidden outright -- "don't hide legs, just tint" -- so both parts
	# always agree on one waterline instead of two independent effects.
	_body.material = _submersion.shared_material()
	_leg_left.material = _submersion.shared_material()
	_leg_right.material = _submersion.shared_material()

	_leg_left_base_position = _leg_left.position
	_leg_right_base_position = _leg_right.position
	_arm_left_base_position = _arm_left.position
	_arm_right_base_position = _arm_right.position
	_tool_slot_base_position = _tool_slot.position
	_body_base_position = _body.position
	_head_base_position = _head.position

	# A look requested before this view was in the tree wins; otherwise a
	# default identity, so an unconfigured view still reads as a person
	# (see apply_appearance / HeroAppearance).
	if _pending_appearance.is_empty():
		apply_appearance(HeroAppearance.new().appearance_for("warrior", 0))
	else:
		apply_appearance(_pending_appearance)

	_arm_left.visible = false
	_arm_right.visible = false
	_head_slot.visible = false
	_tool_slot.visible = false
	_chest_slot.visible = false
	_legs_slot.visible = false
	_feet_slot.visible = false


func _process(delta: float) -> void:
	match movement_state:
		MovementState.WALKING:
			_cycle_time += delta * WALK_CYCLE_SPEED
			leg_swing_offset = sin(_cycle_time) * LEG_SWING_AMPLITUDE
			# Contralateral, not in-phase: real gait swings an arm opposite
			# the leg on its own side (left arm forward with right leg
			# forward), so this carries the OPPOSITE sign from
			# leg_swing_offset above, not the same one.
			arm_stroke_offset = -sin(_cycle_time) * ARM_SWAY_AMPLITUDE
		MovementState.SWIMMING:
			leg_swing_offset = 0.0
			if is_moving:
				_cycle_time += delta * SWIM_CYCLE_SPEED
				arm_stroke_offset = sin(_cycle_time) * ARM_STROKE_AMPLITUDE
			else:
				# Treading water: submerged, arms out, but not stroking.
				arm_stroke_offset = 0.0
		_:
			_cycle_time = 0.0
			leg_swing_offset = 0.0
			arm_stroke_offset = 0.0

	# Legs no longer vanish while swimming/wading -- see set_submersion_
	# depth's own doc comment ("don't hide legs, just tint"). LegRight's
	# fusion-hide is the one remaining reason either leg is ever invisible.
	_leg_left.visible = true
	_leg_right.visible = not _legs_are_fused
	# Used to be visible ONLY while swimming -- a leftover from when the flat
	# procedural torso rectangle was wide enough to visually stand in for a
	# whole upper body, arms included, and separate Arm sprites existed only
	# for the swimming stroke pose. hero_composite.png's illustrated torso
	# stops at the shoulder (see docs/concept/character_art_brief.md), so
	# that assumption no longer holds -- reported live: "no hands are
	# visible" while standing/walking. Arms now stay visible in every
	# movement state; only the STROKE animation itself (arm_stroke_offset
	# above) stays gated to actually swimming.
	_arm_left.visible = true
	_arm_right.visible = true

	if _legs_are_fused:
		# Real walk-cycle FRAMES now, not synthesized rotation or a lift
		# (see _leg_walk_frames' own doc comment for the fuller history --
		# rotation read as a left-right pendulum on a front-facing sprite
		# no matter the angle; a lift alone was reported as barely visible
		# motion). hero_composite.png's own outfit rows each carry several
		# real drawn leg poses now; this just steps through them in step
		# with the shared walk-cycle clock, the same one leg_swing_offset/
		# arm_stroke_offset above already use, so a full lap of _cycle_time
		# (2*PI, WALK_CYCLE_SPEED radians/sec) plays through the WHOLE
		# sequence once per stride rather than racing ahead of or lagging
		# behind everything else that's timed off it.
		if movement_state == MovementState.WALKING:
			var frame_count := _leg_walk_frames.size()
			if frame_count > 0:
				var phase_fraction := fposmod(_cycle_time, TAU) / TAU
				var frame_index := int(phase_fraction * frame_count) % frame_count
				_apply_leg_frame(frame_index)
		else:
			_apply_leg_frame(0)
	else:
		_leg_left.position = _leg_left_base_position + Vector2(0, leg_swing_offset)
		_leg_right.position = _leg_right_base_position + Vector2(0, -leg_swing_offset)
	_arm_left.position = _arm_left_base_position + Vector2(0, arm_stroke_offset)
	_arm_right.position = _arm_right_base_position + Vector2(0, -arm_stroke_offset)
	# A held weapon tracks ArmRight's OWN current position -- including its
	# walk/swim sway above -- rather than a fixed torso-side slot (reported
	# live: "the sword should be held by the actual hand"). GRIP_OFFSET
	# reaches from the arm sprite's own centre down toward where a hand
	# holds a hilt, plus the same facing-driven side shift set_facing always
	# applied, now stored in _tool_side instead of baked into a one-time
	# position write.
	_tool_slot.position = _arm_right.position + Vector2(_tool_side * TOOL_SLOT_SIDE_OFFSET, GRIP_OFFSET_Y)

	_apply_submersion_depth()

	if _swing_time_remaining > 0.0:
		_swing_time_remaining = maxf(0.0, _swing_time_remaining - delta)
		if _swing_time_remaining <= 0.0:
			_tool_slot.rotation = 0.0  # swing just finished -- rest, not frozen at full extension
		else:
			var progress := 1.0 - _swing_time_remaining / _swing_duration
			_tool_slot.rotation = _weapon_swing.rotation_at(progress, _swing_facing)
	else:
		_tool_slot.rotation = 0.0


## Updates facing from a movement direction; a near-zero direction (idle)
## leaves the previous facing unchanged rather than snapping to a default.
func set_facing(direction: Vector2) -> void:
	if direction.length() < 0.01:
		return

	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0 else Facing.UP

	_tool_side = 0.0
	if facing == Facing.RIGHT:
		_tool_side = 1.0
	elif facing == Facing.LEFT:
		_tool_side = -1.0
	_tool_slot.z_index = -1 if facing == Facing.UP else 1


## Dresses this character as the given hero (see HeroAppearance): class-
## colored tunic with trim, DNA-picked skin/hair on the head, class leg
## colors, skin-toned arms. Call any time -- textures regenerate in place.
func apply_appearance(appearance: Dictionary) -> void:
	# Callers can dress a view before it has entered the scene tree (a
	# villager is built and dressed by VillageRenderer, whose parent node
	# may not itself be in the tree yet). @onready part refs are null until
	# then, so remember the look and apply it once _ready runs.
	if _body == null:
		_pending_appearance = appearance
		return
	# Which of hero_composite.png's 8 pre-colored outfits this hero wears --
	# DNA-derived like skin/hair/eyes already are (asked directly: no new
	# player-choosable axis, unlike head's own -- see IllustratedCharacterSprite
	# .outfit_variant_for's own doc comment), so it only needs rolling once
	# per dress rather than per part below.
	_outfit_variant = _illustrated.outfit_variant_for(appearance.get("seed", 0))
	_apply_head(appearance)
	_apply_body(appearance)
	# Reads both Head's and Body's just-finished position/offset/scale, so it
	# has to run after both.
	_apply_neck(appearance)
	_apply_legs(appearance)
	_apply_arms(appearance)


## Body is the simple case among the three hero_composite parts: one drawing
## per outfit row, one world slot, no fusion/splitting question the way legs/
## arms each have their own (see _apply_legs/_apply_arms). Pre-colored art,
## so -- same rule the illustrated head follows -- modulate must stay WHITE
## rather than re-tinting an already-colored texture.
## Sprite2D centers its TEXTURE on `.position` by default -- true content-
## center-at-position semantics for the old flat, padding-free procedural
## art, but hero_composite.png's parts are normalized onto
## IllustratedCharacterSprite.CANVAS_SIZE, a shared canvas taller than most
## parts' own content, with that content baseline-anchored near the BOTTOM
## of it rather than centered within it (see CANVAS_SIZE/BASELINE_Y's own
## doc comment). Left uncorrected, Sprite2D centers the whole PADDED CANVAS
## on `.position` instead of the visible content -- and since the empty
## padding sits mostly ABOVE the content (baseline near the bottom), the
## actual art renders noticeably LOWER than `.position` alone would
## suggest. For a tall part like body this pushed the torso's own art down
## far enough to visually cover the legs entirely (reported live: "still no
## legs" / "back to the old procedural version" even with real,
## uncontaminated leg art correctly wired -- see IllustratedCharacterSprite.
## _primary_content_rect's own doc comment for the separate fragment-
## contamination bug fixed alongside this one; that fix alone wasn't
## enough, because it was never the only problem).
##
## Returns the `.offset.y` (in UNSCALED texture-PIXEL units -- Sprite2D
## scales it by `.scale` itself, same as it scales the texture) that shifts
## the drawn texture so the CONTENT's own vertical center -- not the padded
## canvas's -- lands on `.position`, restoring the old flat-art semantics
## exactly regardless of how tall a given outfit row's content happens to
## be.
##
## Takes the ACTUAL measured content height in raw pixels, not
## target_world_height / scale -- that back-derivation was correct only
## when scale came straight out of composite_part_scale_for/head_scale_for
## (which IS target_world_height / measured_content_height, so dividing
## back out recovers it exactly), but silently wrong once
## _width_bounded_scale can hand back a SMALLER, width-driven scale
## instead: dividing target_world_height by that smaller scale then
## overestimates the true content height, offsetting the content further
## than it should go. Body was firmly enough re-centred already that this
## stayed invisible at BODY_SIZE-scale sizes, but became a real, measurable
## error once _apply_neck needed the exact same edge to the pixel to size a
## bridge against it. Pass the real pixel height (trimmed_composite_image /
## trimmed_head_image's own `.get_height()`) instead and this whole class
## of drift is impossible by construction.
func _composite_content_offset_y(
	content_height_px: float, canvas_height: float, baseline_y: float
) -> float:
	var content_center_y := baseline_y - content_height_px * 0.5
	return canvas_height * 0.5 - content_center_y


## composite_part_scale_for/head_scale_for match CONTENT HEIGHT to a part's
## target world height alone, then CharacterView applies that SAME scale to
## width too (Sprite2D.scale is one uniform Vector2.ONE * scale) -- correct
## only when the source art's own aspect ratio already matches
## BODY_SIZE/LEG_SIZE/etc.'s own aspect, the assumption the old flat-
## rectangle procedural art satisfied by construction (drawn at EXACTLY that
## box, so matching height always meant matching width too).
## hero_composite.png's body column measures noticeably WIDER relative to
## its own height than BODY_SIZE's own aspect -- height-matching alone
## rendered the torso roughly 2x BODY_SIZE.x wide (reported live:
## "proportions are awfully wrong"). Clamped to whichever of width/height is
## more constraining -- the same "fit inside a box, preserve aspect, never
## stretch" rule normalize_frames already applies one canvas-normalization
## step up the pipeline -- so a part can render SHORTER than its target
## height when its own art is unusually wide, rather than ever wider than
## its target width.
func _width_bounded_scale(
	height_scale: float, trimmed_content: Image, target_world_width: float
) -> float:
	if trimmed_content == null or trimmed_content.get_width() <= 0:
		return height_scale
	var width_scale := target_world_width / float(trimmed_content.get_width())
	return minf(height_scale, width_scale)


func _apply_body(appearance: Dictionary) -> void:
	var textures := _illustrated.generate_composite_textures("body", _outfit_variant)
	# Checked on the ACTUAL result, not has_composite_part alone -- a
	# registered part can still come back empty for one specific outfit row
	# if that row's content doesn't land where expected (measured across
	# every row after exactly this happened live -- see
	# HERO_COMPOSITE_BAND_INDICES' own doc comment); falling back to procedural
	# here is a safety net against a FUTURE such gap, not a fix for a known
	# one (the known one is fixed at the source).
	if not textures.is_empty():
		_body.texture = textures[0]
		var trimmed_body := _illustrated.trimmed_composite_image("body", _outfit_variant)
		var body_scale := _illustrated.composite_part_scale_for(
			"body", _outfit_variant, float(BODY_SIZE.y)
		)
		body_scale = _width_bounded_scale(body_scale, trimmed_body, float(BODY_SIZE.x))
		_body.scale = Vector2.ONE * body_scale
		_body.offset.y = _composite_content_offset_y(
			trimmed_body.get_height(),
			IllustratedCharacterSprite.CANVAS_SIZE.y, IllustratedCharacterSprite.BASELINE_Y
		)
		_body.modulate = Color.WHITE
	else:
		_apply_paperdoll_part(
			_body, "body", appearance.tunic, BODY_SIZE, 0,
			func(): return _character_sprite.generate_hero_tunic_texture(ART_BODY_SIZE, appearance)
		)


## How wide the procedural neck bridge draws, in world units -- narrower
## than LEG_SIZE.x (a neck reads narrower than a leg) and, more importantly,
## narrower than HEAD_SIZE.x so it tucks visually under the head/collar
## rather than reading as its own separate wide block.
const NECK_WIDTH := 4
## Overlap into both Head's and Body's own measured edges -- generous, not
## the bare minimum, so most of the rectangle hides UNDER the head above
## and the collar below (drawn over it, since Neck sits before both in the
## .tscn's paint order... run last relative to Body specifically) and only
## a sliver bridges the actual visible gap. A first attempt at a small
## overlap (1.0) with the shaded-cylinder limb art arms/legs use (a full
## dark outline all the way around) read as an obvious floating rectangle
## rather than a neck (reported/seen live) -- fixed by both a bigger
## overlap AND a plain, borderless flat fill (see _apply_neck) instead of
## that outlined style, which is right for a LIMB's own silhouette but
## wrong for a bridge piece that is meant to mostly disappear.
const NECK_OVERLAP := 3.0

## Neither Head's nor Body's own art draws a neck, and both are positioned
## by their own measured CONTENT (see _composite_content_offset_y), which
## varies per outfit row/head cell -- so the gap between them isn't fixed
## either. Left unfilled, an appearance whose torso or head content happens
## to be shorter than usual shows bare background between the two (reported
## live: "the head is floating" / "the neck should be rendered
## procedurally"). Sized and positioned fresh each apply to exactly span
## whatever gap THIS appearance's own measured Head-bottom/Body-top edges
## leave -- the same measure-don't-assume approach the composite parts
## themselves use, rather than a fixed guess that would only fit one row.
## Must run after _apply_head and _apply_body, since it reads their
## finished position/offset/scale.
##
## Drawn as a plain, borderless flat fill -- not
## ProceduralCharacterSprite.generate_body_part_texture's shaded-cylinder
## limb style (a full dark outline all the way around), which is right for
## a LIMB's own silhouette but reads as an obvious floating rectangle for a
## bridge piece meant to mostly disappear under the head and collar (see
## NECK_OVERLAP's own doc comment). No DETAIL_MULTIPLIER oversampling
## either -- there is no fine detail here for it to buy.
func _apply_neck(appearance: Dictionary) -> void:
	var head_bottom := _head.position.y + _head.offset.y * _head.scale.y + float(HEAD_SIZE.y) * 0.5
	var body_top := (
		_body.position.y + _body.offset.y * _body.scale.y - _body_content_height_world() * 0.5
	)
	var gap := body_top - head_bottom
	if gap <= 0.5:
		# Head and body already meet or overlap for this appearance -- no
		# neck needed, and a zero/negative-height texture would be invalid.
		_neck.visible = false
		return
	_neck.visible = true
	var neck_height := gap + NECK_OVERLAP * 2.0
	var image := Image.create(NECK_WIDTH, maxi(1, roundi(neck_height)), false, Image.FORMAT_RGBA8)
	image.fill(appearance.skin)
	_neck.texture = ImageTexture.create_from_image(image)
	_neck.scale = Vector2.ONE
	_neck.position = Vector2(0, (head_bottom + body_top) * 0.5)
	_neck_base_position = _neck.position


## Body's actual rendered content height, in world units -- BODY_SIZE.y
## only when a row's own aspect let it hit that exactly; _width_bounded_scale
## can leave it shorter (see BODY_SIZE's own doc comment). Falls back to the
## flat BODY_SIZE.y for the procedural branch, which (ART_BODY_SIZE being
## exactly BODY_SIZE * ArtResolution.DETAIL_MULTIPLIER, undone by
## ArtResolution.SPRITE_SCALE) always renders at exactly that height by
## construction, so the two branches agree without _apply_neck needing to
## know which one is active.
func _body_content_height_world() -> float:
	var trimmed := _illustrated.trimmed_composite_image("body", _outfit_variant)
	if trimmed == null:
		return float(BODY_SIZE.y)
	return float(trimmed.get_height()) * _body.scale.y


## Arms genuinely split into two independent drawings in hero_composite.png
## (unlike the fused legs -- see IllustratedCharacterSprite's own doc
## comment on why), so -- unlike _apply_legs -- ArmLeft/ArmRight keep their
## own separate world slots and separate art, the same shape the OLD
## arms.png-sourced path always used.
func _apply_arms(appearance: Dictionary) -> void:
	var textures := _illustrated.generate_composite_textures("arms", _outfit_variant)
	# See _apply_body's own comment on why this checks the actual result,
	# not has_composite_part alone.
	if not textures.is_empty():
		_arm_left.texture = textures[0]
		var arm_left_scale := _illustrated.composite_part_scale_for(
			"arms", _outfit_variant, float(ARM_SIZE.y), 0
		)
		_arm_left.scale = Vector2.ONE * arm_left_scale
		_arm_left.offset.y = _composite_content_offset_y(
			_illustrated.trimmed_composite_image("arms", _outfit_variant, "front", 0).get_height(),
			IllustratedCharacterSprite.CANVAS_SIZE.y, IllustratedCharacterSprite.BASELINE_Y
		)
		_arm_left.modulate = Color.WHITE
		_arm_left.position = _arm_left_base_position
		# Almost every row's two arms are detached enough to split into two
		# frames, but not a guarantee the source art makes for every one --
		# a row whose art happens to fuse them (found by checking all 8, see
		# HERO_COMPOSITE_BAND_INDICES' own doc comment on the same class of
		# gap) falls back to ArmRight wearing the same single frame as
		# ArmLeft, which is a real cheat but a way smaller one than leaving
		# ArmRight showing whatever texture it happened to have before.
		var right_index := 1 if textures.size() > 1 else 0
		_arm_right.texture = textures[right_index]
		var arm_right_scale := _illustrated.composite_part_scale_for(
			"arms", _outfit_variant, float(ARM_SIZE.y), right_index
		)
		_arm_right.scale = Vector2.ONE * arm_right_scale
		_arm_right.offset.y = _composite_content_offset_y(
			_illustrated.trimmed_composite_image("arms", _outfit_variant, "front", right_index).get_height(),
			IllustratedCharacterSprite.CANVAS_SIZE.y, IllustratedCharacterSprite.BASELINE_Y
		)
		_arm_right.modulate = Color.WHITE
		_arm_right.position = _arm_right_base_position
	else:
		_apply_paperdoll_part(
			_arm_left, "arms", appearance.skin, ARM_SIZE, 0,
			func(): return _character_sprite.generate_body_part_texture(ART_ARM_SIZE, appearance.skin)
		)
		_apply_paperdoll_part(
			_arm_right, "arms", appearance.skin, ARM_SIZE, 1,
			func(): return _character_sprite.generate_body_part_texture(ART_ARM_SIZE, appearance.skin)
		)


## The head mixes skin tone, hair color/style, beard and eye color in one
## drawing, which is why it is not just another _apply_paperdoll_part call --
## see IllustratedCharacterSprite's own doc comment on why a single flat
## modulate can't separate those out. The illustrated path recolors by
## luminance instead (baking the DNA skin tone directly into the pixels), so
## its own modulate must stay WHITE -- tinting an already-tinted texture
## would double the color. Hair is a known gap on the illustrated path (see
## the art brief): head.png's 100 faces are all bald, so an illustrated hero
## currently reads bald regardless of the DNA-picked hair_style/hair color.
func _apply_head(appearance: Dictionary) -> void:
	var cell_index: int = appearance.get("head_index", 0)
	if _illustrated.has_usable_head(cell_index, appearance.skin):
		_head.texture = _illustrated.generate_head_texture(cell_index, appearance.skin)
		var head_scale := _illustrated.head_scale_for(cell_index, float(HEAD_SIZE.y))
		_head.scale = Vector2.ONE * head_scale
		_head.offset.y = _composite_content_offset_y(
			_illustrated.trimmed_head_image(cell_index, appearance.skin).get_height(),
			IllustratedCharacterSprite.HEAD_CANVAS_SIZE.y, IllustratedCharacterSprite.HEAD_BASELINE_Y
		)
		_head.modulate = Color.WHITE
	else:
		_head.texture = _character_sprite.generate_hero_head_texture(ART_HEAD_SIZE, appearance)
		_head.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
		_head.modulate = Color.WHITE


## Legs are the one paperdoll slot that does not map 1:1 onto LegLeft/
## LegRight the way every other part does. The procedural fallback still
## needs two independently-positioned leg sprites -- the walk cycle bobs them
## in OPPOSITE directions (see _process), which is what makes a two-legged
## gait read at all. The illustrated art draws both legs together as one
## fused PAIR (see IllustratedCharacterSprite's own doc comment on why), so
## it is worn as TWO sprites covering both world slots between them instead:
## LegLeft is the HIP pivot, wearing the THIGH crop (see
## IllustratedCharacterSprite.composite_leg_segments) and centred where the
## fused pair used to sit as one whole sprite; LegLeftKnee/LegLeftShin (its
## children -- see the .tscn) are the KNEE pivot and the SHIN crop.
## LegRight is hidden outright, same as before. _legs_are_fused records
## which mode is active so _process knows to drive the hip/knee pivot chain
## with a real gait (see leg_gait_cycle.gd) instead of the procedural
## fallback's independent per-leg position swing.
func _apply_legs(appearance: Dictionary) -> void:
	var textures := _illustrated.generate_composite_textures("legs", _outfit_variant)
	# See _apply_body's own comment on why this checks the actual result,
	# not has_composite_part alone.
	if not textures.is_empty():
		_leg_left.modulate = Color.WHITE
		_leg_left.rotation = 0.0
		_leg_fused_rest_position = (_leg_left_base_position + _leg_right_base_position) * 0.5
		# The hip/knee crop-and-hinge rig used to live here (LegLeftKnee/
		# LegLeftShin) -- retired now that hero_composite.png carries real
		# walk-cycle frames for the legs (see _leg_walk_frames' own doc
		# comment): real art beats synthesizing motion from one static
		# pose. The nodes stay in the .tscn, just permanently hidden, so
		# they never show a stale texture from before this pass.
		_leg_knee.rotation = 0.0
		_leg_shin.visible = false
		_leg_walk_frames = textures
		_apply_leg_frame(0)
		_legs_are_fused = true
	else:
		_apply_paperdoll_part(
			_leg_left, "legs", appearance.legs, LEG_SIZE, 0,
			func(): return _character_sprite.generate_body_part_texture(ART_LEG_SIZE, appearance.legs)
		)
		_apply_paperdoll_part(
			_leg_right, "legs", appearance.legs, LEG_SIZE, 0,
			func(): return _character_sprite.generate_body_part_texture(ART_LEG_SIZE, appearance.legs)
		)
		_leg_left.position = _leg_left_base_position
		_leg_left.rotation = 0.0
		_leg_knee.rotation = 0.0
		# No knee crop on the procedural fallback (flat rectangles, no
		# hip/knee split art) -- hidden rather than left showing a stale
		# illustrated-path texture from a previous appearance.
		_leg_shin.visible = false
		_legs_are_fused = false


## Shows walk-cycle frame `frame_index` of _leg_walk_frames -- scaled,
## width-clamped, and positioned exactly the way _apply_legs' own
## single-frame version always was, just re-measured per FRAME instead of
## once per appearance: real walk-cycle poses can genuinely differ in
## their own drawn height (a mid-stride pose often reads a little shorter
## than a standing one), so re-measuring per frame lets the character's
## own real art drive a small natural vertical bob as a side effect,
## rather than needing a second synthetic bob layered on top of real
## animated art. Called once at rest (frame 0, a neutral standing pose)
## and again every WALKING frame from _process to actually step through
## the sequence (see that function's own doc comment).
func _apply_leg_frame(frame_index: int) -> void:
	if _leg_walk_frames.is_empty():
		return
	var index := clampi(frame_index, 0, _leg_walk_frames.size() - 1)
	var trimmed := _illustrated.trimmed_composite_image("legs", _outfit_variant, "front", index)
	var legs_scale := _illustrated.composite_part_scale_for(
		"legs", _outfit_variant, float(LEG_SIZE.y), index
	)
	# The fused pair spans BOTH world slots, so its own width bound is
	# twice a single leg's -- see _width_bounded_scale's own doc comment,
	# and LEG_SIZE.x's own doc comment for why this clamp exists at all
	# (reported live: "unproportional ... walks like a duck").
	legs_scale = _width_bounded_scale(legs_scale, trimmed, float(LEG_SIZE.x * 2))
	_leg_left.texture = _leg_walk_frames[index]
	_leg_left.scale = Vector2.ONE * legs_scale
	_leg_left.offset.y = _composite_content_offset_y(
		trimmed.get_height() if trimmed != null else float(IllustratedCharacterSprite.BASELINE_Y),
		IllustratedCharacterSprite.CANVAS_SIZE.y, IllustratedCharacterSprite.BASELINE_Y
	)
	_leg_left.position = _leg_fused_rest_position


## Uses illustrated art for `part_name` (tinted `tint` via modulate -- see
## IllustratedCharacterSprite's "draw parts neutral" convention) if any is
## registered, falling back to the procedural texture `generate_procedural`
## builds otherwise -- the same has-art-then-fallback shape CreatureMarker
## uses for illustrated animal species.
##
## `target_world_size`/`frame_index` drive the illustrated branch's scale
## (see IllustratedCharacterSprite.part_scale_for): every part is normalized
## onto ONE shared working canvas (CANVAS_SIZE), not one sized per part, so
## the flat ArtResolution.SPRITE_SCALE the procedural branch uses would
## render an illustrated part at the wrong size -- each part's Sprite2D scale
## has to be measured from what actually got drawn, not assumed from the
## canvas. `frame_index` matters for arms specifically: its two poses are
## independent crops (not a mirrored copy), so ArmLeft and ArmRight must each
## measure THEIR OWN frame, not frame 0 for both.
func _apply_paperdoll_part(
	part: Sprite2D, part_name: String, tint: Color, target_world_size: Vector2i,
	frame_index: int, generate_procedural: Callable
) -> void:
	if _illustrated.has_action(part_name, "idle"):
		var frames := _illustrated.generate_textures(part_name, "idle")
		part.texture = frames[clampi(frame_index, 0, frames.size() - 1)]
		part.modulate = tint
		part.scale = Vector2.ONE * _illustrated.part_scale_for(
			part_name, float(target_world_size.y), frame_index
		)
	else:
		part.texture = generate_procedural.call()
		part.modulate = Color.WHITE
		part.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE


func set_movement_state(state: MovementState) -> void:
	movement_state = state
	# You can't swing a sword while swimming: the weapon is stowed (hidden)
	# in the water and re-drawn when back on land. _equipped_slots still
	# remembers it's equipped -- this is purely visual stowing.
	if _tool_slot != null and _equipped_slots.get("tool", false):
		_tool_slot.visible = state != MovementState.SWIMMING


## Sets the real, continuous water depth (in meters) this rig is standing
## in. Player calls this every frame with the SAME depth _resolve_water_
## state already computes from real ocean/river/lake depth -- a value that
## used to be computed and immediately discarded once collapsed into the
## coarse walking/wading/swimming/drowning mode string, which is why
## wading (anything short of the full swim threshold) had no visual
## signature at all until this existed (reported: wading in from the
## shore should gradually tint and sink, not snap from nothing straight to
## "half the torso submerged" at the swim line).
##
## Replaces the old hard "legs vanish the instant you start swimming"
## switch with the SAME shared SubmersionShader material the torso already
## used ("don't hide legs, just tint" -- a swimming character's legs are
## genuinely fully underwater, exactly where a waterline anchored at the
## torso's own centre already puts them, so no separate leg-specific
## waterline was needed, only the hide switch removed).
func set_submersion_depth(depth_meters: float) -> void:
	_submersion_depth_meters = depth_meters


## How much of the rig is below the water, as a smooth [0, 1] fraction --
## the one signal driving both the waterline and the visual sink below.
## Reuses WaterMovementModel.WADE_DEPTH_METERS -- the SAME tested
## threshold that already separates "wading" from "swimming" for movement
## speed -- as the normalizing depth, rather than inventing a second,
## unrelated hand-picked one: at that real depth the character is already
## fully swimming (floating, not walking a riverbed), which is exactly
## where this fraction should reach 1.0 too.
##
## _submersion_depth_meters defaults to -1.0, a sentinel for "no caller
## has ever set a real depth" (as opposed to a real, measured zero) --
## callers that only ever say "swimming or not" via movement_state (the
## character-creator diorama, village NPCs; see character_preview_
## diorama.gd/npc_marker.gd, neither of which has real river/ocean/lake
## depth to hand) never call set_submersion_depth at all, so they fall
## back to treating SWIMMING as "at least wade-depth deep" -- keeping
## their existing full-torso-tint look exactly as it was before this.
func _submersion_fraction() -> float:
	var depth_meters := _submersion_depth_meters
	if depth_meters < 0.0:
		depth_meters = (
			WaterMovementModel.WADE_DEPTH_METERS if movement_state == MovementState.SWIMMING else 0.0
		)
	return clampf(depth_meters / WaterMovementModel.WADE_DEPTH_METERS, 0.0, 1.0)


## How far the whole rig visually sinks (in local pixels, before this
## node's own SCALE) at full wade depth -- suggesting a riverbed that
## actually slopes down toward the channel as you wade in, rather than a
## character floating at a fixed height regardless of how deep the water
## beneath them already is. Shared with animals (CreatureMarker) via
## SubmersionShader.MAX_SINK_PX -- see that constant's own doc comment for
## why this lives there rather than as a second, independently-tuned
## value here. Pinned by test_full_wade_depth_sinks_the_body_by_the_full_
## constant rather than left as an eyeballed comment.
const MAX_SUBMERSION_SINK_PX := SubmersionShader.MAX_SINK_PX


## Drives both visible consequences of _submersion_fraction: the shared
## shader's waterline (tint) and a small downward sink applied on TOP of
## whatever _process already computed for each part this frame (walk
## swing, swim stroke, weapon stow/re-equip, the fused-leg walk-cycle
## frame...) -- additive, so it never needs to know which of those set a
## given part's position, only to nudge the result down afterward. Called
## once, last, at the end of _process.
func _apply_submersion_depth() -> void:
	var fraction := _submersion_fraction()

	# The waterline is a FIXED external reference (the real water surface),
	# never the rig's own cosmetic sink below -- anchored on the stable
	# _body_base_position constant, not on _body's live (already-sunk)
	# position this frame, so the two effects can't compound each other.
	if fraction > 0.0:
		_submersion.set_waterline(global_position.y + lerpf(0.0, _body_base_position.y, fraction))
	else:
		_submersion.clear_waterline()

	var sink := lerpf(0.0, MAX_SUBMERSION_SINK_PX, fraction)
	_leg_left.position.y += sink
	_leg_right.position.y += sink
	_arm_left.position.y += sink
	_arm_right.position.y += sink
	_tool_slot.position.y += sink
	_body.position = _body_base_position + Vector2(0, sink)
	_head.position = _head_base_position + Vector2(0, sink)
	if _neck.visible:
		_neck.position = _neck_base_position + Vector2(0, sink)


func legs_visible() -> bool:
	return _leg_left.visible


## Whether legs are currently worn as one fused illustrated pair (LegLeft
## only) rather than two independent sprites -- see _apply_legs.
func legs_are_fused() -> bool:
	return _legs_are_fused


func equip_slot(slot_name: String, color: Color) -> void:
	var node := _slot_node(slot_name)
	if node == null:
		return
	_set_solid_texture(node, ART_SLOT_SIZE, color)
	node.visible = true
	_equipped_slots[slot_name] = true


func unequip_slot(slot_name: String) -> void:
	var node := _slot_node(slot_name)
	if node == null:
		return
	node.visible = false
	_equipped_slots.erase(slot_name)


func is_slot_equipped(slot_name: String) -> bool:
	return _equipped_slots.get(slot_name, false)


## Shows the weapon's actual sprite in the tool slot (real item art, not the
## flat-color placeholder equip_slot() uses). Shifts the sprite's rotation
## pivot to the grip -- the bottom edge of the image, per ProceduralItemSprite's
## convention for sword/axe art -- so play_attack_swing's rotation sweeps the
## blade through an arc instead of spinning it in place around its own center.
func equip_weapon(texture: Texture2D) -> void:
	_tool_slot.texture = texture
	_tool_slot.offset = Vector2(0, -texture.get_height() / 2.0)
	_tool_slot.visible = true
	_equipped_slots["tool"] = true


## Starts a swing animation of the equipped weapon: a pendulum arc (see
## WeaponSwing) oriented horizontally for left/right facing or vertically for
## up/down, played out over `duration` seconds and reset to idle afterward.
func play_attack_swing(facing: String, duration: float) -> void:
	_swing_facing = facing
	_swing_duration = duration
	_swing_time_remaining = duration


func tool_slot_rotation() -> float:
	return _tool_slot.rotation


func tool_slot_texture() -> Texture2D:
	return _tool_slot.texture


func tool_slot_offset() -> Vector2:
	return _tool_slot.offset


func _slot_node(slot_name: String) -> Sprite2D:
	match slot_name:
		"head":
			return _head_slot
		"chest":
			return _chest_slot
		"legs":
			return _legs_slot
		"feet":
			return _feet_slot
		"tool":
			return _tool_slot
		_:
			return null


## Shows `texture` -- an armor piece's own generated icon (see Item.sprite_id/
## docs/concept/item_illustrations.md) -- in the given slot. The real-art
## equivalent of equip_weapon() above for "head"/"chest"/"legs"/"feet" (see
## Equipment.SLOTS), rather than equip_slot()'s flat-color placeholder: armor
## should look like the same item art already shown everywhere else, not a
## second, disconnected system.
func equip_armor_slot(slot_name: String, texture: Texture2D) -> void:
	var node := _slot_node(slot_name)
	if node == null:
		return
	node.texture = texture
	node.visible = true
	_equipped_slots[slot_name] = true


## The texture currently shown in `slot_name`, or null for an unknown slot or
## one nothing has equipped into yet -- lets a caller (or a test) verify what
## a slot is actually displaying without reaching past this class into the
## Sprite2D node itself.
func slot_texture(slot_name: String) -> Texture2D:
	var node := _slot_node(slot_name)
	return node.texture if node != null else null


func _set_solid_texture(sprite: Sprite2D, size: Vector2i, color: Color) -> void:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	sprite.texture = ImageTexture.create_from_image(image)
