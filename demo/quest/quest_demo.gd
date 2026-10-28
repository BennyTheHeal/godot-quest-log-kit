extends IKInventoryUI
## Quest Log Kit demo: a village with ten quests (collect, hunt, talk, go to a place, a chain
## unlocked by another quest, an auto-completing one, a daily one, a timed one, a branch with
## two follow-ups, reward choices), XP / currency / reputation rewards, a mini-map with a
## compass, the on-screen tracker, the journal, a dialogue bridge, save / load and the four
## art directions.

const ART := "res://addons/inventory_kit/art/"
const DIRECTIONS := {"painted": "Hand-painted", "realistic": "Realistic", "cartoon": "Cartoon", "flat": "Flat"}
const SAVE_DIR := "user://quest_demo/"
const SITE := "https://banc-essai.site-testeurs.workers.dev/?src=quest-demo"
const VillageMap := preload("res://demo/quest/village_map.gd")

var bag: IKInventory
var quest_log: QKQuestLog
var journal: QKJournalWindow
var tracker: QKQuestTracker
var bridge: QKDialogueBridge
var map: Control
## What the game keeps from non-item rewards (the kit only announces them).
var stats := {"xp": 0, "currencies": {}, "reputation": {}}
## Days skipped with the "Next day" button: the demo's calendar for daily quests.
var day_offset := 0
var _stats_label: Label
var art_direction := ""
var _picker: OptionButton
var _status: Label
var _save := IKSaveFile.new(SAVE_DIR + "inventory.json")


static func available_directions() -> Array[String]:
	var result: Array[String] = []
	for da in DIRECTIONS:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			result.append(da)
	return result


