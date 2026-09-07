extends StaticBody2D

## A tree that can be felled with an axe (see Player._perform_attack),
## dropping wood. Deliberately defines NO _process -- thousands of these are
## loaded at once, so any per-frame behavior here would tank the frame rate
## (the same constraint ForageScheduler's centralized ticking exists to
## avoid). take_damage() is only ever called on demand by the attacker, so
## having a script here costs nothing at runtime until that happens.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Health = preload("res://src/gameplay/health.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const TreeMorphShader = preload("res://src/rendering/tree_morph_shader.gd")

const GROUP_NAME := "tree"
const MAX_HEALTH := 30.0
const WOOD_DROP_COUNT := 3
const STICK_DROP_COUNT := 2

var health := MAX_HEALTH
var _health := Health.new()

## Set by TreeRenderer so this tree can re-render its own canopy with its
## current ripe-fruit crop (see set_ripe_fruit) -- fruit phenology is driven
## centrally (EarthChunkManager.step_fruiting) only for trees near the player,
## so most trees never pay this cost.
var species_bias := 0.5
var sprite_seed := 0
var _canopy_sprite: Sprite2D
var _ripe_count := -1  # -1 == "never set", so the first update always renders
## The season this tree's canopy is currently drawn in (see IllustratedTree).
## Empty until set, so the first update always renders.
var _season := ""
## The season it is turning INTO, and how far along (see SeasonTransition).
## Part of the drawn state, so a tree redraws as the turn advances rather than
## only when the season name finally changes -- which is what made the change
## happen all at once.
var _turning_into := ""
var _turn_progress := 0.0
## How much snow lies on this tree's canopy right now (see TreeRenderer.
## set_snow_coverage / EarthChunkManager._snow_depth) -- pushed in alongside
## season/turn because it is the SAME shape of fact: a live value for the
## whole world at once, not an independent per-tree one the way growth_scale
## is. Deliberately NOT a season: docs/concept/seasons.md's "canopy is on
## the clock" reasoning is about which of the four SEASON frames a tree
## wears, and does not extend to how much of it is under snow -- that stays
## a live-weather quantity, same as the ground's own lying snow.
var _snow_coverage := 0.0
## How much of its canopy this tree has actually put out.
##
## Part of the DRAWN state, not just the node scale: a young tree has fewer
## branches, and scaling the whole node drew a sapling as a full-grown tree in
## miniature -- crown, boughs and every twig, only small. Growth reaching the
## canopy is what makes a sapling look like a sapling.
var _drawn_growth := -1.0
var _tree_sprite_generator := ProceduralTreeSprite.new()
## The sapling art (see IllustratedTree's own "sapling growth sequence"
## section) this tree draws from below TreeGrowth.BRANCH_START_FRACTION, and
## dissolves out of via TreeMorphShader above it. A plain instance, mirroring
## _tree_sprite_generator's own shape -- IllustratedTree's actual sapling
## frames are cached STATIC on that class, so every ChoppableTree sharing one
## instance each costs nothing extra.
var _illustrated_art := IllustratedTree.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)


## For World's mouse-hover tooltip (see HoverTargetFinder). Names its real
## stage (see docs/concept/woodworking.md): standing, felled-with-canopy, or
## a bare trunk once the crown is off.
func get_display_name() -> String:
	if not _felled:
		return "Tree"
	return "Bare Trunk" if _canopy_removed else "Fallen Tree"


## For World's mouse-hover tooltip (see HoverTargetFinder). Bound to "attack"
## because that is the input Player._chop_step actually reads (see
## Player._perform_attack). A bare trunk additionally offers Saw -- shown
## regardless of whether the player currently has a saw + enough Carpentry
## to actually use it (informational, same "show every possible action"
## convention every other multi-action hover already follows -- see e.g.
## LiftableStone's Pick Up + Kick).
func get_hover_actions() -> Array:
	var actions := [{"verb": "Chop", "action": "attack"}]
	if _felled and _canopy_removed:
		actions.append({"verb": "Saw", "action": "attack"})
	return actions


## Registers the canopy sprite so set_ripe_fruit can swap its texture.
func bind_canopy(sprite: Sprite2D) -> void:
	_canopy_sprite = sprite


