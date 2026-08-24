extends RefCounted

## Real tunnel-collapse risk from an unsupported span (see
## docs/concept/geology.md "Collapse: stress grows with the square of the
## span"). A real unsupported roof span bends like a simple beam under its
## own weight, and simple-beam bending stress scales with the SQUARE of the
## span, not linearly -- this is why historic room-and-pillar mining kept
## unsupported spans to a strict few metres between timber sets rather than
## treating "a bit wider" as proportionally a bit riskier.
##
## Pure function of span alone -- it doesn't know or care what layer/rock
## type it's in, mirroring MountainOrePlacement's own "takes the physical
## quantity as an input" convention.

## Below this span, real timber-set spacing in historic room-and-pillar
## mining kept a roof essentially safe without support -- collapse chance
## is zero up to here.
const SAFE_SPAN_M := 2.0

## Beyond this span, the opening is already about as wide as any realistic
## unsupported working in this project's world -- chance holds at its
## ceiling rather than climbing further.
const CEILING_SPAN_M := 12.0

## Collapse chance at or beyond CEILING_SPAN_M. High enough that pushing a
## dig this wide without support is a real hazard, not a coin flip.
const MAX_COLLAPSE_CHANCE := 0.9


## Collapse chance for a real unsupported span of `unsupported_span` metres.
## Zero at or below SAFE_SPAN_M, then grows with the SQUARE of how far past
## it the span is (the real bending-stress relationship), reaching
## MAX_COLLAPSE_CHANCE at CEILING_SPAN_M and holding there beyond it.
func collapse_chance_for(unsupported_span: float) -> float:
	if unsupported_span <= SAFE_SPAN_M:
		return 0.0
	var t := clampf(
		(unsupported_span - SAFE_SPAN_M) / (CEILING_SPAN_M - SAFE_SPAN_M), 0.0, 1.0
	)
	return t * t * MAX_COLLAPSE_CHANCE
