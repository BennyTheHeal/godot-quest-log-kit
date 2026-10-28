@tool
class_name QKQuest
extends Resource
## A quest: who gives it, what to do, what it pays.

## Stable id, stored in save files. Pick it once and never change it.
@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
## Who gives it ("Mira the alchemist"). Shown in the journal.
@export var giver: String = ""
## Free grouping for the journal: "main", "side"...
@export var category: StringName = &"side"
@export var objectives: Array[QKObjective] = []
## Items given when the quest is turned in, {item_id: amount}.
@export var rewards: Dictionary[StringName, int] = {}
## Quests that must be completed before this one becomes available.
@export var prerequisites: Array[StringName] = []
## True: completes by itself when every objective is done. False: the player turns it in.
@export var auto_complete: bool = false
## Shown in the journal before it is available (as "???").
@export var visible_when_locked: bool = false
## Rewards besides items: XP, currencies, reputation, your own kinds (items work too).
## Given in the turn-in, after [member rewards]; non-item kinds reach your game through
## [signal QKQuestLog.reward_granted].
@export var extra_rewards: Array[QKReward] = []
## The player picks ONE of these when turning in ([method QKQuestLog.turn_in]'s choice).
## A quest with choices never auto-completes: it waits to be turned in.
@export var reward_choices: Array[QKReward] = []
## Branch prerequisites: {quest id: branch}. That quest must be completed through that
## branch ([member QKObjective.branch]), e.g. {&"bandits": &"fight"}.
@export var requires_branch: Dictionary[StringName, StringName] = {}

@export_group("Repeat and time")
## Can be taken again after it is completed (or failed).
@export var repeatable: bool = false
## Repeatable: seconds of real time before it is available again (0 = at once).
@export var cooldown: float = 0.0
## Repeatable: available again at the next daily reset instead ([member QKQuestLog.daily_reset_hour]).
@export var daily: bool = false
## Seconds of play to finish it once accepted (0 = no limit). At 0 the quest fails.
## Counts game time: it stops while the tree is paused, and is saved.
@export var time_limit: float = 0.0


static func make(p_id: StringName, p_title: String, p_objectives: Array[QKObjective], p_rewards: Dictionary = {}) -> QKQuest:
	var quest := QKQuest.new()
	quest.id = p_id
	quest.title = p_title
	quest.objectives = p_objectives
	quest.rewards.assign(p_rewards)
	return quest


func get_title() -> String:
	return QKText.t(title) if not title.is_empty() else String(id).capitalize()


## Branch names used by the objectives, in order.
func get_branches() -> Array[StringName]:
	var found: Array[StringName] = []
	for objective in objectives:
		if objective != null and not objective.branch.is_empty() and not found.has(objective.branch):
			found.append(objective.branch)
	return found


func get_objective(objective_id: StringName) -> QKObjective:
	for objective in objectives:
		if objective != null and objective.id == objective_id:
			return objective
	return null
