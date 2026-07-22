extends RefCounted

## Shared art-direction style helper for the procedural pixel-art generators.
## Pushes the look toward a brighter, more saturated Zelda/Pokemon overworld
## palette with chunky Hammerwatch-style dark outlines and a top-left rim
## highlight, so every generator shades and outlines the same consistent way.
## Pure logic, deterministic -- same input always yields the same Color.

## Near-black, slightly cool: the shared silhouette outline color.
const OUTLINE := Color(0.08, 0.06, 0.1)

## How much shade()/highlight() move a color's value toward dark/light.
const SHADE_AMOUNT := 0.28
const HIGHLIGHT_AMOUNT := 0.24


## The shared dark outline color for every generator's silhouette.
func outline_color() -> Color:
	return OUTLINE


## Return `c` with its HSV saturation raised by `amount`, clamped to [0, 1].
## Value and hue (and alpha) are preserved -- only saturation moves.
func saturate(c: Color, amount: float) -> Color:
	var out := Color.from_hsv(c.h, clampf(c.s + amount, 0.0, 1.0), c.v, c.a)
	return out


## A darker tone of `c` for lower-right shadow faces.
func shade(c: Color) -> Color:
	return c.darkened(SHADE_AMOUNT)


## A lighter tone of `c` for the top-left rim highlight.
func highlight(c: Color) -> Color:
	return c.lightened(HIGHLIGHT_AMOUNT)
