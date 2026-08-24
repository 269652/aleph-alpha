extends RefCounted

## Illustrated flower BLOOM-HEAD art, sliced from an AI-generated reference
## sheet (see docs/art/ai_sprite_prompts.md), one sheet per HEAD ARCHETYPE
## (cup/layered/spike/puff -- see ProceduralTerrainSprite... no, see
## ProceduralFlowerSprite.HEAD_SHAPE_BY_SPECIES) rather than per species: the
## archetype is what's structurally different between species (a real crocus
## and a real tulip share the same shallow-open-cup shape and differ only in
## colour/size, both already data-driven elsewhere -- FlowerSpecies.color_for,
## height_cm), so one illustrated sheet per archetype covers every species
## that maps to it, and a new species costs zero new art. Same "hand-drawn
## sheet -> SpriteSheetSlicer -> cached frames" shape IllustratedAnimalSprite
## already uses for horse/deer/boar; ProceduralFlowerSprite composites the
## illustrated head onto its own procedural stem/leaves, falling back to the
## procedural head painter entirely for any archetype with no sheet yet (the
## same has_species()-gated fallback convention IllustratedAnimalSprite
## documents).
##
## Each sheet is a single row of 4 bloom stages, left to right: bud, opening,
## full bloom, spent. Bud/opening are sliced and cached here but NOT YET
## consumed by ProceduralFlowerSprite -- a currently-rendered flower is
## always already in bloom (see FlowerPatch.blooming_cells/EarthChunkManager.
## _sync_flower_sprites, which only ever draws a cell once it's blooming, on
## purpose: "a flower is either there or it isn't"), so there is no live
## "still growing toward its first bloom" state to show them for today. They
## stay here, fully sliced and tested, as the known next step (see
## docs/progress.md) rather than being left unbuilt -- only ProceduralFlower-
## Sprite's consumption of them is deferred, not the art pipeline itself.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Left-to-right order every archetype sheet is authored in.
const STAGE_BUD := 0
const STAGE_OPENING := 1
const STAGE_FULL_BLOOM := 2
const STAGE_SPENT := 3
const STAGE_COUNT := 4

## archetype -> source sheet path. Only archetypes with real art land here;
## has_archetype/frames_for both key off this, so an archetype with no entry
## cleanly reports "nothing to draw" rather than erroring.
const _SHEETS := {
	"cup": "res://assets/sprites/flowers/cup.png",
	"layered": "res://assets/sprites/flowers/layered.png",
}

## species -> its OWN sheet, which wins over its archetype's.
##
## One sheet per archetype is the default because it costs no new art per
## species, and for most species that is genuinely right -- a real crocus and
## a real tulip are the same shallow cup differing in colour and size, both
## already data-driven. But some species deserve their own drawing, and this
## is where a sheet for one goes: drop the art in, add the entry, and that
## species stops using the shared one. Nothing else changes, and every other
## species of the archetype is unaffected.
##
## The same species-first-then-generic lookup IllustratedAnimalSprite uses for
## per-action art.
const _SPECIES_SHEETS := {
	"crocus": "res://assets/sprites/flowers/crocus.png",
	"tulip": "res://assets/sprites/flowers/tulip.png",
	"rose": "res://assets/sprites/flowers/rose.png",
	"daisy": "res://assets/sprites/flowers/daisy.png",
	"sunflower": "res://assets/sprites/flowers/sunflower.png",
	"lavender": "res://assets/sprites/flowers/lavender.png",
}


## The sheet this species should draw from: its own if it has one, otherwise
## its archetype's, or "" for neither (the caller falls back to procedural art).
static func sheet_path_for(species: String, archetype: String) -> String:
	if _SPECIES_SHEETS.has(species):
		return _SPECIES_SHEETS[species]
	return _SHEETS.get(archetype, "")


## Whether there is ANY illustrated art for this species, of either kind.
func has_art_for(species: String, archetype: String) -> bool:
	return sheet_path_for(species, archetype) != ""


## The bloom-stage frames this species should use -- its own art if it has
## any, otherwise its archetype's shared sheet.
func frames_for_species(species: String, archetype: String) -> Array:
	var path := sheet_path_for(species, archetype)
	if path == "":
		return []
	if not _frame_cache.has(path):
		_frame_cache[path] = _load_frames_from(path)
	return _frame_cache[path]

## The small canvas each stage frame is normalized onto, bottom-anchored so
## every stage's stem-attachment point lands at the same local position
## regardless of how much the bloom itself has opened out (matching
## IllustratedAnimalSprite's baseline-alignment convention, sized for a
## flower head rather than a whole animal -- see ProceduralFlowerSprite.SIZE,
## the 32x32 canvas the head gets composited onto; a head roughly half that
## keeps it proportionate to the hand-measured ~10-16px procedural heads it
## replaces, see _paint_cup_head).
const HEAD_CANVAS_SIZE := Vector2i(18, 18)
const HEAD_BASELINE_Y := 18

