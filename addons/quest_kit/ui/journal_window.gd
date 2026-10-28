class_name QKJournalWindow
extends PanelContainer
## A ready-to-use quest journal: In progress / Available / Done tabs, quest list,
## details with objectives and rewards (items, XP, currencies, reputation, a reward to
## choose), timers, Accept, Turn in, Abandon and Track buttons.
##
## Works with the mouse, the keyboard and a gamepad (focus navigation; Q / E or LB / RB
## switch tabs). Set [member quest_log] and [member bag].

signal refused(result: QKResult, text: String)
## The player pressed Cancel (Escape / B) in the window.
signal close_requested

enum Tab { ACTIVE, AVAILABLE, DONE }

const TAB_PREVIOUS := &"qk_previous_tab"
const TAB_NEXT := &"qk_next_tab"

@export var quest_log: QKQuestLog:
	set(value):
		if quest_log != null and quest_log.changed.is_connected(_queue_refresh):
			quest_log.changed.disconnect(_queue_refresh)
			quest_log.timers_changed.disconnect(_on_timers_changed)
		quest_log = value
		if quest_log != null:
			quest_log.changed.connect(_queue_refresh)
			quest_log.timers_changed.connect(_on_timers_changed)
		_queue_refresh()
## Where rewards go (and collected items are taken from).
var bag: IKContainer
## Accept and Turn in from the journal. Turn it off when quests are only given and
## turned in by talking to NPCs; the journal then only shows and tracks.
@export var allow_actions: bool = true

var current_tab: Tab = Tab.ACTIVE
var _tabs: Array[Button] = []
var _list := VBoxContainer.new()
var _empty := Label.new()
var _title := Label.new()
var _giver := Label.new()
var _text := RichTextLabel.new()
var _rewards := HFlowContainer.new()
var _choices_row := HBoxContainer.new()
var _choices := HFlowContainer.new()
var _choice := -1
var _choice_quest: StringName
var _accept := Button.new()
var _turn_in := Button.new()
var _abandon := Button.new()
var _track := CheckBox.new()
var _status := Label.new()
var _selected: StringName
var _refresh_queued := false


func _init() -> void:
	_build()


func _ready() -> void:
	_ensure_actions()
	refresh()


func show_tab(tab: int) -> void:
	current_tab = posmod(tab, 3) as Tab
	_selected = &""
	refresh()
	_focus_selected.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	for i in _tabs.size():
		_tabs[i].button_pressed = i == current_tab
		_tabs[i].modulate = Color.WHITE if i == current_tab else Color(1, 1, 1, 0.55)
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focused != null and _list.is_ancestor_of(focused)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var quests := _tab_quests()
	for quest in quests:
		var button := Button.new()
		var state := quest_log.get_state(quest.id)
		var locked := state == QKQuestLog.State.LOCKED
		button.text = "???" if locked else quest.get_title()
		if state == QKQuestLog.State.READY:
			button.text += "  · " + QKText.t("Ready!")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = quest.id == _selected
		button.disabled = locked
		var quest_id := quest.id
		button.set_meta(&"quest_id", quest_id)
		button.pressed.connect(func() -> void: _select(quest_id))
		button.focus_entered.connect(func() -> void: _select(quest_id, false))
		_list.add_child(button)
	_empty.visible = quests.is_empty()
	_empty.text = [QKText.t("No quest in progress."), QKText.t("No quest available right now."), QKText.t("No quest done yet.")][current_tab]
	if not quests.any(func(q: QKQuest) -> bool: return q.id == _selected):
		_selected = &""
		for quest in quests:
			if quest_log.get_state(quest.id) != QKQuestLog.State.LOCKED:
				_selected = quest.id
				break
	_refresh_details()
	if had_focus:
		_focus_selected.call_deferred()


