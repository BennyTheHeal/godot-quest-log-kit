@tool
class_name QKObjective
extends Resource
## One step of a quest: hold some items, count game events (kills, talks), or go somewhere.

enum Kind {
	## Have [member amount] of item [member target] in the watched container.
	COLLECT,
	## Report event [member target] [member amount] times with [method QKQuestLog.report].
	EVENT,
	## Go to zone [member target] ([method QKQuestLog.reach], or a [QKQuestZone] on an
	## Area2D / Area3D), or within [member radius] of [member position]
	## ([method QKQuestLog.update_position]) when [member has_position] is on.
	REACH,
}

## Stable id inside its quest, stored in save files.
@export var id: StringName
@export var kind: Kind = Kind.EVENT
## Item id (COLLECT) or event id (EVENT), e.g. &"oak_log", &"kill_wolf", &"talk_mira".
@export var target: StringName
@export_range(1, 9999) var amount: int = 1
## Text shown to players. "%d" is replaced by the amount: "Collect %d oak logs".
@export var text: String = ""
## COLLECT: the items are taken when the quest is turned in.
@export var consume_on_turn_in: bool = true
## Optional objectives do not block completion.
@export var optional: bool = false
## Branches: objectives with the same non-empty branch form one path. The quest needs
## every common objective (empty branch) plus every objective of ONE branch; the first
## branch done is the one taken ([method QKQuestLog.get_branch]) and can unlock its own
## follow-up ([member QKQuest.requires_branch]).
@export var branch: StringName
@export_group("Target")
## The objective has a place in the world: shown by markers and compasses
## ([method QKQuestLog.get_target]); for REACH, being within [member radius] completes it.
@export var has_position: bool = false
## World position (2D games: x, y and z = 0).
@export var position: Vector3 = Vector3.ZERO
@export var radius: float = 2.0


static func collect(p_id: StringName, item_id: StringName, p_amount: int, p_text: String = "") -> QKObjective:
	var objective := QKObjective.new()
	objective.id = p_id
	objective.kind = Kind.COLLECT
	objective.target = item_id
	objective.amount = p_amount
	objective.text = p_text
	return objective


static func event(p_id: StringName, event_id: StringName, p_amount: int = 1, p_text: String = "") -> QKObjective:
	var objective := QKObjective.new()
	objective.id = p_id
	objective.kind = Kind.EVENT
	objective.target = event_id
	objective.amount = p_amount
	objective.text = p_text
	return objective


## Go to zone [param zone_id] (reported by [method QKQuestLog.reach] or a [QKQuestZone]).
static func reach(p_id: StringName, zone_id: StringName, p_text: String = "") -> QKObjective:
	var objective := QKObjective.new()
	objective.id = p_id
	objective.kind = Kind.REACH
	objective.target = zone_id
	objective.text = p_text
	return objective


## Go within [param p_radius] of [param p_position] (Vector2 or Vector3), checked by
## [method QKQuestLog.update_position]. [param zone_id] also lets [method QKQuestLog.reach] complete it.
static func reach_position(p_id: StringName, p_position: Variant, p_radius: float, p_text: String = "", zone_id: StringName = &"") -> QKObjective:
	var objective := reach(p_id, zone_id, p_text)
	objective.has_position = true
	objective.position = to_vector3(p_position)
	objective.radius = p_radius
	return objective


static func to_vector3(value: Variant) -> Vector3:
	if value is Vector2 or value is Vector2i:
		return Vector3(value.x, value.y, 0)
	if value is Vector3 or value is Vector3i:
		return Vector3(value)
	return Vector3.ZERO


func get_text() -> String:
	var shown := QKText.t(text) if not text.is_empty() else String(target).capitalize()
	return shown % amount if shown.contains("%d") else shown
