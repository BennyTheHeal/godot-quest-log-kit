class_name QKText
extends RefCounted
## Every text Quest Log Kit shows to players goes through here, so it can be translated
## or reworded with Godot's translation system (template:
## [code]addons/quest_kit/translations/quest_kit.csv[/code]), like Inventory Kit's IKText.

static var result_texts := {
	QKResult.Code.INVALID_ARGUMENT: "That did not work.",
	QKResult.Code.UNKNOWN_QUEST: "Unknown quest.",
	QKResult.Code.LOCKED: "This quest is not available yet.",
	QKResult.Code.WRONG_STATE: "That is not possible for this quest now.",
	QKResult.Code.NOT_READY: "Some objectives are not done yet.",
	QKResult.Code.NO_ROOM: "Not enough room in your bag for the reward.",
	QKResult.Code.MISSING_ITEMS: "You no longer have the items this quest needs.",
	QKResult.Code.INVENTORY_ERROR: "That did not work.",
	QKResult.Code.CHOICE_REQUIRED: "Choose a reward first.",
	QKResult.Code.ON_COOLDOWN: "Come back later for this quest.",
}

## Name of each state, as shown in the journal.
static var state_texts := {
	0: "Locked", 1: "Available", 2: "In progress", 3: "Ready to turn in", 4: "Completed", 5: "Failed",
}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


static func result_message(result: QKResult) -> String:
	if result == null or result.ok:
		return ""
	if result.inventory_result != null and not result.inventory_result.player_text.is_empty():
		return IKText.result_message(result.inventory_result)
	return t(result_texts.get(result.code, "That did not work."))


static func state_text(state: int) -> String:
	return t(state_texts.get(state, ""))


## "1:05", "12:00", "2 h 05" for timers and cooldowns.
static func duration(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	if total >= 3600:
		return t("%d h %02d") % [total / 3600, (total % 3600) / 60]
	return "%d:%02d" % [total / 60, total % 60]
