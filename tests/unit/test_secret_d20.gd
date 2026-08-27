extends GutTest

## SecretD20 (docs/concept/easter_eggs.md's D&D d20 nod): the ONE deliberate
## exception to this project's fully-deterministic combat/crafting/
## spellcasting design -- a single, secret, genuinely-random d20 roll that
## does something harmless and silly on a natural 20, and nothing at all
## otherwise. Isolated in its own small module specifically so it can never
## be mistaken for, or accidentally reused as, a general-purpose RNG source
## elsewhere in this project (see the module's own doc comment).
##
## roll() takes a caller-supplied RandomNumberGenerator (a seeded one here,
## a real randomized one in play -- same "caller supplies the real
## primitive" shape every other Easter-egg module in this project uses),
## so this whole suite stays deterministic and fast.

const SecretD20 = preload("res://src/gameplay/secret_d20.gd")

var d20: SecretD20
var rng: RandomNumberGenerator


func before_each():
	d20 = SecretD20.new()
	rng = RandomNumberGenerator.new()
	rng.seed = 12345


func test_roll_is_always_between_1_and_20():
	for i in 500:
		var value := d20.roll(rng)
		assert_true(value >= 1 and value <= 20, "rolled %d" % value)


func test_roll_actually_uses_the_supplied_rng_not_a_fixed_value():
	# A seeded RNG rolled many times should produce more than one distinct
	# value -- proof this is a real roll, not a constant in disguise.
	var seen := {}
	for i in 100:
		seen[d20.roll(rng)] = true
	assert_true(seen.size() > 1)


func test_is_natural_20_true_only_for_20():
	assert_true(d20.is_natural_20(20))
	for value in [1, 2, 10, 19]:
		assert_false(d20.is_natural_20(value), "value %d" % value)


func test_outcome_message_is_empty_for_anything_but_a_natural_20():
	for value in [1, 5, 13, 19]:
		assert_eq(d20.outcome_message(value), "", "value %d" % value)


func test_outcome_message_is_nonempty_for_a_natural_20():
	assert_true(d20.outcome_message(20).length() > 0)