static func make_book() -> QKQuestBook:
	var book := QKQuestBook.new()
	var firewood := _quest(book, &"firewood", "Firewood for Winter", "Old Tobin", &"main",
		"The nights are getting cold and Tobin's back is not what it was. Bring him oak logs.",
		[QKObjective.collect(&"logs", &"oak_log", 8, "Bring %d oak logs")], {&"gold_coins": 25, &"bread": 3})
	var wolves := _quest(book, &"wolves", "Wolf Trouble", "Captain Hale", &"side",
		"Wolves have been taking sheep at night. Thin the pack.",
		[QKObjective.event(&"kills", &"kill_wolf", 3, "Hunt %d wolves")], {&"iron_helmet": 1, &"gold_coins": 40})
	var remedy := _quest(book, &"remedy", "A Remedy for Mira", "Mira the alchemist", &"side",
		"Mira needs fresh herbs for her fever remedy, and wants to hear what you found.",
		[QKObjective.collect(&"herbs", &"herb", 5, "Gather %d herbs"), QKObjective.event(&"talk", &"talk_mira", 1, "Talk to Mira")],
		{&"health_potion": 3})
	remedy.prerequisites = [&"firewood"]
	var mine := _quest(book, &"mine", "The Old Mine", "Captain Hale", &"main",
		"With the wolves gone, the old mine can be reopened. Find the gate key in the ruins, then go there.",
		[QKObjective.collect(&"key", &"key", 1, "Find the mine key"),
			QKObjective.reach_position(&"reach", VillageMap.place_position(&"mine"), 12.0, "Reach the old mine", &"mine")],
		{&"iron_ingot": 5, &"gold_coins": 60})
	mine.prerequisites = [&"wolves"]
	mine.visible_when_locked = true
	var pelts := _quest(book, &"pelts", "Hunter's Pride", "Old Tobin", &"side",
		"Show Tobin you can hunt: keep four raw hides. They stay yours.",
		[QKObjective.collect(&"hides", &"rawhide", 4, "Hold %d raw hides")], {&"gold_coins": 15})
	pelts.objectives[0].consume_on_turn_in = false
	pelts.auto_complete = true

	var daily := _quest(book, &"daily_herbs", "Mira's Daily Herbs", "Mira the alchemist", &"daily",
		"Mira always needs more herbs. Come back every day.",
		[QKObjective.collect(&"herbs", &"herb", 3, "Bring %d herbs")], {})
	daily.extra_rewards = [QKReward.xp(15), QKReward.reputation(&"village", 5)]
	daily.repeatable = true
	daily.daily = true
	var courier := _quest(book, &"courier", "Urgent Letter", "Captain Hale", &"side",
		"Run this letter to Mira's hut before the patrol leaves. Click the map to walk.",
		[QKObjective.reach_position(&"run", VillageMap.place_position(&"mira_hut"), 10.0, "Run to Mira's hut", &"mira_hut")], {})
	courier.extra_rewards = [QKReward.xp(30), QKReward.currency(&"guild_marks", 5)]
	courier.time_limit = 30.0
	courier.repeatable = true
	courier.cooldown = 10.0
	courier.auto_complete = true
	var bandits := _quest(book, &"bandits", "The Bandit Camp", "Captain Hale", &"main",
		"Bandits camp east of the village. Drive them off, or talk them into leaving: your call.",
		[QKObjective.reach_position(&"camp", VillageMap.place_position(&"camp"), 12.0, "Find the bandit camp", &"camp"),
			QKObjective.event(&"fight", &"fight_bandits", 2, "Beat %d bandits"),
			QKObjective.event(&"talk", &"parley_bandits", 1, "Talk them into leaving")], {&"gold_coins": 20})
	bandits.objectives[1].branch = &"fight"
	bandits.objectives[2].branch = &"talk"
	bandits.extra_rewards = [QKReward.xp(40)]
	var chief := _quest(book, &"chief", "The Bandit Chief", "Captain Hale", &"main",
		"You beat his men. Now the chief himself. Pick your reward.",
		[QKObjective.event(&"chief", &"fight_bandits", 1, "Beat the chief")], {})
	chief.requires_branch = {&"bandits": &"fight"}
	chief.reward_choices = [QKReward.item(&"iron_helmet"), QKReward.item(&"health_potion", 3), QKReward.currency(&"guild_marks", 15)]
	chief.visible_when_locked = true
	var truce := _quest(book, &"truce", "An Uneasy Truce", "The bandits", &"main",
		"The bandits will leave in peace if they are fed. Bring them bread.",
		[QKObjective.collect(&"bread", &"bread", 2, "Bring %d loaves of bread")], {})
	truce.requires_branch = {&"bandits": &"talk"}
	truce.extra_rewards = [QKReward.reputation(&"bandits", 10)]
	truce.reward_choices = [QKReward.xp(50), QKReward.currency(&"guild_marks", 10)]
	truce.visible_when_locked = true
	return book


static func _quest(book: QKQuestBook, id: StringName, title: String, giver: String, category: StringName,
		description: String, objectives: Array[QKObjective], rewards: Dictionary) -> QKQuest:
	var quest := QKQuest.make(id, title, objectives, rewards)
	quest.giver = giver
	quest.category = category
	quest.description = description
	book.add_quest(quest)
	return quest


