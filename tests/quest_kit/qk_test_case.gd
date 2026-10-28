extends RefCounted
## Base class for Quest Log Kit tests: assertions and shared fixtures.

var _failures := PackedStringArray()
var _nodes: Array[Node] = []


func get_failures() -> PackedStringArray:
	return _failures


func get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds [param node] to the scene root; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	get_tree().root.add_child(node)
	_nodes.append(node)
	return node


func wait_frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## Called by the runner after each test.
func cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	await get_tree().process_frame


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%sexpected <%s> but got <%s>" % [message + ": " if message else "", expected, actual])


func assert_ok(result: IKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])


func assert_code(result: IKResult, code: IKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", IKResult.Code.keys()[code], result])


## Disconnects every signal of [param objects]. Call at the end of tests whose
## lambdas capture the emitter, otherwise the reference cycle leaks.
func disconnect_all(objects: Array) -> void:
	for object: Object in objects:
		for info in object.get_signal_list():
			for connection in object.get_signal_connection_list(info.name):
				object.disconnect(info.name, connection.callable)




# --- Fixtures ----------------------------------------------------------------

func assert_quest(result: QKResult, code: QKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", QKResult.Code.keys()[code], result])


func make_item(id: StringName, max_stack: int = 20) -> IKItemDefinition:
	var item := IKItemDefinition.new()
	item.id = id
	item.display_name = String(id).capitalize()
	item.max_stack = max_stack
	return item


## wood, herb, gold (stack 999), sword (stack 1).
func make_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	db.add_item(make_item(&"wood"))
	db.add_item(make_item(&"herb"))
	db.add_item(make_item(&"gold", 999))
	db.add_item(make_item(&"sword", 1))
	return db


## firewood: collect 5 wood -> 10 gold. wolves: kill 3 wolves (event) -> sword, auto-complete.
## alchemist: collect 2 herbs + talk to Mira, requires firewood -> 20 gold.
func make_book() -> QKQuestBook:
	var book := QKQuestBook.new()
	book.add_quest(QKQuest.make(&"firewood", "Firewood", [QKObjective.collect(&"wood", &"wood", 5)], {&"gold": 10}))
	var wolves := QKQuest.make(&"wolves", "Wolves", [QKObjective.event(&"kills", &"kill_wolf", 3)], {&"sword": 1})
	wolves.auto_complete = true
	book.add_quest(wolves)
	var alchemist := QKQuest.make(&"alchemist", "Alchemist", [QKObjective.collect(&"herbs", &"herb", 2), QKObjective.event(&"talk", &"talk_mira")], {&"gold": 20})
	alchemist.prerequisites = [&"firewood"]
	book.add_quest(alchemist)
	return book


func make_log(db: IKItemDatabase, bag: IKContainer) -> QKQuestLog:
	var log := QKQuestLog.new()
	log.book = make_book()
	log.database = db
	add_to_tree(log)
	log.watch(bag)
	return log


func make_bag(db: IKItemDatabase, items: Dictionary = {}, slots: int = 6) -> IKContainer:
	var bag := IKContainer.new(&"bag", slots, db)
	for item_id: StringName in items:
		bag.add(item_id, items[item_id])
	return bag
