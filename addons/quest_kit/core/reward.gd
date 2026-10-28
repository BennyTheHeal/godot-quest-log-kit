@tool
class_name QKReward
extends Resource
## One reward that is not (only) an item stack: experience, a currency, reputation with a
## faction, or anything your game invents ("unlock_recipe", "title"...).
##
## Items ([constant ITEM]) go into the bag in the turn-in transaction, like
## [member QKQuest.rewards]. Every other kind is handed to your game through
## [signal QKQuestLog.reward_granted] (and [member QKQuestLog.reward_callback]):
## the kit does not store XP or money, your game does.

const ITEM := &"item"
const XP := &"xp"
const CURRENCY := &"currency"
const REPUTATION := &"reputation"

## &"item", &"xp", &"currency", &"reputation" or your own kind.
@export var kind: StringName = XP
## Item id (item), currency id (&"gold", &"guild_marks"), faction id (reputation) or free id. Empty for XP.
@export var id: StringName
@export var amount: int = 1
## Text shown in the journal. "%d" is replaced by the amount. Empty = a default per kind.
@export var text: String = ""


static func make(p_kind: StringName, p_id: StringName, p_amount: int, p_text: String = "") -> QKReward:
	var reward := QKReward.new()
	reward.kind = p_kind
	reward.id = p_id
	reward.amount = p_amount
	reward.text = p_text
	return reward


static func item(item_id: StringName, p_amount: int = 1) -> QKReward:
	return make(ITEM, item_id, p_amount)


static func xp(p_amount: int, skill: StringName = &"") -> QKReward:
	return make(XP, skill, p_amount)


static func currency(currency_id: StringName, p_amount: int) -> QKReward:
	return make(CURRENCY, currency_id, p_amount)


static func reputation(faction_id: StringName, p_amount: int) -> QKReward:
	return make(REPUTATION, faction_id, p_amount)


func is_item() -> bool:
	return kind == ITEM


## Player text: "50 XP", "+5 reputation: Village", "12 Guild Marks". Item names come
## from the item database, see [method QKJournalWindow].
func get_text(database: IKItemDatabase = null) -> String:
	var shown := QKText.t(text)
	if shown.is_empty():
		match kind:
			ITEM:
				var definition := database.get_item(id) if database != null else null
				return "%d × %s" % [amount, IKText.item_name(definition) if definition != null else String(id).capitalize()]
			XP:
				shown = QKText.t("%d XP")
			REPUTATION:
				return QKText.t("%+d reputation: %s") % [amount, QKText.t(String(id).capitalize())]
			_:
				return "%d %s" % [amount, QKText.t(String(id if not id.is_empty() else kind).capitalize())]
	return shown % amount if shown.contains("%d") else shown
