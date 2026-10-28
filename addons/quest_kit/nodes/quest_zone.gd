class_name QKQuestZone
extends Node
## Put it under an Area2D or an Area3D: when the player enters the area, REACH
## objectives that wait for [member zone_id] complete ([method QKQuestLog.reach]).
## The area is also registered as the target of those objectives, so
## [method QKQuestLog.get_target] follows it for markers and compasses.
##
## The player is any body (or area) in the [member player_group] group.

@export var quest_log: QKQuestLog:
	set(value):
		if quest_log != null and is_inside_tree():
			quest_log.unregister_zone(zone_id)
		quest_log = value
		if is_inside_tree():
			_register()
## Matches [member QKObjective.target] of REACH objectives.
@export var zone_id: StringName
@export var player_group: StringName = &"player"
## Also report when an Area (not only a body) of the group enters, e.g. a player hitbox.
@export var detect_areas: bool = false


func _ready() -> void:
	var area := get_parent()
	if area == null or not area.has_signal(&"body_entered"):
		push_warning("QKQuestZone '%s' must be a child of an Area2D or an Area3D." % zone_id)
		return
	area.connect(&"body_entered", _on_entered)
	if area.has_signal(&"area_entered"):
		area.connect(&"area_entered", _on_area_entered)
	_register()


func _exit_tree() -> void:
	if quest_log != null and is_instance_valid(quest_log):
		quest_log.unregister_zone(zone_id)


func _register() -> void:
	if quest_log != null and not zone_id.is_empty():
		quest_log.register_zone(zone_id, get_parent())


func _on_entered(body: Node) -> void:
	if quest_log != null and body.is_in_group(player_group):
		quest_log.reach(zone_id)


func _on_area_entered(area: Node) -> void:
	if detect_areas:
		_on_entered(area)