# --- Building ----------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = QKText.t("Journal")
	title.add_theme_font_size_override(&"font_size", 22)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var hint := Label.new()
	hint.text = QKText.t("Q / E · LB / RB")
	hint.modulate = Color(1, 1, 1, 0.55)
	header.add_child(hint)
	var tab_row := HBoxContainer.new()
	column.add_child(tab_row)
	var group := ButtonGroup.new()
	for label in ["In progress", "Available", "Done"]:
		var tab := Button.new()
		tab.text = QKText.t(label)
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = FOCUS_NONE
		var index := _tabs.size()
		tab.pressed.connect(func() -> void: show_tab(index))
		tab_row.add_child(tab)
		_tabs.append(tab)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(230, 180)
	body.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	list_box.add_child(_list)
	_empty.modulate = Color(1, 1, 1, 0.6)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_box.add_child(_empty)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = SIZE_EXPAND_FILL
	details.add_theme_constant_override(&"separation", 6)
	body.add_child(details)
	_title.add_theme_font_size_override(&"font_size", 20)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_title)
	_giver.modulate = Color(1, 1, 1, 0.65)
	details.add_child(_giver)
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(_text)
	var rewards_row := HBoxContainer.new()
	details.add_child(rewards_row)
	var rewards_label := Label.new()
	rewards_label.text = QKText.t("Rewards:")
	rewards_row.add_child(rewards_label)
	_rewards.add_theme_constant_override(&"separation", 6)
	rewards_row.add_child(_rewards)
	_rewards.size_flags_horizontal = SIZE_EXPAND_FILL
	details.add_child(_choices_row)
	var choices_label := Label.new()
	choices_label.text = QKText.t("Choose one:")
	_choices_row.add_child(choices_label)
	_choices.add_theme_constant_override(&"h_separation", 6)
	_choices.size_flags_horizontal = SIZE_EXPAND_FILL
	_choices_row.add_child(_choices)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	details.add_child(buttons)
	for button: Button in [_accept, _turn_in, _abandon]:
		button.custom_minimum_size = Vector2(0, 40)
		buttons.add_child(button)
	_accept.text = QKText.t("Accept")
	_accept.pressed.connect(func() -> void: _act(quest_log.accept(_selected)))
	_turn_in.text = QKText.t("Turn in")
	_turn_in.pressed.connect(func() -> void: _act(quest_log.turn_in(_selected, bag, _choice)))
	_abandon.text = QKText.t("Abandon")
	_abandon.pressed.connect(func() -> void: _act(quest_log.abandon(_selected)))
	_track.text = QKText.t("Track")
	_track.toggled.connect(func(on: bool) -> void:
		if quest_log != null and _selected != &"" and quest_log.is_tracked(_selected) != on:
			if not quest_log.set_tracked(_selected, on):
				_track.set_pressed_no_signal(false)
				_set_status(QKText.t("Too many tracked quests."), true))
	buttons.add_child(_track)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_status)


# --- Content -----------------------------------------------------------------

func _tab_quests() -> Array[QKQuest]:
	var found: Array[QKQuest] = []
	if quest_log == null or quest_log.book == null:
		return found
	for quest in quest_log.book.quests:
		if quest == null:
			continue
		var state := quest_log.get_state(quest.id)
		var wanted := false
		match current_tab:
			Tab.ACTIVE:
				wanted = state == QKQuestLog.State.ACTIVE or state == QKQuestLog.State.READY
			Tab.AVAILABLE:
				wanted = state == QKQuestLog.State.AVAILABLE or (state == QKQuestLog.State.LOCKED and quest.visible_when_locked)
			Tab.DONE:
				wanted = state == QKQuestLog.State.COMPLETED or state == QKQuestLog.State.FAILED
		if wanted:
			found.append(quest)
	return found


func _select(quest_id: StringName, grab: bool = true) -> void:
	_selected = quest_id
	for child in _list.get_children():
		if child is Button:
			var mine: bool = child.get_meta(&"quest_id", &"") == quest_id and quest_id != &""
			child.set_pressed_no_signal(mine)
			if grab and mine and not child.has_focus():
				child.grab_focus()
	_refresh_details()


