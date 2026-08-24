extends RefCounted

## Pure hip/knee gait-angle math for CharacterView's walk animation (see
## CharacterView._process/_apply_legs) -- replaces two placeholders at once:
## the old `leg_swing_offset = sin(_cycle_time) * LEG_SWING_AMPLITUDE`
## vertical BOB (a position offset, no joint anywhere) and
## `FUSED_LEG_ROCK_AMPLITUDE` (one whole-pair RIGID rotation, still no
## knee). Reported live, directly: "add proper walk animation by morphing
## the leg sprites and include a knee joint animated motion" -- this is that
## real gait curve, as two small pure functions of a single phase, kept
## separate from Node wiring the same way WeaponSwing.rotation_at already
## keeps the attack-swing's pure angle math separate from CharacterView.
##
## A REAL human gait's knee-flexion-vs-phase curve is a double-humped curve,
## not one sine (see Winter's "Biomechanics and Motor Control of Human
## Movement" gait-cycle joint-angle figures -- the same book CharacterView.
## LEG_TO_HEIGHT_FRACTION already cites for a different table): a small
## ~20-degree "yield" flexion during early stance, then a much larger
## ~60-70-degree flexion during swing to lift the foot clear of the ground.
## This is a deliberate simplification of that (the task this was built
## against explicitly allows it: "even a simplified two-phase sine-based
## approximation is fine AS LONG AS it's a real, named, tested function of
## gait-cycle phase") -- one rectified-sine hump per stride, timed to the
## swing half of the cycle only, not the full biomechanical double-hump.
##
## Phase convention: `phase` is in RADIANS, one full stride is 2*PI, and
## phase=0 is the leg fully forward, about to plant (heel strike). Stance
## (foot planted, sweeping backward under the body as the torso passes over
## it) is phase in [0, PI]; swing (foot lifted, recovering forward through
## the air) is phase in [PI, 2*PI]. Both functions are naturally periodic
## (built from sin/cos) -- callers do not need to wrap `phase` into [0,
## 2*PI) themselves.

## Thigh swing either side of vertical, radians -- real hip flexion/
## extension during walking is commonly cited around 30 degrees forward to
## 10-20 degrees back (Winter's own gait-cycle joint-angle tables); 25
## degrees sits inside that range as a single symmetric amplitude (a real
## simplification: a flat +-A swing rather than genuinely asymmetric
## flexion/extension bounds, in the same spirit as the knee's own single-
## hump simplification above).
const HIP_SWING_AMPLITUDE := deg_to_rad(25.0)

## Peak knee flexion during swing, radians -- real swing-phase knee flexion
## peaks around 60-70 degrees (Winter). 45 degrees is deliberately smaller
## than that real peak: this bends a FUSED, front-facing leg PAIR (see
## CharacterView._apply_legs' own doc comment on why the illustrated art
## can't split into two independently-swinging legs), not one leg seen in
## profile -- on a front-on silhouette the full real angle reads as an
## exaggerated snap rather than a stride.
const KNEE_BEND_AMPLITUDE := deg_to_rad(45.0)


## Hip (thigh) angle at this phase, radians -- a plain sine (well, cosine,
## so it starts at its own peak): +amplitude at phase=0 (leg forward, about
## to plant), 0 a quarter-cycle either side (leg vertical, passing under the
## body at mid-stance or mid-swing), -amplitude at phase=PI (leg trailing,
## about to lift for swing).
func hip_angle(phase: float) -> float:
	return HIP_SWING_AMPLITUDE * cos(phase)


## Knee (shin) flexion at this phase, radians, always >= 0 -- a real knee
## only bends one way. Zero through the whole stance half (phase in
## [0, PI]: sin(phase) >= 0 there, and this rectifies -sin(phase) up to 0),
## rising to a single peak of KNEE_BEND_AMPLITUDE at phase = 3*PI/2
## (mid-swing -- the leg is vertical again, exactly like mid-stance, but now
## swinging forward through the air and needing maximum ground clearance),
## and back down to zero as the leg reaches forward to plant again at
## phase = 2*PI. Deliberately timed a quarter-cycle AFTER hip_angle's own
## zero-crossing at phase=PI (leg starts trailing/lifting) rather than
## coinciding with it -- the knee keeps bending past the moment the hip
## starts swinging forward, exactly the lag a real recovering leg shows.
func knee_angle(phase: float) -> float:
	return KNEE_BEND_AMPLITUDE * maxf(0.0, -sin(phase))