## Shows `count` ripe fruits on the canopy, drawn for `season`, under
## `snow_coverage` of snow (see the field's own doc comment -- a live
## weather fact, not another season).
##
## No-op unless something actually changed (avoids regenerating the texture
## every tick) or the canopy isn't bound. Season and crop share one entry
## point because they share one texture: regenerating for a new season would
## otherwise silently drop the fruit already on the tree. Snow is compared
## by its QUANTISED level (see ProceduralTreeSprite.snow_level), not the raw
## float: lying snow accumulates continuously, and comparing raw values
## would redraw every tree in range on every single accumulation tick --
## the same cost class as the compositing slowdown this codebase already
## fixed once (see ProceduralTreeSprite's own "why these caches exist").
func set_ripe_fruit(
	count: int, for_season: String = "", turning_into: String = "", turn_progress: float = 0.0,
	snow_coverage: float = 0.0
) -> void:
	if _canopy_sprite == null:
		return
	if (
		count == _ripe_count
		and for_season == _season
		and turning_into == _turning_into
		and is_equal_approx(turn_progress, _turn_progress)
		and is_equal_approx(_canopy_growth(), _drawn_growth)
		and is_equal_approx(
			ProceduralTreeSprite.snow_level(snow_coverage),
			ProceduralTreeSprite.snow_level(_snow_coverage)
		)
	):
		return
	_ripe_count = count
	_season = for_season
	_turning_into = turning_into
	_turn_progress = turn_progress
	_snow_coverage = snow_coverage
	_redraw_canopy()


## The season this tree is currently drawn in.
## The canopy fraction this tree draws at, quantised the way the sprite cache
## quantises it -- so a tree growing by a hair does not count as a change and
## rebuild its texture every frame.
func _canopy_growth() -> float:
	return ProceduralTreeSprite.growth_level(growth_scale)


## ## Two phases, ONE redraw entry point
##
## Below TreeGrowth.BRANCH_START_FRACTION a tree is still a bare, unbranched
## shoot -- it draws from IllustratedTree's real sapling art (see
## refresh_sapling_display) and never touches generate_texture_with_fruit at
## all, since there is no "mature" picture to speak of yet. At and above it,
## this draws the REAL, FULLY mature texture (growth pinned to 1.0, not
## _drawn_growth -- see below) and lets TreeMorphShader dissolve the sapling
## sheet's last frame OUT of it as canopy_growth_fraction climbs, clearing
## the morph outright once that reaches 1.0 so a fully-grown tree renders
## through today's exact, unmodified path with zero shader overhead.
##
## `growth` is passed as a literal 1.0 here, not _drawn_growth (still
## computed below, unchanged, for set_ripe_fruit's OWN "did anything change"
## comparison -- see _canopy_growth's doc comment): ProceduralTreeSprite.
## growth_level clamps and quantises to GROWTH_LEVELS, so growth_level(x) is
## already pinned at exactly 1.0 for any x >= 5/6 -- which _drawn_growth
## always is by the time this branch can even run (BRANCH_START_FRACTION is
## 0.595, comfortably below that). The OLD "fewer branches at lower growth"
## picture that _drawn_growth would otherwise still ask for between 0.595
## and 5/6 is exactly the range this feature replaces with the new dissolve
## -- asking for anything less than the full picture there would draw a
## half-branched tree UNDER a dissolve that is already trying to show the
## canopy filling in, encoding "how grown" twice over.
func _redraw_canopy() -> void:
	if _canopy_sprite == null:
		return
	_drawn_growth = _canopy_growth()
	if _tree_growth.sapling_progress(growth_scale) < 1.0:
		refresh_sapling_display()
		return
	if _season == "":
		return
	_canopy_sprite.texture = _tree_sprite_generator.generate_texture_with_fruit(
		species_bias,
		sprite_seed,
		maxi(_ripe_count, 0),
		_season,
		_turning_into,
		_turn_progress,
		1.0,
		_snow_coverage
	)
	var material := _canopy_sprite.material as ShaderMaterial
	if material == null:
		return
	var canopy_growth := _tree_growth.canopy_growth_fraction(growth_scale)
	if canopy_growth >= 1.0:
		TreeMorphShader.clear(material)
	else:
		TreeMorphShader.apply(
			material,
			_illustrated_art.sapling_frame(_illustrated_art.sapling_frame_count() - 1),
			ProceduralTreeSprite.tree_variant_for(sprite_seed),
			canopy_growth
		)


