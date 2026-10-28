class_name QKQuestLog
extends Node
## The player's quests: what is available, in progress, ready, done or failed.
##
## COLLECT objectives read the watched container live (drop the items and the
## objective goes back down). EVENT objectives count what your game reports, REACH
## objectives complete when the player gets somewhere.
## Turning in takes the collected items and gives the rewards in one [IKTransaction]:
## if the rewards do not fit, nothing is taken.
## [codeblock]
## quest_log.watch(bag.container)
## quest_log.accept(&"firewood")
## quest_log.report(&"kill_wolf")          # from your enemy's death
## var result := quest_log.turn_in(&"firewood", bag.container)
## quest_log.reward_granted.connect(_on_reward)  # XP, money, reputation: your game keeps them
## [/codeblock]
## Repeatable and daily quests use real time ([member clock]); time limits use game time
## (they count in [method _process] and stop while the tree is paused).

enum State { LOCKED, AVAILABLE, ACTIVE, READY, COMPLETED, FAILED }

signal state_changed(quest: QKQuest, state: State)
signal objective_progressed(quest: QKQuest, objective: QKObjective, done: int)
## Emitted when a quest is turned in (or auto-completes), after the rewards were given.
signal quest_completed(quest: QKQuest)
signal tracking_changed
## Anything changed: refresh the UI.
signal changed
## A non-item reward was earned (XP, currency, reputation, your own kinds). The kit does
## not keep these: add them to your game's stats here. [param id] is the currency /
## faction / skill id (empty for plain XP). Emitted before [signal quest_completed].
signal reward_granted(kind: StringName, id: StringName, amount: int)
## A timed quest ran out of time and failed.
signal quest_expired(quest: QKQuest)
## Once per second while a time limit or a cooldown runs: update timers on screen.
signal timers_changed

const DATA_VERSION := 2

@export var book: QKQuestBook
## Item definitions, for names in the UI. Defaults to the watched container's.
@export var database: IKItemDatabase
## Quests shown by the tracker at most.
@export_range(0, 16) var max_tracked: int = 3
## Newly accepted quests are tracked automatically (while there is room).
@export var track_on_accept: bool = true
## Local hour at which daily quests come back (0 = midnight).
@export_range(0, 23) var daily_reset_hour: int = 0

## Optional, called like [signal reward_granted]: [code]func(kind, id, amount)[/code].
var reward_callback: Callable
## Real time in seconds for cooldowns and daily quests. Empty = the system clock
## ([method Time.get_unix_time_from_system]). Point it at your game's calendar if it has one.
var clock: Callable
## Offset of the local time zone in minutes, for the daily reset. Read from the system.
var time_zone_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))

var _states: Dictionary = {}  # quest id -> State (only ACTIVE, READY, COMPLETED, FAILED are stored)
var _events: Dictionary = {}  # quest id -> {objective id -> count} (EVENT and REACH)
var _tracked: Array[StringName] = []
var _container: IKContainer
var _completing := false  # the turn-in transaction changes the bag: ignore that echo
var _time_left: Dictionary = {}  # quest id -> seconds of play left (timed quests in progress)
var _finished_at: Dictionary = {}  # quest id -> clock time of the last completion / failure
var _completions: Dictionary = {}  # quest id -> times completed
var _branches: Dictionary = {}  # quest id -> branch taken at the last completion
var _cooling: Dictionary = {}  # repeatable quests waiting for their cooldown
var _zones: Dictionary = {}  # zone id -> WeakRef to a Node2D / Node3D
var _second := 0.0


func _ready() -> void:
	if book == null:
		book = QKQuestBook.new()


func _process(delta: float) -> void:
	if not _time_left.is_empty():
		advance_time(delta, false)
	_second -= delta
	if _second <= 0.0:
		_second = 1.0
		if not _time_left.is_empty() or not _cooling.is_empty():
			check_cooldowns()
			timers_changed.emit()


func _exit_tree() -> void:
	if _container != null and _container.changed.is_connected(_on_container_changed):
		_container.changed.disconnect(_on_container_changed)


## The container COLLECT objectives are counted in (usually the player's bag).
func watch(container: IKContainer) -> void:
	if _container != null and _container.changed.is_connected(_on_container_changed):
		_container.changed.disconnect(_on_container_changed)
	_container = container
	if database == null and container != null:
		database = container.database
	if container != null:
		container.changed.connect(_on_container_changed)
	_refresh_ready()


