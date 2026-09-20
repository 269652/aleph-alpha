extends RefCounted

## Per-chunk, per-layer rock sim: SOLID rock / ORE deposit / open TUNNEL,
## the underground counterpart of what Chunk.biome is for the surface (see
## docs/concept/geology.md "Real strata, not a backdrop"). One class,
## differently PARAMETERIZED per layer -- the four real layers ask the same
## question ("what's in this cell") at different odds, not four different
## questions.
##
## Deterministic per (layer, global_x, global_y), same coordinate-hash idiom
## StonePlacement/OrePlacement already use. Mining (mine_at) is the one real
## mutable state this instance carries -- a mined cell is TUNNEL for the
## rest of this Strata's life, the underground equivalent of a played-out
## stone node's queue_free permanence, except the *cell* persists (there's
## always ground underfoot) rather than the node.
##
## Natural cave passage (KIND_VOID) is a separate thing again: carved by
## water over geological time rather than by anyone, and supplied by
## CaveNetwork per the chunk's own Palmer pattern (see
## docs/concept/underground.md). A chunk with no cave pattern -- the
## default, and the honest majority answer on a planet whose bedrock is
## mostly insoluble -- behaves exactly as this class did before caves
## existed.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const GeologyOreGenesis = preload("res://src/world/geology_ore_genesis.gd")
const CaveNetwork = preload("res://src/world/cave_network.gd")
const CavePattern = preload("res://src/world/cave_pattern.gd")

const LAYER_TOPSOIL_REGOLITH := "topsoil_regolith"
const LAYER_BEDROCK := "bedrock"
const LAYER_DEEP_BEDROCK := "deep_bedrock"
const LAYER_HYDROTHERMAL := "hydrothermal"

## Depth order, shallowest first -- also the order a shaft descends through
## (see geology.md's Status: only the first transition is wired today).
const LAYERS: Array[String] = [
	LAYER_TOPSOIL_REGOLITH, LAYER_BEDROCK, LAYER_DEEP_BEDROCK, LAYER_HYDROTHERMAL
]

const KIND_SOLID := "solid"
const KIND_ORE := "ore"

## A cell a PLAYER mined out.
const KIND_TUNNEL := "tunnel"

## A natural passage, carved by water over geological time (see
## docs/concept/underground.md). Distinct from KIND_TUNNEL although both
## are walkable, and the distinction is real rather than cosmetic: nobody
## took ore out of a natural void, and a tunnel is somebody's working,
## which is what a mining claim gets staked on.
const KIND_VOID := "void"

## Fraction of cells that are ore-bearing before genesis picks WHICH ore
## (see GeologyOreGenesis for that weighting). Rises with depth -- a real
## deep working cuts through more mineralised rock on average than a
## shallow one, before any single-deposit-type weighting is even applied.
const ORE_DENSITY_BY_LAYER := {
	LAYER_TOPSOIL_REGOLITH: 0.06,
	LAYER_BEDROCK: 0.08,
	LAYER_DEEP_BEDROCK: 0.10,
	LAYER_HYDROTHERMAL: 0.14,
}

var layer: String
var chunk_origin: Vector2i

## Which Palmer pattern of natural cave system runs through this chunk, or
## PATTERN_NONE for rock with no cave in it -- the honest majority answer,
## and the default, so a caller that knows nothing about lithology gets
## exactly the solid-rock behaviour this class had before caves existed.
var cave_pattern: String

var _genesis := GeologyOreGenesis.new()
var _cave_network := CaveNetwork.new()
var _mined: Dictionary = {}  # local Vector2i -> true


## Whether a cell of this kind can be walked through -- a natural passage
## or a player's own working, but never rock.
static func is_walkable(kind: String) -> bool:
	return kind == KIND_VOID or kind == KIND_TUNNEL


func _init(
	layer_name: String,
	chunk_origin_tiles: Vector2i,
	pattern: String = CavePattern.PATTERN_NONE
) -> void:
	layer = layer_name
	chunk_origin = chunk_origin_tiles
	cave_pattern = pattern


## SOLID, ORE, VOID or TUNNEL for this local cell (relative to
## chunk_origin). Deterministic and side-effect-free except that a
## previously mine_at'd cell always reads back as TUNNEL.
func cell_kind_at(local_cell: Vector2i) -> String:
	var global := chunk_origin + local_cell
	# Natural void wins over everything below it: there is no rock in an
	# open passage, so there is nothing there to have been mined and
	# nothing there to be ore.
	if _cave_network.is_void_at(cave_pattern, global.x, global.y):
		return KIND_VOID
	if _mined.has(local_cell):
		return KIND_TUNNEL
	if _is_ore_cell(global.x, global.y):
		return KIND_ORE
	return KIND_SOLID


## The ore type at this local cell -- meaningful only where cell_kind_at
## reports ORE, same "callers already know it's ore" contract as
## OrePlacement.ore_type_at.
func ore_type_at(local_x: int, local_y: int) -> String:
	var global := chunk_origin + Vector2i(local_x, local_y)
	return _genesis.ore_type_at(global.x, global.y, layer)


## Deterministic per-cell seed for this cell's sprite variation.
func seed_at(local_x: int, local_y: int) -> int:
	var global := chunk_origin + Vector2i(local_x, local_y)
	return hash("%d_%d_%s_strata_seed" % [global.x, global.y, layer])


## Mines this local cell: it reads as TUNNEL from now on. Mining an
## already-open tunnel is a harmless no-op, and so is swinging at a
## natural passage -- open air is not work, and must not turn a void water
## carved into a working somebody could claim.
func mine_at(local_cell: Vector2i) -> void:
	var global := chunk_origin + local_cell
	if _cave_network.is_void_at(cave_pattern, global.x, global.y):
		return
	_mined[local_cell] = true


func _is_ore_cell(global_x: int, global_y: int) -> bool:
	var density: float = ORE_DENSITY_BY_LAYER.get(layer, 0.0)
	if density <= 0.0:
		return false
	var roll := PixelNoise.unit(hash("strata_ore_%s" % layer), global_x, global_y)
	return roll < density