## Shows this tree's real sapling art immediately, if it is still below
## TreeGrowth.BRANCH_START_FRACTION -- the ONE place that actually reads the
## sapling sheet, called both from _redraw_canopy's own first branch and
## directly by TreeRenderer right after a fresh tree is bound (see
## TreeRenderer._build_tree_node), before this tree has ever had a season
## synced to it at all.
##
## That second call site is not a convenience: a freshly-spawned sapling's
## sprite starts out holding TreeRenderer's shared, always-fully-grown
## cached texture (see TreeRenderer._texture_for, which has no per-tree
## growth to key on), and _redraw_canopy would otherwise only ever correct
## that once this tree's OWN _season/_drawn_growth first change -- which
## depends on an unrelated season-sync tick reaching it. Calling this once,
## directly, the moment the canopy sprite exists closes that exact window --
## the "miniaturized full canopy" bug as originally reported, at its worst:
## a mid-session seed spawning right in front of the player.
##
## A no-op past the sapling phase, so a caller never has to check first.
func refresh_sapling_display() -> void:
	if _canopy_sprite == null:
		return
	var sapling_progress := _tree_growth.sapling_progress(growth_scale)
	if sapling_progress >= 1.0:
		return
	_canopy_sprite.texture = _illustrated_art.sapling_frame_for_progress(sapling_progress)
	var material := _canopy_sprite.material as ShaderMaterial
	if material != null:
		TreeMorphShader.clear(material)


func current_season() -> String:
	return _season


## The crop currently drawn on this tree. Lets a season change redraw the
## canopy without knowing, or losing, the fruit already on it.
func ripe_fruit_count() -> int:
	return maxi(_ripe_count, 0)


## Reduces health; felling drops nothing yet (see docs/concept/woodworking.md
## -- the tree is a real thing lying there, not a loot spray) and frees the
## tree once fully worked up (its collision goes with it, same as any other
## queue_free()'d node). A swing lands on this tree.
##
## Standing, it takes damage until it FALLS -- and then it is still there, on
## its side, holding all its timber. Fallen, the FIRST swing limbs the crown
## off (sticks); every swing after that bucks one length off the bare trunk
## into logs, until the trunk is used up. See saw_up() for the alternative,
## tool+skill-gated way to finish a bare trunk in one action instead.
func take_damage(amount: float) -> void:
	if _felled:
		if not _canopy_removed:
			_remove_canopy()
		else:
			_cut_up()
		return
	health = _health.take_damage(health, amount)
	if _health.is_dead(health):
		_fall()


## Whether this tree has been felled and is lying there.
func is_felled() -> bool:
	return _felled


var _felled := false
## Whether the crown has already been limbed off (see _remove_canopy) --
## once true, further swings work the bare trunk itself.
var _canopy_removed := false
var _cuts_left := FelledTree.CUTS_TO_CLEAR


## Topples the tree: same sprite, on its side, still carrying its timber.
func _fall() -> void:
	_felled = true
	_canopy_removed = false
	_cuts_left = FelledTree.CUTS_TO_CLEAR
	rotation = FelledTree.FALLEN_ROTATION * float(FelledTree.fall_direction(sprite_seed))
	# A fallen trunk lies ON the ground rather than standing on it, so it stops
	# blocking the way and stops sorting like a standing tree.
	z_index = -1
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)


## The first swing on a freshly-felled tree: limbs the crown off as sticks.
## Real forestry practice (limb before bucking), not an invented game step --
## see docs/concept/woodworking.md. Does not consume one of the trunk's own
## CUTS_TO_CLEAR.
##
## Actually swaps what's drawn, not just the state flag -- reported live: a
## tree still showed its full canopy after this fired, since flipping
## _canopy_removed alone never told the canopy sprite to redraw.
func _remove_canopy() -> void:
	_canopy_removed = true
	var sticks_count := FelledTree.sticks_from_canopy(growth_scale)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("stick", "Stick", "material", 40), sticks_count), position
	)
	if _canopy_sprite != null:
		_canopy_sprite.texture = _tree_sprite_generator.generate_bare_trunk_texture(
			species_bias, sprite_seed, _season
		)


## Bucks one length off the bare trunk into a real log.
func _cut_up() -> void:
	var log_count := FelledTree.logs_per_cut(growth_scale)
	_cuts_left -= 1
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("log", "Log", "material", 20), log_count), position
	)
	if _cuts_left <= 0:
		queue_free()


## Saws the ENTIRE remaining bare trunk into beam + plank in one action,
## skipping the per-swing log split -- the tool+skill-gated alternative to
## _cut_up (see docs/concept/woodworking.md). Returns whether it happened:
## false (a no-op) unless this is actually a bare, not-yet-fully-worked
## trunk, so a caller (Player._chop_step) can just try this first and fall
## back to the ordinary chop otherwise.
func saw_up() -> bool:
	if not _felled or not _canopy_removed or _cuts_left <= 0:
		return false
	var beam_count := FelledTree.beams_from_trunk(growth_scale, _cuts_left)
	var plank_count := FelledTree.planks_from_trunk(growth_scale, _cuts_left)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("beam", "Beam", "material", 20), beam_count), position
	)
	WorldItemBus.item_dropped.emit(
		ItemStack.new(Item.new("plank", "Plank", "material", 20), plank_count),
		position + Vector2(8, 4)
	)
	_cuts_left = 0
	queue_free()
	return true