var _slicer := SpriteSheetSlicer.new()

## archetype -> Array[ImageTexture] (STAGE_COUNT entries), sliced once per
## archetype and reused thereafter -- mirrors IllustratedAnimalSprite.
## _frame_cache: every flower of a given archetype/stage shows the identical
## illustrated art, so there's nothing to gain in re-slicing per flower.
static var _frame_cache: Dictionary = {}


func has_archetype(archetype: String) -> bool:
	return _SHEETS.has(archetype)


## The 4 bloom-stage frames for `archetype`, bud..spent, ready to composite.
## Empty for an archetype with no sheet yet -- callers must check
## has_archetype first and fall back to procedural art themselves.
func frames_for(archetype: String) -> Array:
	if not has_archetype(archetype):
		return []
	if not _frame_cache.has(archetype):
		_frame_cache[archetype] = _load_frames(archetype)
	return _frame_cache[archetype]


func _load_frames(archetype: String) -> Array:
	return _load_frames_from(_SHEETS[archetype])


## Keyed by PATH rather than by archetype, so a species sheet and an archetype
## sheet can never collide in the cache.
func _load_frames_from(path: String) -> Array:
	var image := SpriteSheetLoader.load_image(path)
	var frames := _slicer.detect_frames(image, 0, image.get_height())
	var normalized := _slicer.normalize_frames(image, frames, HEAD_CANVAS_SIZE, HEAD_BASELINE_Y)
	var textures: Array[ImageTexture] = []
	for frame_image in normalized:
		textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## Whether this species has a sheet of its OWN, as opposed to falling back to
## its archetype's shared one. Callers use this to tell "drawn specifically"
## from "drawn generically" -- the two look different on purpose.
func has_own_art(species: String) -> bool:
	return _SPECIES_SHEETS.has(species)


## ## Masks: where each sheet's PETALS are, on the hue wheel
##
## The recolour repaints the petals and must leave alone the parts drawn in
## another colour on purpose -- a gold eye, a green sepal. Telling them apart
## needs to know which hue is the petal mass, and that cannot be derived
## reliably: measured across these sheets, the cup sheet's PETALS sit at 30
## degrees, which is exactly where the daisy sheet's EYE sits. A rule based on
## "the biggest cluster wins" gets one of those two backwards.
##
## So each sheet says where its own petals are. That is the mask, expressed as
## data rather than as a companion image -- adding a sheet costs one number,
## not a second drawing. Everything sufficiently far from it in hue keeps the
## colour the artist gave it.
##
## Measured, not guessed (buckets of 15 degrees over each sheet's full-bloom
## frame):
##   crocus  petals 270 (71%), stamens 60 (2%),  sepals 75 (7%)
##   tulip   petals 345 (64%), stamens 60 (6%),  sepals 75 (12%)
##   rose    petals 345 (86%), stamens 60 (7%),  sepals 75 (4%)
##   daisy   petals 345 (55% across 330-15), eye 30 (21%)
##   cup     petals 30  (53%), no green at all
##   layered petals 15-30 (87%), stamens 60 (6%)
const _SHEET_PETAL_HUE := {
	"res://assets/sprites/flowers/crocus.png": 270.0,
	"res://assets/sprites/flowers/tulip.png": 345.0,
	"res://assets/sprites/flowers/rose.png": 345.0,
	"res://assets/sprites/flowers/daisy.png": 345.0,
	"res://assets/sprites/flowers/cup.png": 30.0,
	"res://assets/sprites/flowers/layered.png": 22.0,
	## sunflower petals 30 (45% at 30, with 15/45/60 shading around it), and
	## its brown centre is a DARK 30 rather than a different hue -- brown is
	## dark gold -- so it recolours with the petals and comes out as a dark
	## version of whatever the plant came up as, which is what a sunflower
	## centre looks like.
	"res://assets/sprites/flowers/sunflower.png": 32.0,
	## lavender petals 255-270 (62% across the two), foliage at 90-120 (24%).
	"res://assets/sprites/flowers/lavender.png": 262.0,
}

## Where a sheet's petals sit on the hue wheel, in degrees.
##
## Returns -1.0 for a sheet that has not declared one, which the painter reads
## as "recolour everything" -- the old behaviour, and the safe default: a
## sheet with no mask loses its eye, where a wrong mask would lose its petals.
static func petal_hue_for(species: String, archetype: String) -> float:
	return _SHEET_PETAL_HUE.get(sheet_path_for(species, archetype), -1.0)
