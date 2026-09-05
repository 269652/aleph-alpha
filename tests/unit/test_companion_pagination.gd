extends GutTest

## CompanionPagination: pure, generic list pagination -- no knowledge of
## items/recipes/anything companion-server-specific, so any future
## paginated view can reuse it. See companion_item_catalog_view.gd for the
## first consumer.

const CompanionPagination = preload("res://src/companion_server/companion_pagination.gd")


func test_the_first_page_holds_the_first_page_size_items():
	var result := CompanionPagination.paginate([1, 2, 3, 4, 5], 1, 2)
	assert_eq(result.items, [1, 2])


func test_a_middle_page_holds_the_right_slice():
	var result := CompanionPagination.paginate([1, 2, 3, 4, 5], 2, 2)
	assert_eq(result.items, [3, 4])


func test_the_last_page_can_be_a_partial_page():
	var result := CompanionPagination.paginate([1, 2, 3, 4, 5], 3, 2)
	assert_eq(result.items, [5])


func test_total_pages_is_the_ceiling_of_count_over_page_size():
	var result := CompanionPagination.paginate([1, 2, 3, 4, 5], 1, 2)
	assert_eq(result.total_pages, 3)


func test_total_count_reports_the_unpaginated_size():
	var result := CompanionPagination.paginate([1, 2, 3, 4, 5], 1, 2)
	assert_eq(result.total_count, 5)


func test_a_page_number_below_one_clamps_up_to_the_first_page():
	var result := CompanionPagination.paginate([1, 2, 3], 0, 2)
	assert_eq(result.page, 1)
	assert_eq(result.items, [1, 2])


func test_a_page_number_past_the_end_clamps_down_to_the_last_page():
	var result := CompanionPagination.paginate([1, 2, 3], 99, 2)
	assert_eq(result.page, 2)
	assert_eq(result.items, [3])


func test_an_empty_list_reports_one_total_page_not_zero():
	# A zero-match search is the NORMAL shape of using a search box, not a
	# rare edge case -- total_pages must stay a valid, renderable "page 1
	# of 1", never a division-by-zero-shaped 0.
	var result := CompanionPagination.paginate([], 1, 20)
	assert_eq(result.total_pages, 1)
	assert_eq(result.items, [])
	assert_eq(result.page, 1)


func test_a_page_size_larger_than_the_list_returns_everything_on_page_one():
	var result := CompanionPagination.paginate([1, 2, 3], 1, 20)
	assert_eq(result.items, [1, 2, 3])
	assert_eq(result.total_pages, 1)