func _ready() -> void:
	var directions := available_directions()
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [directions[0], directions[0]])
	bag = IKInventory.new()
	bag.name = "Bag"
	bag.container_id = &"bag"
	bag.size = 12
	bag.database = database
	bag.initial_items.assign({&"oak_log": 3, &"gold_coins": 10, &"apple": 2})
	add_child(bag)
	quest_log = QKQuestLog.new()
	quest_log.name = "QuestLog"
	quest_log.book = make_book()
	quest_log.database = database
	quest_log.clock = func() -> float: return Time.get_unix_time_from_system() + day_offset * 86400.0
	add_child(quest_log)
	# The dialogue bridge, as a game would register it as an autoload "Quests".
	bridge = QKDialogueBridge.new()
	bridge.name = "Quests"
	bridge.quest_log = quest_log
	add_child(bridge)
	_build_layout(directions)
	super._ready()
	quest_log.watch(bag.container)
	journal.quest_log = quest_log
	journal.bag = bag.container
	tracker.quest_log = quest_log
	map.quest_log = quest_log
	quest_log.reward_granted.connect(_on_reward)
	quest_log.quest_expired.connect(func(quest: QKQuest) -> void:
		_set_status("Out of time: %s failed. It can be taken again soon." % quest.get_title(), true))
	bridge.refused.connect(func(_result: QKResult, text: String) -> void: _set_status(text, true))
	map.arrived.connect(func(place: StringName) -> void:
		quest_log.reach(place)
		_set_status("You arrive at: %s." % VillageMap.PLACES[place][1]))
	quest_log.quest_completed.connect(func(quest: QKQuest) -> void:
		_set_status("Quest completed: %s. Rewards are in your bag." % quest.get_title()))
	quest_log.state_changed.connect(func(quest: QKQuest, state: QKQuestLog.State) -> void:
		if state == QKQuestLog.State.READY:
			_set_status("%s: ready to turn in (journal)." % quest.get_title()))
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	apply_art_direction(directions[0])


func apply_art_direction(da: String) -> void:
	art_direction = da
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [da, da])
	bag.container.database = database
	cursor.container.database = database
	quest_log.database = database
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])
	journal.refresh()
	var index := available_directions().find(da)
	if _picker != null and index >= 0 and _picker.selected != index:
		_picker.select(index)


## What the buttons of the "village" do: a real game would call these from its world.
func do_action(action: StringName) -> void:
	match action:
		&"chop":
			_give(&"oak_log", 2, "You chop 2 oak logs.")
		&"herbs":
			_give(&"herb", 1, "You pick a bunch of herbs.")
		&"hunt":
			quest_log.report(&"kill_wolf")
			_give(&"rawhide", 1, "You drive off a wolf and keep its hide.")
		&"mira":
			# What a Dialogue Manager / Dialogic line would do: "do Quests.advance("talk_mira")".
			if bridge.is_ready("daily_herbs"):
				bridge.complete("daily_herbs")
				_set_status("Mira: \"Fresh herbs again, thank you!\"")
			elif bridge.is_available("daily_herbs"):
				bridge.accept("daily_herbs")
				_set_status("Mira: \"Could you bring me three herbs every day?\"")
			else:
				_set_status("Mira thanks you for the news from the woods.")
			bridge.run("advance talk_mira")
		&"ruins":
			if bag.container.has(&"key"):
				_set_status("Nothing else in the ruins.")
			else:
				_give(&"key", 1, "Under a fallen beam: an old iron key.")
		&"mine":
			map.walk_to(&"mine", true)
			_set_status("You reach the boarded-up mine entrance.")
		&"fight":
			if map.player.distance_to(VillageMap.place_position(&"camp")) > 15.0:
				_set_status("The bandits are at their camp: walk there on the map first.", true)
				return
			quest_log.report(&"fight_bandits")
			_set_status("You beat a bandit.")
		&"parley":
			if map.player.distance_to(VillageMap.place_position(&"camp")) > 15.0:
				_set_status("The bandits are at their camp: walk there on the map first.", true)
				return
			quest_log.report(&"parley_bandits")
			_set_status("The bandits listen. They are hungry more than mean.")
		&"next_day":
			day_offset += 1
			quest_log.check_cooldowns()
			_set_status("A night passes. Daily quests are back.")


func _give(item_id: StringName, amount: int, text: String) -> void:
	var result := bag.container.add(item_id, amount)
	_set_status(text if result.ok else IKText.result_message(result), not result.ok)


