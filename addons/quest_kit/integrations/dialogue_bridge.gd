class_name QKDialogueBridge
extends Node
## Calls the quest log from dialogue addons, with no dependency on them: nothing here
## names a Dialogue Manager or Dialogic class, so the kit works the same when they are
## not installed.
##
## Add this script as an autoload named [code]Quests[/code] (Project Settings > Globals),
## then give it your log once: [code]Quests.quest_log = $QuestLog[/code].
## [br][br]
## [b]Dialogue Manager[/b] (Nathan Hoad): mutations and conditions call autoloads directly.
## [codeblock]
## ~ mira
## if Quests.is_ready("remedy")
##     Mira: You found the herbs!
##     do Quests.complete("remedy")
## elif Quests.is_available("remedy")
##     Mira: Could you gather herbs for me?
##     - Of course.
##         do Quests.accept("remedy")
## do Quests.advance("talk_mira")
## [/codeblock]
## [b]Dialogic 2[/b]: a Signal event whose argument starts with [member dialogic_prefix]
## runs [method run]: [code][signal arg="quest accept remedy"][/code],
## [code][signal arg="quest advance talk_mira"][/code]. Dialogic 2 can also call the
## autoload itself (Call event: [code]do Quests.accept("remedy")[/code]).

## Emitted when a command from a dialogue was refused (locked, not ready...).
signal refused(result: QKResult, text: String)

@export var quest_log: QKQuestLog
## Where turn-in rewards go. Empty = the container the log watches.
var bag: IKContainer
## Dialogic Signal events starting with this word are quest commands. Empty = listen to none.
@export var dialogic_prefix: String = "quest"
## Outcome of the last accept / complete / fail / abandon.
var last_result: QKResult

var _dialogic: Node


func _ready() -> void:
	# Dialogic is an autoload named "Dialogic" when the addon is enabled; absent = nothing to do.
	_dialogic = get_node_or_null(^"/root/Dialogic")
	if _dialogic != null and _dialogic.has_signal(&"signal_event") and not dialogic_prefix.is_empty():
		_dialogic.connect(&"signal_event", _on_dialogic_signal)


func _exit_tree() -> void:
	if _dialogic != null and is_instance_valid(_dialogic) and _dialogic.is_connected(&"signal_event", _on_dialogic_signal):
		_dialogic.disconnect(&"signal_event", _on_dialogic_signal)


# --- Mutations -------------------------------------------------------------------

func accept(quest_id: String) -> bool:
	return _check(quest_log.accept(StringName(quest_id))) if _has_log() else false


## Reports a game event (EVENT objectives): "talk_mira", "kill_wolf"...
func advance(event_id: String, amount: int = 1) -> void:
	if _has_log():
		quest_log.report(StringName(event_id), amount)


## Completes REACH objectives waiting for this zone.
func reach(zone_id: String) -> void:
	if _has_log():
		quest_log.reach(StringName(zone_id))


## Turns the quest in (takes the items, gives the rewards). [param choice]: reward choice index.
func complete(quest_id: String, choice: int = -1) -> bool:
	if not _has_log():
		return false
	var target := bag if bag != null else quest_log.get_container()
	return _check(quest_log.turn_in(StringName(quest_id), target, choice))


func fail(quest_id: String) -> bool:
	return _check(quest_log.fail(StringName(quest_id))) if _has_log() else false


func abandon(quest_id: String) -> bool:
	return _check(quest_log.abandon(StringName(quest_id))) if _has_log() else false


# --- Conditions ------------------------------------------------------------------

## "locked", "available", "active", "ready", "completed" or "failed".
func state(quest_id: String) -> String:
	return QKQuestLog.State.keys()[quest_log.get_state(StringName(quest_id))].to_lower() if _has_log() else "locked"


func is_available(quest_id: String) -> bool:
	return state(quest_id) == "available"


## In progress (ready or not).
func is_active(quest_id: String) -> bool:
	return state(quest_id) in ["active", "ready"]


func is_ready(quest_id: String) -> bool:
	return state(quest_id) == "ready"


func is_completed(quest_id: String) -> bool:
	return _has_log() and quest_log.has_completed(StringName(quest_id))


func is_failed(quest_id: String) -> bool:
	return state(quest_id) == "failed"


func progress(quest_id: String, objective_id: String) -> int:
	return quest_log.get_progress(StringName(quest_id), StringName(objective_id)) if _has_log() else 0


func branch(quest_id: String) -> String:
	return String(quest_log.get_branch(StringName(quest_id))) if _has_log() else ""


# --- Text commands -----------------------------------------------------------------

## Runs "accept remedy", "advance talk_mira 2", "reach mine", "complete remedy 1",
## "fail courier", "abandon courier". Returns false if the command is unknown or refused.
func run(command: String) -> bool:
	var words := command.strip_edges().split(" ", false)
	if words.size() < 2:
		return false
	var amount := int(words[2]) if words.size() > 2 and words[2].is_valid_int() else -1
	match words[0].to_lower():
		"accept":
			return accept(words[1])
		"advance", "report":
			advance(words[1], maxi(1, amount))
			return true
		"reach":
			reach(words[1])
			return true
		"complete", "turn_in":
			return complete(words[1], amount)
		"fail":
			return fail(words[1])
		"abandon":
			return abandon(words[1])
	push_warning("QKDialogueBridge: unknown command '%s'" % command)
	return false


func _on_dialogic_signal(argument: Variant) -> void:
	if typeof(argument) != TYPE_STRING and typeof(argument) != TYPE_STRING_NAME:
		return
	var text := String(argument).strip_edges()
	if text.begins_with(dialogic_prefix + " "):
		run(text.substr(dialogic_prefix.length() + 1))


func _has_log() -> bool:
	if quest_log == null:
		push_warning("QKDialogueBridge: set quest_log first.")
		return false
	return true


func _check(result: QKResult) -> bool:
	last_result = result
	if not result.ok:
		refused.emit(result, QKText.result_message(result))
	return result.ok
