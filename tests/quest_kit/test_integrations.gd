extends "res://tests/quest_kit/qk_test_case.gd"
## The dialogue bridge (Dialogue Manager / Dialogic, without either installed) and the
## journal's new parts.


class FakeDialogic extends Node:
	signal signal_event(argument: Variant)


func _bridge() -> Dictionary:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5})
	var log := make_log(db, bag)
	var bridge := QKDialogueBridge.new()
	bridge.quest_log = log
	add_to_tree(bridge)
	return {"bridge": bridge, "log": log, "bag": bag}


func test_bridge_mutations_and_conditions() -> void:
	var w := _bridge()
	var bridge: QKDialogueBridge = w.bridge
	assert_true(bridge.is_available("firewood"))
	assert_true(bridge.accept("firewood"))
	assert_true(bridge.is_ready("firewood"))
	assert_true(bridge.is_active("firewood"))
	assert_eq(bridge.state("firewood"), "ready")
	assert_true(bridge.complete("firewood"), "uses the watched bag")
	assert_true(bridge.is_completed("firewood"))
	assert_eq(w.bag.count(&"gold"), 10)
	var refused := []
	bridge.refused.connect(func(_result: QKResult, text: String) -> void: refused.append(text))
	assert_false(bridge.accept("firewood"))
	assert_eq(refused.size(), 1)
	assert_true(bridge.run("accept wolves"))
	assert_true(bridge.run("advance kill_wolf 2"))
	assert_eq(bridge.progress("wolves", "kills"), 2)
	assert_true(bridge.run("report kill_wolf"))
	assert_true(bridge.is_completed("wolves"), "auto-complete")
	disconnect_all([bridge])


func test_bridge_listens_to_dialogic_when_present() -> void:
	var fake := FakeDialogic.new()
	fake.name = "Dialogic"
	add_to_tree(fake)
	var w := _bridge()
	fake.signal_event.emit("quest accept wolves")
	fake.signal_event.emit("not for us")
	fake.signal_event.emit({"a": 1})
	assert_true(w.bridge.is_active("wolves"))


func test_bridge_without_dialogic_or_log() -> void:
	var bridge := QKDialogueBridge.new()
	add_to_tree(bridge)
	# No log: refuses quietly (a warning, not an error) instead of crashing the dialogue.
	assert_eq(bridge.state("x"), "locked")


func test_journal_shows_choices_and_turns_in_the_picked_one() -> void:
	var db := make_db()
	var bag := make_bag(db)
	var log := make_log(db, bag)
	var quest := QKQuest.make(&"pick", "Pick", [QKObjective.event(&"do", &"ping")])
	quest.reward_choices = [QKReward.item(&"sword"), QKReward.xp(25)]
	quest.extra_rewards = [QKReward.reputation(&"village", 3)]
	log.book.add_quest(quest)
	var journal := QKJournalWindow.new()
	journal.quest_log = log
	journal.bag = bag
	add_to_tree(journal)
	log.accept(&"pick")
	log.report(&"ping")
	await wait_frames(2)
	journal.show_tab(QKJournalWindow.Tab.ACTIVE)
	await wait_frames(1)
	journal._select(&"pick")
	assert_true(journal._choices_row.visible)
	assert_eq(journal._choices.get_child_count(), 2)
	assert_true(journal._giver.text.length() > 0)
	journal._turn_in.pressed.emit()
	await wait_frames(2)
	assert_eq(log.get_state(&"pick"), QKQuestLog.State.READY, "no choice yet: refused")
	assert_false(journal._status.text.is_empty())
	journal._choices.get_child(0).pressed.emit()
	journal._turn_in.pressed.emit()
	await wait_frames(2)
	assert_eq(log.get_state(&"pick"), QKQuestLog.State.COMPLETED)
	assert_eq(bag.count(&"sword"), 1)


func test_demo_new_quests() -> void:
	var demo: Node = add_to_tree(load("res://demo/quest/quest_demo.tscn").instantiate())
	await wait_frames(3)
	var log: QKQuestLog = demo.quest_log
	var bag: IKContainer = demo.bag.container
	# Branch: talk the bandits into leaving, then feed them.
	log.accept(&"bandits")
	demo.map.walk_to(&"camp", true)
	demo.do_action(&"parley")
	assert_eq(log.get_state(&"bandits"), QKQuestLog.State.READY)
	assert_true(log.turn_in(&"bandits", bag).ok)
	assert_eq(int(demo.stats.xp), 40, "XP reached the demo's stats")
	assert_eq(log.get_state(&"truce"), QKQuestLog.State.AVAILABLE)
	assert_eq(log.get_state(&"chief"), QKQuestLog.State.LOCKED)
	# Compass target: the courier run to Mira's hut.
	log.accept(&"courier")
	assert_eq(log.get_target(&"courier").objective_id, &"run")
	demo.map.walk_to(&"mira_hut", true)
	assert_eq(log.get_state(&"courier"), QKQuestLog.State.COMPLETED)
	assert_eq(int(demo.stats.currencies.guild_marks), 5)
	# Daily herbs through the dialogue bridge.
	demo.do_action(&"mira")
	assert_true(log.get_state(&"daily_herbs") == QKQuestLog.State.ACTIVE)
	for i in 3:
		demo.do_action(&"herbs")
	demo.do_action(&"mira")
	assert_eq(log.get_state(&"daily_herbs"), QKQuestLog.State.COMPLETED)
	demo.do_action(&"next_day")
	assert_eq(log.get_state(&"daily_herbs"), QKQuestLog.State.AVAILABLE)
	demo._on_save()
	demo.stats.xp = 0
	demo._on_load()
	assert_eq(int(demo.stats.xp), 85, "stats saved with the quests")