## The container given to [method watch].
func get_container() -> IKContainer:
	return _container


# --- Reading -------------------------------------------------------------------

func get_state(quest_id: StringName) -> State:
	var quest := book.get_quest(quest_id)
	if _states.has(quest_id):
		var state: State = _states[quest_id]
		var finished := state == State.COMPLETED or state == State.FAILED
		if not (finished and quest != null and quest.repeatable and get_cooldown_left(quest_id) <= 0.0):
			return state
	if quest == null:
		return State.LOCKED
	for required in quest.prerequisites:
		if not has_completed(required):
			return State.LOCKED
	for required in quest.requires_branch:
		if not has_completed(required) or _branches.get(required, &"") != quest.requires_branch[required]:
			return State.LOCKED
	return State.AVAILABLE


func get_quests(state: State) -> Array[QKQuest]:
	var found: Array[QKQuest] = []
	for quest in book.quests:
		if quest != null and get_state(quest.id) == state:
			found.append(quest)
	return found


## Completed at least once (a repeatable quest taken again still counts for prerequisites).
func has_completed(quest_id: StringName) -> bool:
	return _states.get(quest_id) == State.COMPLETED or _completions.get(quest_id, 0) > 0


func times_completed(quest_id: StringName) -> int:
	return maxi(_completions.get(quest_id, 0), 1 if _states.get(quest_id) == State.COMPLETED else 0)


## The branch a quest was completed through (in progress: the branch already done). Empty if none.
func get_branch(quest_id: StringName) -> StringName:
	var state: Variant = _states.get(quest_id)
	if state == State.ACTIVE or state == State.READY:
		var quest := book.get_quest(quest_id)
		return _done_branch(quest) if quest != null else &""
	return _branches.get(quest_id, &"")


## Seconds of play left on a timed quest in progress; -1 when it has no time limit running.
func get_time_left(quest_id: StringName) -> float:
	return _time_left.get(quest_id, -1.0)


## Seconds before a repeatable quest can be taken again (0 when it can, or is not repeatable).
func get_cooldown_left(quest_id: StringName) -> float:
	var quest := book.get_quest(quest_id)
	var state: Variant = _states.get(quest_id)
	if quest == null or not quest.repeatable or not _finished_at.has(quest_id) or (state != State.COMPLETED and state != State.FAILED):
		return 0.0
	var now := _now()
	if quest.daily:
		return maxf(0.0, _next_reset(_finished_at[quest_id]) - now)
	return maxf(0.0, _finished_at[quest_id] + quest.cooldown - now)


## Progress of one objective: how many of [member QKObjective.amount] are done.
func get_progress(quest_id: StringName, objective_id: StringName) -> int:
	var quest := book.get_quest(quest_id)
	var objective := quest.get_objective(objective_id) if quest != null else null
	if objective == null:
		return 0
	var state := get_state(quest_id)
	if state == State.COMPLETED:
		var taken: StringName = _branches.get(quest_id, objective.branch)
		return objective.amount if objective.branch.is_empty() or objective.branch == taken else 0
	if state != State.ACTIVE and state != State.READY:
		return 0
	if objective.kind == QKObjective.Kind.COLLECT:
		return mini(objective.amount, _container.count(objective.target) if _container != null else 0)
	return mini(objective.amount, _events.get(quest_id, {}).get(objective_id, 0))


func is_objective_done(quest_id: StringName, objective_id: StringName) -> bool:
	var objective := book.get_quest(quest_id).get_objective(objective_id)
	return get_progress(quest_id, objective_id) >= objective.amount


## Every non-optional objective done (with branches: the common ones and those of one branch).
func are_objectives_done(quest_id: StringName) -> bool:
	var quest := book.get_quest(quest_id)
	if quest == null:
		return false
	for objective in quest.objectives:
		if objective != null and objective.branch.is_empty() and not objective.optional and get_progress(quest_id, objective.id) < objective.amount:
			return false
	return quest.get_branches().is_empty() or not _done_branch(quest).is_empty()


func get_tracked() -> Array[StringName]:
	return _tracked.duplicate()


func is_tracked(quest_id: StringName) -> bool:
	return _tracked.has(quest_id)


