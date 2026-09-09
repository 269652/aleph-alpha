extends GutTest

## A real, minimal ecosystem presence for one calling cicada (see
## docs/concept/creature_and_footstep_audio.md's "Cicadas" section).
## Deliberately as light as AntQueenMarker's own precedent for "a real
## creature that genuinely never moves gets no state machine at all" --
## no flight/foraging machinery it would never use, no visual art in this
## pass (a real, named gap -- cicadas are famously heard far more than
## seen anyway). Its only job is to exist, at a real position, in the
## group World._maybe_play_creature_calls scans.

const CicadaMarker = preload("res://src/rendering/cicada_marker.gd")


func test_species_is_cicada():
	var marker := CicadaMarker.new()
	add_child_autofree(marker)
	assert_eq(marker.species, "cicada")


func test_joins_the_cicada_group_on_ready():
	var marker := CicadaMarker.new()
	add_child_autofree(marker)
	assert_true(marker.is_in_group(CicadaMarker.GROUP_NAME))
