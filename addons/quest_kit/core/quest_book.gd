@tool
class_name QKQuestBook
extends Resource
## Every quest of the game. Save it as a .tres and share it.

@export var quests: Array[QKQuest] = []

var _index: Dictionary = {}
var _indexed_count := -1


func get_quest(quest_id: StringName) -> QKQuest:
	if _indexed_count != quests.size():
		_index.clear()
		for quest in quests:
			if quest != null and not quest.id.is_empty():
				_index[quest.id] = quest
		_indexed_count = quests.size()
	return _index.get(quest_id)


func add_quest(quest: QKQuest) -> void:
	quests.append(quest)
	_indexed_count = -1


## Problems a developer should fix: duplicate ids, unknown items or prerequisites, empty quests.
func validate(database: IKItemDatabase) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for quest in quests:
		if quest == null:
			problems.append("empty slot in the quest list")
			continue
		if quest.id.is_empty() or seen.has(quest.id):
			problems.append("quest id missing or duplicated: '%s'" % quest.id)
		seen[quest.id] = true
		if quest.objectives.is_empty():
			problems.append("%s has no objective" % quest.id)
		var objective_ids := {}
		for objective in quest.objectives:
			if objective == null or objective.id.is_empty() or objective_ids.has(objective.id):
				problems.append("%s: objective id missing or duplicated" % quest.id)
				continue
			objective_ids[objective.id] = true
			if objective.kind == QKObjective.Kind.COLLECT and database != null and not database.has_item(objective.target):
				problems.append("%s: unknown item %s" % [quest.id, objective.target])
			if objective.kind == QKObjective.Kind.REACH and objective.target.is_empty() and not objective.has_position:
				problems.append("%s: objective %s has neither a zone id nor a position" % [quest.id, objective.id])
		for item_id in quest.rewards:
			if database != null and not database.has_item(item_id):
				problems.append("%s: unknown reward item %s" % [quest.id, item_id])
		for reward in quest.extra_rewards + quest.reward_choices:
			if reward == null:
				problems.append("%s: empty reward slot" % quest.id)
			elif reward.is_item() and database != null and not database.has_item(reward.id):
				problems.append("%s: unknown reward item %s" % [quest.id, reward.id])
		if quest.time_limit < 0 or quest.cooldown < 0:
			problems.append("%s: negative time limit or cooldown" % quest.id)
	for quest in quests:
		if quest == null:
			continue
		for required in quest.prerequisites:
			if not seen.has(required):
				problems.append("%s requires unknown quest %s" % [quest.id, required])
		for required in quest.requires_branch:
			var other := get_quest(required)
			if other == null:
				problems.append("%s requires unknown quest %s" % [quest.id, required])
			elif not other.get_branches().has(quest.requires_branch[required]):
				problems.append("%s requires unknown branch %s of %s" % [quest.id, quest.requires_branch[required], required])
	return problems