## Where the player should go next for this quest (with no id: the tracked quests first,
## then any quest in progress): the first unfinished objective that has a position
## ([member QKObjective.has_position]) or a zone registered with [method register_zone].
## Empty when there is none. Feed it to a marker or a compass:
## [codeblock]
## var target := quest_log.get_target()
## if not target.is_empty():
##     arrow.rotation = (Vector2(target.position.x, target.position.y) - player.position).angle()
## [/codeblock]
## Keys: quest_id, objective_id, position (Vector3; in 2D z = 0), radius, text.
func get_target(quest_id: StringName = &"") -> Dictionary:
	var candidates: Array[StringName] = []
	if not quest_id.is_empty():
		candidates.append(quest_id)
	else:
		candidates.append_array(_tracked)
		for other in book.quests:
			if other != null and not candidates.has(other.id):
				candidates.append(other.id)
	for candidate in candidates:
		var state := get_state(candidate)
		if state != State.ACTIVE and state != State.READY:
			continue
		var quest := book.get_quest(candidate)
		for objective in quest.objectives:
			if objective == null or get_progress(candidate, objective.id) >= objective.amount:
				continue
			var position: Variant = _objective_position(objective)
			if position != null:
				return {"quest_id": candidate, "objective_id": objective.id, "position": position,
					"radius": objective.radius, "text": objective.get_text()}
	return {}


## Lets [method get_target] follow a node (an Area2D / Area3D, an NPC) for the objectives
## whose [member QKObjective.target] is [param zone_id]. [QKQuestZone] does it for you.
func register_zone(zone_id: StringName, node: Node) -> void:
	if node == null:
		_zones.erase(zone_id)
	else:
		_zones[zone_id] = weakref(node)


func unregister_zone(zone_id: StringName) -> void:
	_zones.erase(zone_id)


# --- Actions -------------------------------------------------------------------

func accept(quest_id: StringName) -> QKResult:
	var quest := book.get_quest(quest_id)
	if quest == null:
		return QKResult.failure(QKResult.Code.UNKNOWN_QUEST, "no quest '%s'" % quest_id)
	var state := get_state(quest_id)
	if state == State.LOCKED:
		return QKResult.failure(QKResult.Code.LOCKED, "%s: prerequisites not completed" % quest_id)
	if state != State.AVAILABLE:
		if quest.repeatable and (state == State.COMPLETED or state == State.FAILED):
			return QKResult.failure(QKResult.Code.ON_COOLDOWN, "%s: %d s of cooldown left" % [quest_id, ceili(get_cooldown_left(quest_id))])
		return QKResult.failure(QKResult.Code.WRONG_STATE, "%s is %s" % [quest_id, State.keys()[state]])
	_states[quest_id] = State.ACTIVE
	_events[quest_id] = {}
	_cooling.erase(quest_id)
	if quest.time_limit > 0.0:
		_time_left[quest_id] = quest.time_limit
	if track_on_accept and _tracked.size() < max_tracked:
		_tracked.append(quest_id)
		tracking_changed.emit()
	state_changed.emit(quest, State.ACTIVE)
	_refresh_ready()
	changed.emit()
	return QKResult.success(quest_id)


## Counts [param amount] occurrences of a game event for every active quest that waits for it.
func report(event_id: StringName, amount: int = 1) -> void:
	if amount > 0:
		_count(func(objective: QKObjective) -> bool:
			return objective.kind == QKObjective.Kind.EVENT and objective.target == event_id, amount)


## The player entered zone [param zone_id]: completes the REACH objectives that wait for it.
## [QKQuestZone] calls it; call it yourself from any trigger.
func reach(zone_id: StringName) -> void:
	if not zone_id.is_empty():
		_count(func(objective: QKObjective) -> bool:
			return objective.kind == QKObjective.Kind.REACH and objective.target == zone_id, 1)


## The player is at [param position] (Vector2 or Vector3): completes the REACH objectives
## with a position within their radius. Call it when the player moves (every frame is fine).
func update_position(position: Variant) -> void:
	var here := QKObjective.to_vector3(position)
	_count(func(objective: QKObjective) -> bool:
		return objective.kind == QKObjective.Kind.REACH and objective.has_position \
			and here.distance_to(objective.position) <= objective.radius, 1)


