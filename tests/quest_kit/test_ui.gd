extends "res://tests/quest_kit/qk_test_case.gd"
## The journal, the tracker and the demo scene.


func _window() -> Dictionary:
	var db := make_db()
	var bag := make_bag(db, {&"wood": 5})
	var log := make_log(db, bag)
	var journal := QKJournalWindow.new()
	journal.quest_log = log
	journal.bag = bag
	add_to_tree(journal)
	var tracker := QKQuestTracker.new()
	tracker.quest_log = log
	add_to_tree(tracker)
	return {"journal": journal, "tracker": tracker, "log": log, "bag": bag}


func test_accept_and_turn_in_through_the_journal() -> void:
	var w := _window()
	await wait_frames(2)
	var journal: QKJournalWindow = w.journal
	journal.show_tab(QKJournalWindow.Tab.AVAILABLE)
	await wait_frames(1)
	assert_eq(journal._list.get_child_count(), 2, "firewood and wolves (alchemist locked, hidden)")
	journal._select(&"firewood")
	journal._accept.pressed.emit()
	await wait_frames(2)
	assert_eq(w.log.get_state(&"firewood"), QKQuestLog.State.READY)
	journal.show_tab(QKJournalWindow.Tab.ACTIVE)
	await wait_frames(1)
	journal._select(&"firewood")
	assert_false(journal._turn_in.disabled)
	journal._turn_in.pressed.emit()
	await wait_frames(2)
	assert_eq(w.bag.count(&"gold"), 10)
	journal.show_tab(QKJournalWindow.Tab.DONE)
	await wait_frames(1)
	assert_eq(journal._list.get_child_count(), 1)


func test_tracker_follows_the_log() -> void:
	var w := _window()
	await wait_frames(1)
	var tracker: QKQuestTracker = w.tracker
	assert_false(tracker.visible, "nothing tracked, no empty text: hidden")
	w.log.accept(&"wolves")
	assert_true(tracker.visible)
	assert_true(tracker._text.text.contains("0/3"), tracker._text.text)
	w.log.report(&"kill_wolf")
	assert_true(tracker._text.text.contains("1/3"), tracker._text.text)


func test_tab_shortcuts() -> void:
	var w := _window()
	await wait_frames(2)
	var journal: QKJournalWindow = w.journal
	var event := InputEventAction.new()
	event.action = QKJournalWindow.TAB_PREVIOUS
	event.pressed = true
	journal._unhandled_input(event)
	assert_eq(journal.current_tab, QKJournalWindow.Tab.DONE, "wraps around")


func test_demo_runs_in_every_art_direction() -> void:
	var demo: Node = add_to_tree(load("res://demo/quest/quest_demo.tscn").instantiate())
	await wait_frames(3)
	assert_eq(demo.quest_log.book.validate(demo.quest_log.database), PackedStringArray())
	for da in demo.available_directions():
		demo.apply_art_direction(da)
		await wait_frames(1)
	var log: QKQuestLog = demo.quest_log
	var bag: IKContainer = demo.bag.container
	log.accept(&"firewood")
	for i in 3:
		demo.do_action(&"chop")
	assert_true(log.turn_in(&"firewood", bag).ok)
	log.accept(&"pelts")
	for i in 4:
		demo.do_action(&"hunt")
	assert_eq(log.get_state(&"pelts"), QKQuestLog.State.COMPLETED, "auto-complete, hides kept")
	assert_eq(bag.count(&"rawhide"), 4)
	demo._on_save()
	log.accept(&"remedy")
	demo._on_load()
	assert_eq(log.get_state(&"remedy"), QKQuestLog.State.AVAILABLE, "Load restores the quests")