## When this tree was planted, on the world clock. Trees that predate the
## session are already grown and leave this at zero.
var planted_at := 0.0

## A tree's own growth, kept up to date rather than frozen at spawn.
##
## `growth_scale` used to be assigned once by TreeRenderer, from the tree's age
## at the moment it was built, and nothing ever touched it again: a sapling you
## watched stayed a seedling for as long as you watched it, and the only way to
## see one mature was to walk far enough away for its chunk to unload and then
## come back. Reported as newborn trees not maturing properly.
func set_age(age_seconds: float) -> void:
	growth_scale = _tree_growth.scale_at(age_seconds)
	# Growing is a redraw as well as a resize. The guard in set_ripe_fruit
	# compares crop and season, and age is neither, so it would otherwise read
	# a grown tree as "nothing changed" and keep the sapling's canopy.
	_redraw_canopy()


## How many times a bee has visited this tree so far in its CURRENT bearing
## cycle (see FruitingModel.pollination_factor / docs/concept/flora.md), and
## which cycle that count belongs to.
##
## crop_potential is a pure function of the genome and elapsed time -- there
## is no persisted per-tree state anywhere else for a visit to land in, so
## this is where it lives, the same tier as this node's other per-tree state
## (growth_scale, _ripe_count). Deliberately survives only as long as this
## node does: it does NOT persist across a chunk unload/reload or a save,
## which is an explicit simplification for this pass (see docs/progress.md) --
## a chunk that unloads mid-cycle loses count of visits nobody was watching
## anyway, the same way a sapling's growth is re-derived rather than saved.
var _pollination_visits := 0.0
var _pollination_visits_cycle := -1


## Records one bee visit at world time `now`, within a bearing cycle
## `bearing_cycle_seconds` long. Rolls the count over to zero the moment `now`
## falls in a LATER cycle than the one already being counted, so a visit from
## last year can never go on boosting this year's crop.
##
## `visit_weight` defaults to a flat 1.0 (an ordinary visit) but a caller can
## bank more or less, scaled by the visiting bee's own AnimalFitness.
## fitness_score -- see FruitingModel.visit_weight_for_fitness. The
## accumulator is a float rather than an int specifically to hold these
## fractional weights.
func record_pollination_visit(bearing_cycle_seconds: float, now: float, visit_weight: float = 1.0) -> void:
	var cycle := int(floor(now / maxf(bearing_cycle_seconds, 0.0001)))
	if cycle != _pollination_visits_cycle:
		_pollination_visits_cycle = cycle
		_pollination_visits = 0.0
	_pollination_visits += visit_weight


## How many visits (fitness-weighted, see record_pollination_visit) this tree
## has banked in the bearing cycle `now` falls in. Read-only: querying a
## cycle nothing has been recorded in yet (including the very first query on
## a freshly-built tree) simply reads zero rather than resetting anything, so
## this is safe to call as often as fruiting steps run.
func pollination_visits_in_cycle(bearing_cycle_seconds: float, now: float) -> float:
	var cycle := int(floor(now / maxf(bearing_cycle_seconds, 0.0001)))
	if cycle != _pollination_visits_cycle:
		return 0.0
	return _pollination_visits


static var _tree_growth := TreeGrowth.new()

## How far grown this tree is -- 0.05..(1.0 + TreeGrowth.OLD_GROWTH_BONUS)
## (see TreeGrowth). Applied to the whole node so canopy, trunk, shadow and
## collision shrink or grow together -- a seedling is a small tree, not a
## full tree drawn small, and an old-growth tree is a genuinely bigger
## tree, not the same tree drawn oversized.
##
## Upper bound raised past 1.0 to let TreeGrowth's own old-growth ceiling
## through -- still a real clamp, not removed outright, so a caller passing
## a wildly out-of-range value by mistake cannot render an arbitrarily
## huge tree.
var growth_scale: float = 1.0:
	set(value):
		growth_scale = clampf(value, 0.05, 1.0 + TreeGrowth.OLD_GROWTH_BONUS)
		scale = Vector2.ONE * growth_scale
