extends RefCounted

## The UI scale setting -- see docs/concept/hud.md "UI scale".
##
## Every font size in the HUD is a hardcoded override between 9 and 28, chosen
## against one developer's monitor. This is the settings model that lets the
## player choose otherwise: the same shape AudioSettings gives the master
## volume and SimulationSettings gives its density knobs -- a float, sanitised,
## with the default being exactly today's behaviour.
##
## Deliberately scales FONT SIZES rather than the $UI CanvasLayer. A
## CanvasLayer scales about its origin, so every bottom- and right-anchored
## card would walk off the screen; layout stays at one scale and text is what
## grows.
##
## Persisted by World in the `[ui]` section of the shared settings file, driven
## by the Settings overlay's "Interface" slider. Pinned by
## tests/unit/test_ui_scale.gd.

## 1.0 is a no-op, so a player who never touches the slider sees precisely the
## HUD that shipped.
const DEFAULT_SCALE := 1.0

## Small enough to fit more on a high-resolution screen, large enough to read
## from a couch, and no wider than that: the HUD's absolute offsets (card
## widths, corner insets) are NOT scaled, so a font far outside this range
## would start overflowing cards whose width is fixed.
const MIN_SCALE := 0.75
const MAX_SCALE := 1.75

## The floor a scaled size can never go under. The smallest label in the HUD is
## 9pt, and 9 * MIN_SCALE rounds to 7 -- small enough to be worth catching
## before it reaches a size nobody can read at all.
const MIN_FONT_SIZE := 8


## A scale is a multiplier on a font size: NaN falls back to the default (the
## same fallback AudioSettings.sanitize_volume makes, so an unreadable settings
## file can never produce a zero-size HUD), anything else clamps into range.
static func sanitize(value: float) -> float:
	if is_nan(value):
		return DEFAULT_SCALE
	return clampf(value, MIN_SCALE, MAX_SCALE)


## `base` scaled, rounded (not truncated -- a floor would quietly lose a sixth
## of the smallest label in the HUD) and never below MIN_FONT_SIZE.
##
## This is the ONLY way a size is applied, and it sanitises the scale it is
## given, so a caller can never forget to sanitise first.
static func font_size(base: int, scale: float) -> int:
	return maxi(MIN_FONT_SIZE, roundi(float(base) * sanitize(scale)))
