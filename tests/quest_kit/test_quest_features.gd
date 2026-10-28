extends "res://tests/quest_kit/qk_test_case.gd"
## 1.1: non-item rewards, reward choices, repeatable / daily / timed quests, branches,
## go-to objectives and targets, saves of both versions.

const S := QKQuestLog.State

var _now := 1_000_000.0


func _log_with(quests: Array, bag: IKContainer, db: IKItemDatabase) -> QKQuestLog:
	var log := QKQuestLog.new()
	log.book = QKQuestBook.new()
	for quest: QKQuest in quests:
		log.book.add_quest(quest)
	log.database = db
	log.clock = func() -> float: return _now
	log.time_zone_minutes = 0
	add_to_tree(log)
	log.watch(bag)
	log.set_process(false)  # the tests drive time themselves
	return log


func _event_quest(id: StringName, event_id: StringName = &"ping") -> QKQuest:
	return QKQuest.make(id, String(id), [QKObjective.event(&"do", event_id)])


func test_non_item_rewards_reach_the_game() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"q")
	quest.rewards.assign({&"gold": 5})
	quest.extra_rewards = [QKReward.xp(50), QKReward.currency(&"marks", 3), QKReward.reputation(&"village", 10),
		QKReward.make(&"unlock", &"recipe_bread", 1), QKReward.item(&"herb", 2)]
	var log := _log_with([quest], bag, db)
	var granted := []
	var called := []
	log.reward_granted.connect(func(kind: StringName, id: StringName, amount: int) -> void: granted.append([kind, id, amount]))
	log.reward_callback = func(kind: StringName, id: StringName, amount: int) -> void: called.append(kind)
	log.accept(&"q")
	log.report(&"ping")
	assert_true(log.turn_in(&"q", bag).ok)
	assert_eq(granted, [[&"xp", &"", 50], [&"currency", &"marks", 3], [&"reputation", &"village", 10], [&"unlock", &"recipe_bread", 1]])
	assert_eq(called.size(), 4, "callback too")
	assert_eq(bag.count(&"gold"), 5)
	assert_eq(bag.count(&"herb"), 2, "item kind goes in the bag")
	assert_eq(QKReward.xp(50).get_text(), "50 XP")
	assert_eq(QKReward.reputation(&"village", 5).get_text(), "+5 reputation: Village")
	log.reward_callback = Callable()
	disconnect_all([log])


func test_reward_choice() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"q")
	quest.auto_complete = true
	quest.reward_choices = [QKReward.item(&"sword"), QKReward.xp(100)]
	var log := _log_with([quest], bag, db)
	var granted := []
	log.reward_granted.connect(func(kind: StringName, _id: StringName, amount: int) -> void: granted.append([kind, amount]))
	log.accept(&"q")
	log.report(&"ping")
	assert_eq(log.get_state(&"q"), S.READY, "choices: no auto-complete")
	assert_quest(log.turn_in(&"q", bag), QKResult.Code.CHOICE_REQUIRED)
	assert_quest(log.turn_in(&"q", bag, 5), QKResult.Code.CHOICE_REQUIRED)
	assert_false(QKText.result_message(log.turn_in(&"q", bag)).is_empty())
	assert_true(log.turn_in(&"q", bag, 0).ok)
	assert_eq(bag.count(&"sword"), 1)
	assert_true(granted.is_empty(), "the XP was not picked")
	disconnect_all([log])


func test_chosen_item_that_does_not_fit_takes_nothing() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 20}, 1)
	var quest := QKQuest.make(&"q", "Q", [QKObjective.collect(&"w", &"wood", 5)])
	quest.reward_choices = [QKReward.item(&"sword")]
	var log := _log_with([quest], bag, db)
	log.accept(&"q")
	assert_quest(log.turn_in(&"q", bag, 0), QKResult.Code.NO_ROOM)
	assert_eq(bag.count(&"wood"), 20)


