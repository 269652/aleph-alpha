extends GutTest

const BirdSong = preload("res://src/gameplay/bird_song.gd")


func test_a_bird_is_not_singing_the_instant_its_bout_ends():
	assert_false(BirdSong.should_sing(0, BirdSong.SING_DURATION_SECONDS + 0.01))


func test_a_bird_sings_right_at_the_start_of_its_bout():
	assert_true(BirdSong.should_sing(0, 0.0))
	assert_true(BirdSong.should_sing(0, BirdSong.SING_DURATION_SECONDS - 0.01))


func test_singing_recurs_every_interval():
	assert_true(BirdSong.should_sing(0, BirdSong.SING_INTERVAL_SECONDS))
	assert_true(BirdSong.should_sing(0, BirdSong.SING_INTERVAL_SECONDS * 3.0))


func test_a_bird_spends_most_of_its_time_not_singing():
	var singing := 0
	var total := 600
	for i in total:
		if BirdSong.should_sing(0, float(i) * 0.1):
			singing += 1
	var fraction := float(singing) / float(total)
	assert_between(fraction, 0.15, 0.35, "singing must be a minority of the time, not the default state")


func test_different_birds_sing_at_different_times():
	# Same instant, different seeds -- at least one of a handful of birds
	# must disagree with the others, or a whole flock sings/falls silent
	# in lockstep.
	var states := {}
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		states[BirdSong.should_sing(seed_value, 3.0)] = true
	assert_eq(states.size(), 2, "a flock of 8 birds must not all agree on whether it's singing right now")
