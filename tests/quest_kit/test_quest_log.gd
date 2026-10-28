extends "res://tests/quest_kit/qk_test_case.gd"
## States, prerequisites, collect and event objectives, turn-in, abandon, fail, tracking, saving.

const S := QKQuestLog.State


func test_states_and_prerequisites() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	assert_eq(log.get_state(&"firewood"), S.AVAILABLE)
	assert_eq(log.get_state(&"alchemist"), S.LOCKED)
	assert_quest(log.accept(&"alchemist"), QKResult.Code.LOCKED)
	assert_true(log.accept(&"firewood").ok)
	assert_eq(log.get_state(&"firewood"), S.ACTIVE)
	assert_quest(log.accept(&"firewood"), QKResult.Code.WRONG_STATE)
	assert_quest(log.accept(&"nope"), QKResult.Code.UNKNOWN_QUEST)


func test_collect_follows_the_bag_live() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	log.accept(&"firewood")
	bag.add(&"wood", 3)
	assert_eq(log.get_progress(&"firewood", &"wood"), 3)
	bag.add(&"wood", 4)
	assert_eq(log.get_progress(&"firewood", &"wood"), 5, "capped at the amount")
	assert_eq(log.get_state(&"firewood"), S.READY)
	bag.remove(&"wood", 5)
	assert_eq(log.get_state(&"firewood"), S.ACTIVE, "dropped the wood: back in progress")


func test_turn_in_takes_items_and_gives_rewards() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 7})
	var log := make_log(db, bag)
	var completed := []
	log.quest_completed.connect(func(quest: QKQuest) -> void: completed.append(quest.id))
	log.accept(&"firewood")
	assert_true(log.turn_in(&"firewood", bag).ok)
	assert_eq(bag.count(&"wood"), 2)
	assert_eq(bag.count(&"gold"), 10)
	assert_eq(log.get_state(&"firewood"), S.COMPLETED)
	assert_eq(log.get_state(&"alchemist"), S.AVAILABLE, "unlocked")
	assert_eq(completed, [&"firewood"])
	assert_quest(log.turn_in(&"firewood", bag), QKResult.Code.WRONG_STATE, "no double reward")


func test_turn_in_refused_when_not_ready() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 2})
	var log := make_log(db, bag)
	log.accept(&"firewood")
	assert_quest(log.turn_in(&"firewood", bag), QKResult.Code.NOT_READY)
	assert_eq(bag.count(&"wood"), 2)


func test_rewards_that_do_not_fit_take_nothing() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5, &"herb": 20}, 2)  # 2 slots: wood and herbs, gold has nowhere to go
	bag.add(&"herb", 20)
	var tiny := make_bag(db, {&"wood": 5, &"herb": 20}, 2)
	var log := make_log(db, tiny)
	log.accept(&"firewood")
	# Taking the 5 wood frees its slot, so the gold fits: paying can make room.
	assert_true(log.turn_in(&"firewood", tiny).ok)
	var full := make_bag(db, {&"wood": 10, &"herb": 20}, 2)
	var other := make_log(db, full)
	other.accept(&"firewood")
	var result := other.turn_in(&"firewood", full)
	assert_quest(result, QKResult.Code.NO_ROOM, "5 wood stay in the slot, no room for gold")
	assert_eq(full.count(&"wood"), 10, "nothing taken")
	assert_eq(other.get_state(&"firewood"), S.READY)
	assert_false(QKText.result_message(result).is_empty())


func test_events_and_auto_complete() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	log.report(&"kill_wolf", 5)
	assert_eq(log.get_progress(&"wolves", &"kills"), 0, "not accepted: not counted")
	log.accept(&"wolves")
	log.report(&"kill_wolf")
	log.report(&"kill_wolf")
	assert_eq(log.get_progress(&"wolves", &"kills"), 2)
	log.report(&"kill_wolf")
	assert_eq(log.get_state(&"wolves"), S.COMPLETED, "auto-complete")
	assert_eq(bag.count(&"sword"), 1)


func test_mixed_objectives() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5, &"herb": 2})
	var log := make_log(db, bag)
	log.accept(&"firewood")
	log.turn_in(&"firewood", bag)
	log.accept(&"alchemist")
	assert_eq(log.get_state(&"alchemist"), S.ACTIVE, "herbs held, Mira not met")
	log.report(&"talk_mira")
	assert_eq(log.get_state(&"alchemist"), S.READY)
	assert_true(log.turn_in(&"alchemist", bag).ok)
	assert_eq(bag.count(&"gold"), 30)
	assert_eq(bag.count(&"herb"), 0)


func test_abandon_and_fail() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	log.accept(&"wolves")
	log.report(&"kill_wolf", 2)
	assert_true(log.abandon(&"wolves").ok)
	assert_eq(log.get_state(&"wolves"), S.AVAILABLE)
	log.accept(&"wolves")
	assert_eq(log.get_progress(&"wolves", &"kills"), 0, "progress lost")
	assert_true(log.fail(&"wolves").ok)
	assert_eq(log.get_state(&"wolves"), S.FAILED)
	assert_quest(log.abandon(&"wolves"), QKResult.Code.WRONG_STATE)


func test_tracking() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	log.max_tracked = 1
	log.accept(&"firewood")
	log.accept(&"wolves")
	assert_eq(log.get_tracked(), [&"firewood"], "only one tracked")
	assert_false(log.set_tracked(&"wolves", true))
	log.set_tracked(&"firewood", false)
	assert_true(log.set_tracked(&"wolves", true))
	log.abandon(&"wolves")
	assert_true(log.get_tracked().is_empty())


func test_save_and_load() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5})
	var log := make_log(db, bag)
	log.accept(&"firewood")
	log.turn_in(&"firewood", bag)
	log.accept(&"wolves")
	log.report(&"kill_wolf", 2)
	var data: Dictionary = JSON.parse_string(JSON.stringify(log.to_data()))
	var copy := make_log(db, bag)
	assert_true(copy.load_data(data))
	assert_eq(copy.get_state(&"firewood"), S.COMPLETED)
	assert_eq(copy.get_state(&"alchemist"), S.AVAILABLE)
	assert_eq(copy.get_progress(&"wolves", &"kills"), 2)
	assert_eq(copy.get_tracked(), [&"wolves"])
	assert_false(copy.load_data({"states": []}))


func test_book_validation() -> void:
	var db := make_db()
	var book := make_book()
	assert_eq(book.validate(db), PackedStringArray())
	var broken := QKQuest.make(&"broken", "Broken", [QKObjective.collect(&"x", &"unicorn", 1)], {&"crown": 1})
	broken.prerequisites = [&"missing"]
	book.add_quest(broken)
	assert_eq(book.validate(db).size(), 3, str(book.validate(db)))
