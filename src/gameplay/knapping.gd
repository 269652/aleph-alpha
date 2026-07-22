extends RefCounted
## Rock knapping: smashing one rock against another destroys the target
## and yields 0..MAX_SHARDS_PER_SMASH sharp shards, deterministically per seed.

const SHARD_CHANCE := 0.6
const MAX_SHARDS_PER_SMASH := 2


static func _roll(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s" % [seed_value, salt])) % 10000) / 10000.0


func shard_yield(seed_value: int) -> int:
	if _roll(seed_value, "knap_success") >= SHARD_CHANCE:
		return 0
	var shards := 1
	if _roll(seed_value, "knap_bonus") < 0.5 and MAX_SHARDS_PER_SMASH >= 2:
		shards = 2
	return mini(shards, MAX_SHARDS_PER_SMASH)


func success_fraction_over(seed_count: int) -> float:
	if seed_count <= 0:
		return 0.0
	var successes := 0
	for seed_value in range(seed_count):
		if shard_yield(seed_value) >= 1:
			successes += 1
	return float(successes) / float(seed_count)