## Takes the collected items (unless [member QKObjective.consume_on_turn_in] is off) and
## gives the rewards to [param bag], in one transaction. [param choice]: index in
## [member QKQuest.reward_choices], required when the quest has choices.
func turn_in(quest_id: StringName, bag: IKContainer, choice: int = -1) -> QKResult:
	var quest := book.get_quest(quest_id)
	if quest == null:
		return QKResult.failure(QKResult.Code.UNKNOWN_QUEST, "no quest '%s'" % quest_id)
	if bag == null:
		return QKResult.failure(QKResult.Code.INVALID_ARGUMENT, "turn_in: no bag")
	var state := get_state(quest_id)
	if state != State.ACTIVE and state != State.READY:
		return QKResult.failure(QKResult.Code.WRONG_STATE, "%s is %s" % [quest_id, State.keys()[state]])
	if not are_objectives_done(quest_id):
		return QKResult.failure(QKResult.Code.NOT_READY, "%s: objectives not done" % quest_id)
	if not quest.reward_choices.is_empty() and (choice < 0 or choice >= quest.reward_choices.size() or quest.reward_choices[choice] == null):
		return QKResult.failure(QKResult.Code.CHOICE_REQUIRED, "%s: choose a reward (0-%d)" % [quest_id, quest.reward_choices.size() - 1])
	return _complete(quest, bag, choice)


## Drops an active quest: it becomes available again and its progress is lost.
func abandon(quest_id: StringName) -> QKResult:
	var state := get_state(quest_id)
	if state != State.ACTIVE and state != State.READY:
		return QKResult.failure(QKResult.Code.WRONG_STATE, "%s is not in progress" % quest_id)
	_states.erase(quest_id)
	_events.erase(quest_id)
	_time_left.erase(quest_id)
	_untrack(quest_id)
	state_changed.emit(book.get_quest(quest_id), get_state(quest_id))
	changed.emit()
	return QKResult.success(quest_id)


## Marks an active quest as failed (time out, an NPC died...). A repeatable quest can be
## taken again after its cooldown.
func fail(quest_id: StringName) -> QKResult:
	var state := get_state(quest_id)
	if state != State.ACTIVE and state != State.READY:
		return QKResult.failure(QKResult.Code.WRONG_STATE, "%s is not in progress" % quest_id)
	_states[quest_id] = State.FAILED
	_time_left.erase(quest_id)
	_finished_at[quest_id] = _now()
	var quest := book.get_quest(quest_id)
	if quest != null and quest.repeatable:
		_cooling[quest_id] = true
	_untrack(quest_id)
	state_changed.emit(quest, State.FAILED)
	changed.emit()
	return QKResult.success(quest_id)


## Counts the time limits down by [param seconds] of play ([method _process] does it each
## frame; call it yourself for a turn-based clock). Quests out of time fail.
func advance_time(seconds: float, notify: bool = true) -> void:
	var expired: Array[StringName] = []
	for quest_id: StringName in _time_left.keys():
		var state: Variant = _states.get(quest_id)
		if state != State.ACTIVE and state != State.READY:
			_time_left.erase(quest_id)
			continue
		_time_left[quest_id] -= seconds
		if _time_left[quest_id] <= 0.0:
			expired.append(quest_id)
	for quest_id in expired:
		_time_left.erase(quest_id)
		fail(quest_id)
		quest_expired.emit(book.get_quest(quest_id))
	if notify:
		timers_changed.emit()


## Announces the repeatable quests whose cooldown is over ([signal state_changed]).
## Runs once per second by itself.
func check_cooldowns() -> void:
	var back := false
	for quest_id: StringName in _cooling.keys():
		if get_cooldown_left(quest_id) <= 0.0:
			_cooling.erase(quest_id)
			back = true
			state_changed.emit(book.get_quest(quest_id), get_state(quest_id))
	if back:
		changed.emit()


func set_tracked(quest_id: StringName, tracked: bool) -> bool:
	if not tracked:
		var had := _tracked.has(quest_id)
		_untrack(quest_id)
		return had
	var state := get_state(quest_id)
	if _tracked.has(quest_id) or _tracked.size() >= max_tracked or (state != State.ACTIVE and state != State.READY):
		return false
	_tracked.append(quest_id)
	tracking_changed.emit()
	changed.emit()
	return true


# --- Saving ----------------------------------------------------------------------

func to_data() -> Dictionary:
	var states := {}
	for quest_id in _states:
		states[String(quest_id)] = State.keys()[_states[quest_id]].to_lower()
	var events := {}
	for quest_id in _events:
		var counts := {}
		for objective_id in _events[quest_id]:
			counts[String(objective_id)] = _events[quest_id][objective_id]
		events[String(quest_id)] = counts
	var tracked := []
	for quest_id in _tracked:
		tracked.append(String(quest_id))
	return {"version": DATA_VERSION, "states": states, "events": events, "tracked": tracked,
		"timers": _string_keys(_time_left), "finished_at": _string_keys(_finished_at),
		"completions": _string_keys(_completions), "branches": _string_keys(_branches, true)}


