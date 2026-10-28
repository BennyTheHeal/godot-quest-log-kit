class_name QKQuestTracker
extends PanelContainer
## On-screen list of the tracked quests and their objectives, updated live.
## Put it in your HUD and set [member quest_log].

@export var quest_log: QKQuestLog:
	set(value):
		if quest_log != null and quest_log.changed.is_connected(refresh):
			quest_log.changed.disconnect(refresh)
			quest_log.timers_changed.disconnect(refresh)
		quest_log = value
		if quest_log != null:
			quest_log.changed.connect(refresh)
			quest_log.timers_changed.connect(refresh)
		refresh()
## Text shown when nothing is tracked. Empty = hide the tracker.
@export var empty_text: String = ""

var _text := RichTextLabel.new()


func _init() -> void:
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(260, 0)
	_text.mouse_filter = MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	margin.add_child(_text)


func refresh() -> void:
	if quest_log == null:
		_text.text = ""
		return
	var lines := PackedStringArray()
	for quest_id in quest_log.get_tracked():
		var quest := quest_log.book.get_quest(quest_id)
		if quest == null:
			continue
		var ready := quest_log.get_state(quest_id) == QKQuestLog.State.READY
		var left := quest_log.get_time_left(quest_id)
		var timer := "  [color=#ff9a7a]%s[/color]" % QKText.duration(left) if left >= 0.0 else ""
		lines.append("[b]%s[/b]%s%s" % [quest.get_title(), "  [color=#ffd25a]%s[/color]" % QKText.t("Ready!") if ready else "", timer])
		for objective in quest.objectives:
			if objective == null:
				continue
			var done := quest_log.get_progress(quest_id, objective.id)
			var finished := done >= objective.amount
			var count := "  %d/%d" % [done, objective.amount] if objective.amount > 1 else ""
			var line := "• %s%s%s" % [objective.get_text(), count, "  (%s)" % QKText.t("optional") if objective.optional else ""]
			lines.append("[color=#7ee08a][s]%s[/s][/color]" % line if finished else line)
	if lines.is_empty() and not empty_text.is_empty():
		lines.append("[color=#aab1bf]%s[/color]" % QKText.t(empty_text))
	_text.text = "\n".join(lines)
	visible = not lines.is_empty()
