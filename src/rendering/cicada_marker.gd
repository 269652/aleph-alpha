extends Node2D

## A real, minimal ecosystem presence for one calling cicada -- requested
## live: "you can hear cicadas in the environment which don't exist... add
## them please as real ecosystem member and produce cicada sounds for each
## individual" (see docs/concept/creature_and_footstep_audio.md's
## "Cicadas" section, CicadaPopulation for the spawn/season decision).
##
## No dedicated visual art in this pass -- a real, named, deliberately
## scoped gap, not an oversight: real adult cicadas are famously heard far
## more than seen (excellent bark camouflage), so an audio-only presence is
## an honest first pass rather than a corner cut. No movement, no behavior
## state machine at all: a real adult cicada clings to one spot on its tree
## for its entire (few-week) adult life and never leaves it -- mirrors
## AntQueenMarker's own precedent for "a real creature that genuinely never
## moves gets no state machine", rather than inheriting AmbientFlyerMarker's
## flight/foraging machinery it would never use.
##
## Its only job is to exist, at a real position, in the group World.
## _maybe_play_creature_calls already scans every other species-bearing
## population through (CreatureMarker.GROUP_NAME, AmbientFlyerMarker.
## FLOCK_GROUP) -- a third real population, not a decorative loop bolted on
## separately.

const GROUP_NAME := "cicadas"
const SPECIES := "cicada"

## Plain property, not a function -- mirrors AmbientFlyerMarker.species
## exactly, the same shape World._maybe_play_creature_calls already reads
## via `flyer.species` for every species that isn't a full CreatureMarker.
var species := SPECIES


func _ready() -> void:
	add_to_group(GROUP_NAME)