## Restores [method to_data] (version 1 saves too). Quests removed from the book are ignored.
func load_data(data: Dictionary) -> bool:
	if typeof(data.get("states")) != TYPE_DICTIONARY:
		return false
	var states := {}
	for raw_id: Variant in data.states:
		var quest_id := StringName(str(raw_id))
		var index := State.keys().find(str(data.states[raw_id]).to_upper())
		if book.get_quest(quest_id) != null and index > State.AVAILABLE:
			states[quest_id] = index
	var events := {}
	if typeof(data.get("events")) == TYPE_DICTIONARY:
		for raw_id: Variant in data.events:
			if typeof(data.events[raw_id]) != TYPE_DICTIONARY:
				continue
			var counts := {}
			for objective_id: Variant in data.events[raw_id]:
				counts[StringName(str(objective_id))] = maxi(0, int(data.events[raw_id][objective_id]))
			events[StringName(str(raw_id))] = counts
	_states = states
	_events = events
	_time_left.clear()
	var timers := _read_numbers(data.get("timers"))
	for quest_id: StringName in timers:
		if states.get(quest_id) == State.ACTIVE or states.get(quest_id) == State.READY:
			_time_left[quest_id] = maxf(0.001, float(timers[quest_id]))
	_finished_at.clear()
	var finished := _read_numbers(data.get("finished_at"))
	for quest_id: StringName in finished:
		_finished_at[quest_id] = float(finished[quest_id])
	_completions.clear()
	var completions := _read_numbers(data.get("completions"))
	for quest_id: StringName in completions:
		_completions[quest_id] = maxi(0, int(completions[quest_id]))
	_branches.clear()
	if typeof(data.get("branches")) == TYPE_DICTIONARY:
		for raw_id: Variant in data.branches:
			_branches[StringName(str(raw_id))] = StringName(str(data.branches[raw_id]))
	_cooling.clear()
	for quest_id: StringName in _states:
		if book.get_quest(quest_id).repeatable and get_cooldown_left(quest_id) > 0.0:
			_cooling[quest_id] = true
	_tracked.clear()
	for raw: Variant in data.get("tracked", []):
		var quest_id := StringName(str(raw))
		if (get_state(quest_id) == State.ACTIVE or get_state(quest_id) == State.READY) and _tracked.size() < max_tracked:
			_tracked.append(quest_id)
	_refresh_ready()
	tracking_changed.emit()
	changed.emit()
	return true


# --- Internals -------------------------------------------------------------------

func _complete(quest: QKQuest, bag: IKContainer, choice: int = -1) -> QKResult:
	var transaction := IKTransaction.new()
	var branch := _done_branch(quest)
	var taken := {}
	for objective in quest.objectives:
		if objective != null and objective.kind == QKObjective.Kind.COLLECT and objective.consume_on_turn_in and not objective.optional \
				and (objective.branch.is_empty() or objective.branch == branch):
			taken[objective.target] = taken.get(objective.target, 0) + objective.amount
	var given: Array[QKReward] = []
	for reward in quest.extra_rewards:
		if reward != null and reward.amount != 0:
			given.append(reward)
	if choice >= 0 and choice < quest.reward_choices.size() and quest.reward_choices[choice] != null:
		given.append(quest.reward_choices[choice])
	var items := {}
	for item_id in quest.rewards:
		items[item_id] = quest.rewards[item_id]
	for reward in given:
		if reward.is_item() and reward.amount > 0:
			items[reward.id] = items.get(reward.id, 0) + reward.amount
	if not taken.is_empty():
		var source := _container if _container != null else bag
		if not source.has_all(taken):
			return QKResult.failure(QKResult.Code.MISSING_ITEMS, "%s: items missing" % quest.id)
		transaction.consume(source, taken)
	for item_id in items:
		transaction.add(bag, item_id, items[item_id])
	if not taken.is_empty() or not items.is_empty():
		_completing = true
		var committed := transaction.commit()
		_completing = false
		if not committed.ok:
			var code := QKResult.Code.NO_ROOM if committed.code in [IKResult.Code.CONTAINER_FULL, IKResult.Code.RULE_REJECTED, IKResult.Code.SLOT_FULL] else QKResult.Code.INVENTORY_ERROR
			return QKResult.failure(code, committed.message, committed)
	_states[quest.id] = State.COMPLETED
	_events.erase(quest.id)
	_time_left.erase(quest.id)
	_finished_at[quest.id] = _now()
	_completions[quest.id] = _completions.get(quest.id, 0) + 1
	if not branch.is_empty():
		_branches[quest.id] = branch
	if quest.repeatable:
		_cooling[quest.id] = true
	_untrack(quest.id)
	for reward in given:
		if not reward.is_item():
			reward_granted.emit(reward.kind, reward.id, reward.amount)
			if reward_callback.is_valid():
				reward_callback.call(reward.kind, reward.id, reward.amount)
	state_changed.emit(quest, State.COMPLETED)
	quest_completed.emit(quest)
	for other in book.quests:
		if other != null and other != quest and (other.prerequisites.has(quest.id) or other.requires_branch.has(quest.id)) \
				and get_state(other.id) == State.AVAILABLE:
			state_changed.emit(other, State.AVAILABLE)
	changed.emit()
	return QKResult.success(quest.id)