func _refresh_details() -> void:
	var quest := quest_log.book.get_quest(_selected) if quest_log != null and _selected != &"" else null
	for box: Control in [_rewards, _choices]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	if quest == null or _choice_quest != _selected:
		_choice = -1
		_choice_quest = _selected
	_choices_row.visible = quest != null and not quest.reward_choices.is_empty()
	if quest == null:
		_title.text = ""
		_giver.text = ""
		_text.text = ""
		for button: Button in [_accept, _turn_in, _abandon]:
			button.visible = false
		_track.visible = false
		return
	var state := quest_log.get_state(quest.id)
	_title.text = quest.get_title()
	_giver.text = _status_line(quest, state)
	var lines := PackedStringArray()
	if not quest.description.is_empty():
		lines.append("[i]%s[/i]" % QKText.t(quest.description))
	lines.append("")
	for objective in quest.objectives:
		if objective == null:
			continue
		var done := quest_log.get_progress(quest.id, objective.id)
		var finished := done >= objective.amount
		var line := "• %s  %d/%d%s%s" % [objective.get_text(), done, objective.amount,
			"  (%s)" % QKText.t("optional") if objective.optional else "",
			"  [%s: %s]" % [QKText.t("path"), QKText.t(String(objective.branch).capitalize())] if not objective.branch.is_empty() else ""]
		lines.append("[color=#7ee08a]%s[/color]" % line if finished else line)
	_text.text = "\n".join(lines)
	var database := quest_log.database if quest_log.database != null else (bag.database if bag != null else null)
	for item_id in quest.rewards:
		_rewards.add_child(_reward_view(QKReward.item(item_id, quest.rewards[item_id]), database))
	for reward in quest.extra_rewards:
		if reward != null:
			_rewards.add_child(_reward_view(reward, database))
	var group := ButtonGroup.new()
	for i in quest.reward_choices.size():
		var reward := quest.reward_choices[i]
		if reward == null:
			continue
		var pick := Button.new()
		pick.toggle_mode = true
		pick.button_group = group
		pick.button_pressed = i == _choice
		pick.text = reward.get_text(database)
		if reward.is_item() and database != null and database.get_item(reward.id) != null:
			pick.icon = database.get_item(reward.id).icon
			pick.expand_icon = true
		pick.custom_minimum_size = Vector2(0, 40)
		pick.set_meta(&"choice", i)
		var index := i
		pick.pressed.connect(func() -> void: _choice = index)
		_choices.add_child(pick)
	var in_progress := state == QKQuestLog.State.ACTIVE or state == QKQuestLog.State.READY
	_accept.visible = allow_actions and state == QKQuestLog.State.AVAILABLE
	_turn_in.visible = allow_actions and in_progress
	_turn_in.disabled = state != QKQuestLog.State.READY
	_abandon.visible = in_progress
	_track.visible = in_progress
	_track.set_pressed_no_signal(quest_log.is_tracked(quest.id))


## One reward: an icon for items, a short text for the rest.
func _reward_view(reward: QKReward, database: IKItemDatabase) -> Control:
	var box := HBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.tooltip_text = reward.get_text(database)
	if reward.is_item():
		var definition := database.get_item(reward.id) if database != null else null
		var icon := TextureRect.new()
		icon.texture = definition.icon if definition != null else null
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		box.add_child(icon)
	var label := Label.new()
	label.text = "×%d" % reward.amount if reward.is_item() else reward.get_text(database)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(label)
	return box


## Giver, state, and the clocks: time left, repeat cooldown.
func _status_line(quest: QKQuest, state: QKQuestLog.State) -> String:
	var parts := PackedStringArray()
	if not quest.giver.is_empty():
		parts.append(QKText.t(quest.giver))
	parts.append(QKText.state_text(state))
	var left := quest_log.get_time_left(quest.id)
	if left >= 0.0:
		parts.append(QKText.t("Time left: %s") % QKText.duration(left))
	elif quest.time_limit > 0.0 and state == QKQuestLog.State.AVAILABLE:
		parts.append(QKText.t("Time limit: %s") % QKText.duration(quest.time_limit))
	if quest.repeatable:
		var cooldown := quest_log.get_cooldown_left(quest.id)
		if cooldown > 0.0:
			parts.append(QKText.t("Again in %s") % QKText.duration(cooldown))
		else:
			parts.append(QKText.t("Daily") if quest.daily else QKText.t("Repeatable"))
	return " · ".join(parts)


func _on_timers_changed() -> void:
	if _selected != &"" and quest_log != null and quest_log.book.get_quest(_selected) != null:
		_giver.text = _status_line(quest_log.book.get_quest(_selected), quest_log.get_state(_selected))


func _act(result: QKResult) -> void:
	if result == null:
		return
	if result.ok:
		_set_status("", false)
	else:
		var text := QKText.result_message(result)
		_set_status(text, true)
		refused.emit(result, text)
	_queue_refresh()


func _set_status(text: String, warning: bool) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.62, 0.52) if warning else Color(0.6, 1, 0.65)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(TAB_PREVIOUS):
		show_tab(current_tab - 1)
		accept_event()
	elif event.is_action_pressed(TAB_NEXT):
		show_tab(current_tab + 1)
		accept_event()
	elif event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		accept_event()


func _focus_selected() -> void:
	if not is_inside_tree():
		return
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion() and not child.disabled:
			if _selected == &"" or child.button_pressed:
				child.grab_focus()
				return


func _ensure_actions() -> void:
	var defaults := {
		TAB_PREVIOUS: [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		TAB_NEXT: [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
	}
	for action: StringName in defaults:
		if InputMap.has_action(action):
			continue  # the game's own bindings win
		InputMap.add_action(action)
		for event: InputEvent in defaults[action]:
			InputMap.action_add_event(action, event)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


## Several signals fire for one change: rebuild once, next frame.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()
