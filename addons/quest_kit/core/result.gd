class_name QKResult
extends RefCounted
## Outcome of accepting, turning in or abandoning a quest.

enum Code {
	OK,
	INVALID_ARGUMENT,
	UNKNOWN_QUEST,
	## Prerequisites not completed yet.
	LOCKED,
	## Not in the right state (already active, not accepted, already completed...).
	WRONG_STATE,
	## Turn-in: some objectives are not done.
	NOT_READY,
	## Turn-in: the rewards do not fit in the bag.
	NO_ROOM,
	## Turn-in: collected items went missing before turning in.
	MISSING_ITEMS,
	INVENTORY_ERROR,
	## Turn-in: the quest has reward choices and none (or an invalid one) was given.
	CHOICE_REQUIRED,
	## Accept: a repeatable quest that is still cooling down.
	ON_COOLDOWN,
}

var code: Code = Code.OK
var message: String = ""
var inventory_result: IKResult
var quest_id: StringName

var ok: bool:
	get:
		return code == Code.OK


static func success(p_quest_id: StringName) -> QKResult:
	var result := QKResult.new()
	result.quest_id = p_quest_id
	return result


static func failure(error_code: Code, error_message: String = "", inventory: IKResult = null) -> QKResult:
	var result := QKResult.new()
	result.code = error_code
	result.message = error_message
	result.inventory_result = inventory
	return result


func code_name() -> String:
	return Code.keys()[code]


func _to_string() -> String:
	return "QKResult(OK, %s)" % quest_id if ok else "QKResult(%s: %s)" % [code_name(), message]