## ACTIVE <-> READY follows the objectives; auto-complete quests finish on their own.
func _refresh_ready() -> void:
	for quest_id in _states.keys():
		var state: State = _states[quest_id]
		if state != State.ACTIVE and state != State.READY:
			continue
		var quest := book.get_quest(quest_id)
		var done := are_objectives_done(quest_id)
		if done and quest.auto_complete and quest.reward_choices.is_empty() and _container != null:
			_complete(quest, _container)
			continue
		var wanted := State.READY if done else State.ACTIVE
		if wanted != state:
			_states[quest_id] = wanted
			state_changed.emit(quest, wanted)


## Adds [param amount] to the EVENT / REACH objectives of the quests in progress that [param matches].
func _count(matches: Callable, amount: int) -> void:
	var touched := false
	for quest_id: StringName in _states.keys():
		if _states.get(quest_id) != State.ACTIVE and _states.get(quest_id) != State.READY:
			continue
		var quest := book.get_quest(quest_id)
		if quest == null:
			continue
		for objective in quest.objectives:
			if objective == null or objective.kind == QKObjective.Kind.COLLECT or not matches.call(objective):
				continue
			var counts: Dictionary = _events.get_or_add(quest_id, {})
			var before: int = counts.get(objective.id, 0)
			if before >= objective.amount:
				continue
			counts[objective.id] = mini(objective.amount, before + amount)
			touched = true
			objective_progressed.emit(quest, objective, counts[objective.id])
	if touched:
		_refresh_ready()
		changed.emit()


## The first branch whose objectives are all done (empty if none, or no branches).
func _done_branch(quest: QKQuest) -> StringName:
	for branch in quest.get_branches():
		var needed := 0
		var done := 0
		var any_done := false
		for objective in quest.objectives:
			if objective == null or objective.branch != branch:
				continue
			var finished := get_progress(quest.id, objective.id) >= objective.amount
			any_done = any_done or finished
			if not objective.optional:
				needed += 1
				done += 1 if finished else 0
		if (needed > 0 and done == needed) or (needed == 0 and any_done):
			return branch
	return &""


func _objective_position(objective: QKObjective) -> Variant:
	if not objective.target.is_empty() and _zones.has(objective.target):
		var node: Object = _zones[objective.target].get_ref()
		if node is Node2D:
			return Vector3(node.global_position.x, node.global_position.y, 0)
		if node is Node3D:
			return node.global_position
	if objective.has_position:
		return objective.position
	return null


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_unix_time_from_system()


## Clock time of the first daily reset after [param time].
func _next_reset(time: float) -> float:
	var shift := time_zone_minutes * 60.0 - daily_reset_hour * 3600.0
	return (floorf((time + shift) / 86400.0) + 1.0) * 86400.0 - shift


func _string_keys(values: Dictionary, as_strings: bool = false) -> Dictionary:
	var out := {}
	for key: Variant in values:
		out[String(key)] = String(values[key]) if as_strings else values[key]
	return out


func _read_numbers(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) == TYPE_DICTIONARY:
		for key: Variant in raw:
			if typeof(raw[key]) in [TYPE_INT, TYPE_FLOAT] and book.get_quest(StringName(str(key))) != null:
				out[StringName(str(key))] = raw[key]
	return out


func _untrack(quest_id: StringName) -> void:
	if _tracked.has(quest_id):
		_tracked.erase(quest_id)
		tracking_changed.emit()


func _on_container_changed() -> void:
	if _completing:
		return
	_refresh_ready()
	changed.emit()