func _build_layout(directions: Array[String]) -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	var title := Label.new()
	title.text = "Quest Log Kit — demo"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	_picker = OptionButton.new()
	for da in directions:
		_picker.add_item(DIRECTIONS[da])
	_picker.item_selected.connect(func(index: int) -> void: apply_art_direction(directions[index]))
	_picker.focus_mode = FOCUS_NONE
	header.add_child(_picker)
	_button(header, "Save", _on_save)
	_button(header, "Load", _on_load)
	var site := LinkButton.new()
	site.text = "More kits & our games »"
	site.uri = SITE
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	body.add_child(left)
	_button(header, "Next day", func() -> void: do_action(&"next_day"))
	var grid := GridContainer.new()
	grid.columns = 4
	left.add_child(grid)
	for action in [[&"chop", "Chop wood"], [&"herbs", "Pick herbs"], [&"hunt", "Hunt a wolf"], [&"mira", "Talk to Mira"],
			[&"ruins", "Search ruins"], [&"mine", "Go to the mine"], [&"fight", "Fight bandits"], [&"parley", "Parley"]]:
		var action_id: StringName = action[0]
		_button(grid, action[1], func() -> void: do_action(action_id))
	var bag_frame := PanelContainer.new()
	left.add_child(bag_frame)
	var bag_box := VBoxContainer.new()
	bag_frame.add_child(bag_box)
	var bag_label := Label.new()
	bag_label.text = "Your bag"
	bag_box.add_child(bag_label)
	var view := IKContainerView.new()
	view.name = "BagView"
	view.columns = 6
	view.inventory = bag
	bag_box.add_child(view)
	tracker = QKQuestTracker.new()
	tracker.name = "Tracker"
	tracker.empty_text = "Accept a quest in the journal: it shows up here."
	left.add_child(tracker)
	_status = Label.new()
	_status.text = "Open the Available tab of the journal to start."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	left.add_child(_status)

	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	right.add_child(top)
	map = VillageMap.new()
	map.name = "Map"
	top.add_child(map)
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_stats_label.custom_minimum_size = Vector2(160, 0)
	top.add_child(_stats_label)
	_refresh_stats()
	journal = QKJournalWindow.new()
	journal.name = "Journal"
	journal.size_flags_horizontal = SIZE_EXPAND_FILL
	journal.size_flags_vertical = SIZE_EXPAND_FILL
	journal.close_requested.connect(func() -> void: _set_status("Cancel in the journal: a game would close it here."))
	right.add_child(journal)


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_save() -> void:
	return_held()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var error := _save.save([bag.container])
	var file := FileAccess.open(SAVE_DIR + "quests.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"quests": quest_log.to_data(), "stats": stats, "day_offset": day_offset}, "\t"))
	_set_status("Saved: bag and quests." if error == OK and file != null else "Save failed.", error != OK or file == null)


func _on_load() -> void:
	return_held()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "quests.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Nothing to load yet: press Save first.", true)
		return
	var report := _save.load_into([bag.container])
	if not report.ok:
		_set_status(report.error, true)
		return
	# Saves of demo 1.0 hold the quest data alone.
	if typeof(parsed.get("quests")) == TYPE_DICTIONARY:
		if typeof(parsed.get("stats")) == TYPE_DICTIONARY:
			stats = parsed.stats
		day_offset = int(parsed.get("day_offset", 0))
		parsed = parsed.quests
	quest_log.load_data(parsed)
	_refresh_stats()
	_set_status("Loaded.")


func _on_reward(kind: StringName, id: StringName, amount: int) -> void:
	match kind:
		QKReward.XP:
			stats.xp += amount
		QKReward.CURRENCY:
			stats.currencies[String(id)] = stats.currencies.get(String(id), 0) + amount
		QKReward.REPUTATION:
			stats.reputation[String(id)] = stats.reputation.get(String(id), 0) + amount
	_refresh_stats()


func _refresh_stats() -> void:
	var parts := PackedStringArray(["Level %d · %d/100 XP" % [1 + int(stats.xp) / 100, int(stats.xp) % 100]])
	for id: String in stats.currencies:
		parts.append("%d %s" % [stats.currencies[id], id.capitalize()])
	for id: String in stats.reputation:
		parts.append("%s %+d" % [id.capitalize(), stats.reputation[id]])
	_stats_label.text = "Rewards your game keeps (reward_granted):\n" + "\n".join(parts)


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