func test_repeatable_with_cooldown() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"q")
	quest.repeatable = true
	quest.cooldown = 60.0
	quest.auto_complete = true
	var follow := _event_quest(&"next")
	follow.prerequisites = [&"q"]
	var log := _log_with([quest, follow], bag, db)
	log.accept(&"q")
	log.report(&"ping")
	assert_eq(log.get_state(&"q"), S.COMPLETED)
	assert_eq(log.times_completed(&"q"), 1)
	assert_quest(log.accept(&"q"), QKResult.Code.ON_COOLDOWN)
	assert_eq(int(log.get_cooldown_left(&"q")), 60)
	var back := []
	log.state_changed.connect(func(q: QKQuest, state: S) -> void: back.append([q.id, state]))
	_now += 61.0
	log.check_cooldowns()
	assert_eq(back, [[&"q", S.AVAILABLE]], "announced once")
	assert_eq(log.get_state(&"q"), S.AVAILABLE)
	assert_true(log.accept(&"q").ok)
	assert_eq(log.get_progress(&"q", &"do"), 0, "fresh progress")
	assert_eq(log.get_state(&"next"), S.AVAILABLE, "still counts as completed for prerequisites")
	log.report(&"ping")
	assert_eq(log.times_completed(&"q"), 2)
	disconnect_all([log])


func test_daily_quest_comes_back_after_the_reset() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"daily")
	quest.repeatable = true
	quest.daily = true
	quest.auto_complete = true
	var log := _log_with([quest], bag, db)
	log.daily_reset_hour = 6
	_now = 86400.0 * 100 + 5 * 3600  # 05:00
	log.accept(&"daily")
	log.report(&"ping")
	assert_eq(int(log.get_cooldown_left(&"daily")), 3600, "reset at 06:00 the same day")
	_now += 2 * 3600  # 07:00
	assert_eq(log.get_state(&"daily"), S.AVAILABLE)
	log.accept(&"daily")
	log.report(&"ping")
	_now += 12 * 3600  # 19:00
	assert_eq(log.get_state(&"daily"), S.COMPLETED, "done today")
	_now += 11 * 3600 + 1  # 06:00:01 the next day
	assert_eq(log.get_state(&"daily"), S.AVAILABLE)


func test_timed_quest_fails_when_time_runs_out() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"timed")
	quest.time_limit = 10.0
	var log := _log_with([quest], bag, db)
	var expired := []
	log.quest_expired.connect(func(q: QKQuest) -> void: expired.append(q.id))
	assert_eq(log.get_time_left(&"timed"), -1.0)
	log.accept(&"timed")
	log.advance_time(4.0)
	assert_eq(log.get_time_left(&"timed"), 6.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(log.to_data()))
	log.advance_time(6.5)
	assert_eq(log.get_state(&"timed"), S.FAILED)
	assert_eq(expired, [&"timed"])
	assert_eq(log.get_time_left(&"timed"), -1.0)
	assert_true(log.load_data(data), "timer saved")
	assert_eq(log.get_state(&"timed"), S.ACTIVE)
	assert_eq(log.get_time_left(&"timed"), 6.0)
	log.report(&"ping")
	assert_true(log.turn_in(&"timed", bag).ok, "in time")
	log.advance_time(100.0)
	assert_eq(log.get_state(&"timed"), S.COMPLETED)
	disconnect_all([log])


func test_timer_runs_with_process() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := _event_quest(&"timed")
	quest.time_limit = 0.05
	var log := _log_with([quest], bag, db)
	log.set_process(true)
	log.accept(&"timed")
	for i in 20:
		await get_tree().process_frame
		if log.get_state(&"timed") == S.FAILED:
			break
	await wait_frames(1)
	assert_eq(log.get_state(&"timed"), S.FAILED)


func test_branches_lead_to_different_follow_ups() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5})
	var camp := QKQuest.make(&"camp", "Camp", [QKObjective.event(&"find", &"find_camp"),
		QKObjective.event(&"fight", &"fight", 2), QKObjective.event(&"talk", &"talk"), QKObjective.collect(&"bribe", &"wood", 5)])
	camp.objectives[1].branch = &"fight"
	camp.objectives[2].branch = &"talk"
	camp.objectives[3].branch = &"talk"
	var chief := _event_quest(&"chief")
	chief.requires_branch = {&"camp": &"fight"}
	var truce := _event_quest(&"truce")
	truce.requires_branch = {&"camp": &"talk"}
	var log := _log_with([camp, chief, truce], bag, db)
	assert_eq(log.book.validate(db), PackedStringArray())
	log.accept(&"camp")
	log.report(&"fight", 2)
	assert_eq(log.get_state(&"camp"), S.ACTIVE, "the common objective is still missing")
	log.report(&"find_camp")
	assert_eq(log.get_state(&"camp"), S.READY)
	assert_eq(log.get_branch(&"camp"), &"fight")
	assert_true(log.turn_in(&"camp", bag).ok)
	assert_eq(bag.count(&"wood"), 5, "the other branch's items are not taken")
	assert_eq(log.get_state(&"chief"), S.AVAILABLE)
	assert_eq(log.get_state(&"truce"), S.LOCKED)
	assert_eq(log.get_progress(&"camp", &"talk"), 0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(log.to_data()))
	var copy := _log_with([camp, chief, truce], bag, db)
	copy.load_data(data)
	assert_eq(copy.get_branch(&"camp"), &"fight")
	assert_eq(copy.get_state(&"chief"), S.AVAILABLE)
	var broken := _event_quest(&"broken")
	broken.requires_branch = {&"camp": &"sneak"}
	log.book.add_quest(broken)
	assert_eq(log.book.validate(db).size(), 1)


