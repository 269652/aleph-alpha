extends RefCounted

## Pure player-trust model for the NPC instruction DSL's hiring gate
## (docs/concept/npc_instructions.md, Design pillar 5; docs/concept/npc.md
## "Hiring & instruction": "a stranger won't work for you at any price, but
## an NPC whose quest you completed, or whose child you helped, will"). This
## is deliberately the SMALLEST real thing that can unblock hiring -- a
## single [0,1] scalar for how much ONE NPC trusts THE PLAYER (this is a
## single-player game today, so there's no NPC-NPC relationship graph to
## build) -- not npc.md's full "relationships to other NPCs" web, which
## stays unbuilt (see docs/concept/npc_instructions.md's Status/Non-goals).
##
## Mirrors src/gameplay/pet_loyalty.gd's shape -- RefCounted, a baseline
## const, named thresholds, instance methods reading a caller-stored float --
## but deliberately NOT its numbers. The semantics differ on purpose: a
## freshly-tamed pet's BASELINE_LOYALTY (0.5) already clears its own
## FOLLOW_THRESHOLD (0.4), so a pet you just tamed will already follow you.
## An NPC is the opposite case by design: npc.md is explicit a stranger
## "won't work for you at any price," so BASELINE_TRUST must sit BELOW
## HIRE_THRESHOLD -- a freshly-met NPC is never hireable until the player
## actually does something (a quest, a favor) to raise trust past it. Both
## sides of that relationship are pinned by test_npc_trust.gd, per CLAUDE.md's
## "tuned values/thresholds must be tested functions or test-pinned
## constants, never eyeballed comments."

## A freshly-met NPC's starting trust in the player. Deliberately low but
## not zero -- a stranger isn't necessarily hostile, just not yet trusted
## enough to work for you, and there's real room left to rise toward
## HIRE_THRESHOLD through ordinary play (quests/dialogue, npc.md) without a
## first interaction being required just to get off the floor.
const BASELINE_TRUST := 0.2

## The trust an NPC must have in the player before hiring_gate.gd's can_hire
## will consider them hireable at all, independent of wage -- npc.md's "a
## stranger won't work for you at any price." Set safely above
## BASELINE_TRUST so trust must genuinely be built by play, never started
## with for free.
const HIRE_THRESHOLD := 0.5

## Full trust -- mirrors taming.md's TAME_TRUST := 1.0 for the same
## upper-bound role: the top of the [0,1] scale complexity_ceiling_for
## scales up to.
const FULL_TRUST := 1.0

## complexity_ceiling_for's lower bound, right at HIRE_THRESHOLD -- a
## barely-hireable stranger tolerates only "a trivial one-or-two-rule
## script" (docs/concept/npc_instructions.md, "What the number gates
## against..."). Grounded in npc_instruction_cost.gd's own weight constants
## rather than a separately eyeballed number: a single rule with one
## condition and one action, both on a common (rarity 1.0) resource, costs
## exactly RULE_WEIGHT + CONDITION_WEIGHT + ACTION_WEIGHT = 1.0 + 0.5 + 1.5
## = 3.0 -- the textbook "trivial one-rule script" this ceiling is sized to
## just barely afford.
const MIN_COMPLEXITY_CEILING := 3.0

## complexity_ceiling_for's upper bound, at FULL_TRUST -- "something closer
## to the worked example above" (the concept doc's own 3-rule
## haul_and_forage script, which npc_instruction_cost.gd's own tests pin at
## exactly 8.5). Set comfortably above that so a fully-trusted NPC can
## afford the doc's own worked example with real headroom, not just barely
## clear it.
const MAX_COMPLEXITY_CEILING := 10.0


## Whether an NPC at `trust` in the player is willing to be hired at all --
## the trust half of hiring_gate.gd's can_hire (the wage half is
## hiring_gate.gd's own concern, not this module's).
func is_hireable(trust: float) -> bool:
	return trust >= HIRE_THRESHOLD


## How elaborate an instruction script this NPC will tolerate, as a
## CONTINUOUS function of trust -- not a second boolean gate. Scales
## linearly from MIN_COMPLEXITY_CEILING right at HIRE_THRESHOLD up to
## MAX_COMPLEXITY_CEILING at FULL_TRUST, per docs/concept/npc_instructions.md's
## own "a stranger... tolerates only a trivial one-or-two-rule script; an
## NPC whose quest you completed... tolerates something closer to the worked
## example" -- language describing a smooth scale, not a second yes/no gate.
##
## Below HIRE_THRESHOLD this clamps flat at MIN_COMPLEXITY_CEILING rather
## than continuing to fall below it -- an NPC below the hire threshold can't
## be hired at all (hiring_gate.gd's own concern), so what this returns
## there is moot for gameplay, but clamping keeps the function total and
## never-negative instead of extrapolating into nonsense.
func complexity_ceiling_for(trust: float) -> float:
	var span := FULL_TRUST - HIRE_THRESHOLD
	var t := clampf((trust - HIRE_THRESHOLD) / span, 0.0, 1.0)
	return lerpf(MIN_COMPLEXITY_CEILING, MAX_COMPLEXITY_CEILING, t)