func test_reach_objectives_and_targets() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := QKQuest.make(&"trip", "Trip", [QKObjective.reach(&"gate", &"gate", "Go to the gate"),
		QKObjective.reach_position(&"tower", Vector2(100, 50), 5.0, "Climb the tower")])
	var log := _log_with([quest], bag, db)
	assert_true(log.get_target().is_empty(), "not accepted")
	log.accept(&"trip")
	var target := log.get_target()
	assert_eq(target.objective_id, &"tower", "the gate has no known place yet")
	assert_eq(target.position, Vector3(100, 50, 0))
	var gate := Node3D.new()
	add_to_tree(gate)
	gate.global_position = Vector3(1, 2, 3)
	log.register_zone(&"gate", gate)
	target = log.get_target(&"trip")
	assert_eq(target.objective_id, &"gate")
	assert_eq(target.position, Vector3(1, 2, 3))
	log.update_position(Vector2(100, 60))
	assert_eq(log.get_progress(&"trip", &"tower"), 0, "10 m away, radius 5")
	log.update_position(Vector2(103, 52))
	assert_eq(log.get_progress(&"trip", &"tower"), 1)
	log.reach(&"gate")
	assert_eq(log.get_state(&"trip"), S.READY)
	assert_true(log.get_target().is_empty(), "nothing left to reach")


func test_quest_zone_on_an_area() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var quest := QKQuest.make(&"trip", "Trip", [QKObjective.reach(&"gate", &"gate")])
	var log := _log_with([quest], bag, db)
	log.accept(&"trip")
	var area := Area2D.new()
	area.position = Vector2(40, 30)
	var zone := QKQuestZone.new()
	zone.zone_id = &"gate"
	zone.quest_log = log
	area.add_child(zone)
	add_to_tree(area)
	assert_eq(log.get_target().position, Vector3(40, 30, 0), "the area is the target")
	var stranger := Node2D.new()
	add_to_tree(stranger)
	area.body_entered.emit(stranger)
	assert_eq(log.get_state(&"trip"), S.ACTIVE, "not the player")
	var player := Node2D.new()
	player.add_to_group(&"player")
	add_to_tree(player)
	area.body_entered.emit(player)
	assert_eq(log.get_state(&"trip"), S.READY)


func test_version_1_saves_still_load() -> void:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5})
	var log := make_log(db, bag)
	var old := {"version": 1, "states": {"firewood": "completed", "wolves": "active"},
		"events": {"wolves": {"kills": 2}}, "tracked": ["wolves"]}
	assert_true(log.load_data(old))
	assert_eq(log.get_state(&"firewood"), S.COMPLETED)
	assert_eq(log.get_state(&"alchemist"), S.AVAILABLE)
	assert_eq(log.get_progress(&"wolves", &"kills"), 2)
	assert_eq(log.times_completed(&"firewood"), 1)
	assert_eq(log.get_time_left(&"wolves"), -1.0)
	assert_eq(int(log.to_data().version), 2)


func test_validation_of_new_fields() -> void:
	var db := make_db()
	var book := make_book()
	var quest := QKQuest.make(&"bad", "Bad", [QKObjective.reach(&"nowhere", &"")])
	quest.extra_rewards = [QKReward.item(&"crown")]
	quest.reward_choices = [QKReward.xp(5), null]
	book.add_quest(quest)
	assert_eq(book.validate(db).size(), 3, str(book.validate(db)))
