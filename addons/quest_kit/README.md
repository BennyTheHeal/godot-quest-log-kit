# Quest Log Kit for Godot 4

Quests for your RPG or adventure game: **objectives** (collect items, game events), **prerequisites and chains**, **turn-in with rewards**, an **on-screen tracker** and a **ready-to-use journal** that works with the mouse, the keyboard and a gamepad.

**Pay what you want, from $0.** Code under MIT. A tip on itch.io keeps new kits coming. Official page, downloads and playable web demo: https://banc-essai.site-testeurs.workers.dev/quest-kit/
More kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

- Built on **Inventory Kit** (included in the download): turning in takes the collected items and gives the rewards in one atomic transaction. If the rewards do not fit, nothing is taken.
- **Objectives**: COLLECT (items held in the bag, followed live: drop them and the objective goes back down), EVENT (anything your game reports: `report(&"kill_wolf")`) or REACH (go to an Area2D / Area3D or within a radius of a position), optional objectives.
- **States**: locked, available, in progress, ready to turn in, completed, failed. Prerequisites unlock quest chains; auto-complete quests finish on their own.
- **Rewards**: items, XP, currencies, reputation or your own kinds (`reward_granted(kind, id, amount)`), and "pick one of these" reward choices.
- **Repeatable, daily and timed quests**, **branches** (an alternative objective that leads to a different follow-up), and a **target indicator** for your quest marker or compass.
- **Dialogue bridge** for Dialogue Manager and Dialogic, with no dependency, and C# examples.
- **Tracker** (`QKQuestTracker`): the tracked quests and their objectives on screen, updated live.
- **Journal** (`QKJournalWindow`): In progress / Available / Done tabs, details with objectives and rewards, Accept, Turn in, Abandon, Track. Styled by your Theme (Inventory Kit themes in 4 art styles).
- Save / load (`to_data()` / `load_data()`, 1.0 saves still load), every player text translatable (`translations/quest_kit.csv`), 32 automated tests.

## Install

1. Copy `addons/inventory_kit/` and `addons/quest_kit/` into your project's `addons/` folder (skip Inventory Kit if you already have it).
2. Open `demo/quest/quest_demo.tscn`: a village with ten quests, a mini-map with a compass and an XP / reputation panel.

## Five-minute setup

```gdscript
var firewood := QKQuest.make(&"firewood", "Firewood for Winter",
	[QKObjective.collect(&"logs", &"oak_log", 8, "Bring %d oak logs")], {&"gold_coins": 25})
var wolves := QKQuest.make(&"wolves", "Wolf Trouble",
	[QKObjective.event(&"kills", &"kill_wolf", 3, "Hunt %d wolves")], {&"iron_helmet": 1})
wolves.prerequisites = [&"firewood"]

var book := QKQuestBook.new()          # save it as a .tres
book.add_quest(firewood)
book.add_quest(wolves)

var quest_log := QKQuestLog.new()
quest_log.book = book
add_child(quest_log)
quest_log.watch(bag.container)         # COLLECT objectives count this container

quest_log.accept(&"firewood")
quest_log.report(&"kill_wolf")         # call it from your game when a wolf dies
var result := quest_log.turn_in(&"firewood", bag.container)
if not result.ok:
	status.text = QKText.result_message(result)
```

UI:

```gdscript
var tracker := QKQuestTracker.new()    # in your HUD
tracker.quest_log = quest_log

var journal := QKJournalWindow.new()
journal.quest_log = quest_log
journal.bag = bag.container
journal.theme = preload("res://addons/inventory_kit/art/painted/painted_theme.tres")
journal.close_requested.connect(journal.hide)
```

NPCs give and take quests themselves? Set `journal.allow_actions = false`: the journal only shows and tracks.

## Rewards: XP, money, reputation, choices

Items go into the bag in the turn-in transaction. Everything else is announced: the kit does not store XP or money, your game does.

```gdscript
quest.extra_rewards = [QKReward.xp(50), QKReward.currency(&"gold", 20), QKReward.reputation(&"village", 5),
	QKReward.make(&"unlock_recipe", &"bread", 1)]          # your own kind
quest_log.reward_granted.connect(func(kind: StringName, id: StringName, amount: int) -> void:
	match kind:
		QKReward.XP: player.add_xp(amount)
		QKReward.CURRENCY: wallet.add(id, amount)
		QKReward.REPUTATION: factions.change(id, amount))

# The player picks one (the journal shows buttons; from code, pass the index):
quest.reward_choices = [QKReward.item(&"iron_helmet"), QKReward.item(&"health_potion", 3), QKReward.xp(100)]
quest_log.turn_in(&"bounty", bag.container, 1)    # without a valid index: CHOICE_REQUIRED
```

`reward_granted` fires before `quest_completed`. Prefer a callback? `quest_log.reward_callback = func(kind, id, amount): ...`. A quest with reward choices never auto-completes.

## Repeatable, daily and timed quests

```gdscript
bounty.repeatable = true
bounty.cooldown = 600.0                  # real seconds before it is available again
herbs.repeatable = true
herbs.daily = true                       # back after the daily reset
quest_log.daily_reset_hour = 6           # local time, 06:00
courier.time_limit = 90.0                # seconds of play; fails at 0 (signal quest_expired)
```

- `get_time_left(id)` (-1 if no limit), `get_cooldown_left(id)`, `times_completed(id)`, `has_completed(id)`. Accepting a quest that is cooling down returns `ON_COOLDOWN`.
- Time limits count game time in `_process` (they stop while the tree is paused) and are saved; turn-based game? Turn off processing on the log and call `quest_log.advance_time(seconds)` yourself.
- Cooldowns and dailies use real time: `Time.get_unix_time_from_system()`. Your game has its own calendar? `quest_log.clock = func() -> float: return calendar.seconds`.
- `timers_changed` fires once per second while a timer runs; the tracker and the journal already listen to it.
- A repeatable quest still counts as completed for prerequisites while it is taken again.

## Branches

Objectives that share a `branch` form one path. The quest needs its common objectives (no branch) plus all the objectives of ONE path; the first path done is the one taken. A follow-up can require a path:

```gdscript
var camp := QKQuest.make(&"camp", "The Bandit Camp", [
	QKObjective.event(&"find", &"find_camp"),                    # common to both paths
	QKObjective.event(&"fight", &"kill_bandit", 3, "Beat %d bandits"),
	QKObjective.event(&"talk", &"parley", 1, "Talk them into leaving")])
camp.objectives[1].branch = &"fight"
camp.objectives[2].branch = &"talk"
chief.requires_branch = {&"camp": &"fight"}     # only after fighting
truce.requires_branch = {&"camp": &"talk"}      # only after talking
quest_log.get_branch(&"camp")                   # &"fight" or &"talk"
```

Items of the path not taken are not consumed. `validate()` reports unknown branches.

## Go to a place, quest markers and compasses

```gdscript
# A zone: put a QKQuestZone under any Area2D / Area3D (inspector: quest_log, zone_id = "mine").
# The player is any body in the "player" group (player_group).
QKObjective.reach(&"reach", &"mine", "Reach the old mine")
# Or a position and a radius (Vector2 or Vector3), checked when you report the player position:
QKObjective.reach_position(&"well", Vector2(640, 320), 48.0, "Drink at the well")
quest_log.update_position(player.global_position)   # in _physics_process, or when it moves
quest_log.reach(&"mine")                             # from any trigger of yours
```

The target for your marker or compass: the first unfinished objective with a place (a registered zone, or `has_position` on any objective kind, e.g. the NPC to talk to), tracked quests first.

```gdscript
func _process(_delta: float) -> void:
	var target := quest_log.get_target()             # or get_target(&"mine")
	marker.visible = not target.is_empty()
	if marker.visible:
		var to := Vector2(target.position.x, target.position.y) - player.global_position
		compass_arrow.rotation = to.angle()
		distance_label.text = "%d m" % to.length()
```

Keys: `quest_id`, `objective_id`, `position` (Vector3; in 2D z = 0), `radius`, `text`. A zone node registered with `register_zone()` (QKQuestZone does it) is followed live. The demo's mini-map shows it working.

## Dialogue Manager and Dialogic

`integrations/dialogue_bridge.gd` (`QKDialogueBridge`) lets dialogue files accept, advance and complete quests. It names no class of either addon: with neither installed nothing breaks, and nothing else in the kit needs it.

1. Project Settings > Globals > Autoload: add `res://addons/quest_kit/integrations/dialogue_bridge.gd` as `Quests`.
2. Once your log exists: `Quests.quest_log = $QuestLog` (rewards go to the watched container, or set `Quests.bag`).

Dialogue Manager (Nathan Hoad): mutations and conditions call the autoload.

```
~ mira
if Quests.is_ready("remedy")
	Mira: You found the herbs! Thank you.
	do Quests.complete("remedy")
elif Quests.is_available("remedy")
	Mira: Could you gather five herbs for me?
	- Of course.
		do Quests.accept("remedy")
	- Not now.
do Quests.advance("talk_mira")
```

Dialogic 2: a Signal event whose argument starts with `quest` is run by the bridge; the Call event can also call the autoload directly.

```
[signal arg="quest accept remedy"]
[signal arg="quest advance talk_mira"]
[signal arg="quest complete bounty 1"]
do Quests.complete("remedy")
```

Bridge methods: `accept(id)`, `advance(event, amount = 1)`, `reach(zone)`, `complete(id, choice = -1)`, `fail(id)`, `abandon(id)`; conditions `state(id)` ("locked", "available", "active", "ready", "completed", "failed"), `is_available`, `is_active`, `is_ready`, `is_completed`, `is_failed`, `progress(id, objective)`, `branch(id)`; text commands `run("accept remedy")`. Refusals emit `refused(result, text)` so you can show why. Change the prefix with `dialogic_prefix`.

## Using from C#

The kit is GDScript; from C#, hold the nodes as `GodotObject` / `Node` and use `Call`, `Get` and signals (Godot 4 .NET).

```csharp
using Godot;

public partial class QuestGiver : Node
{
    [Export] public Node QuestLog;          // the QKQuestLog node
    [Export] public Node Bag;               // the IKInventory node of the player

    public override void _Ready()
    {
        QuestLog.Connect("quest_completed", Callable.From<Resource>(quest =>
            GD.Print("Completed: ", quest.Call("get_title"))));
        QuestLog.Connect("reward_granted", Callable.From<StringName, StringName, int>((kind, id, amount) =>
        {
            if (kind.ToString() == "xp") GD.Print("+", amount, " XP");   // your stats here
        }));
    }

    public void Talk()
    {
        var container = (GodotObject)Bag.Get("container");            // IKContainer
        var state = QuestLog.Call("get_state", "remedy").AsInt32();   // QKQuestLog.State: 3 = READY
        GodotObject result = state == 3
            ? QuestLog.Call("turn_in", "remedy", container).AsGodotObject()
            : QuestLog.Call("accept", "remedy").AsGodotObject();
        if (!result.Get("ok").AsBool())
            GD.Print(GD.Load<GDScript>("res://addons/quest_kit/core/text.gd").Call("result_message", result));
        QuestLog.Call("report", "talk_mira", 1);
        QuestLog.Call("update_position", GetNode<Node2D>("../Player").GlobalPosition);
        var target = QuestLog.Call("get_target").AsGodotDictionary();
        if (target.Count > 0) GD.Print("Go to ", target["position"]);
    }
}
```

States: 0 LOCKED, 1 AVAILABLE, 2 ACTIVE, 3 READY, 4 COMPLETED, 5 FAILED. Building quests in C#: `var reward = (Resource)GD.Load<GDScript>("res://addons/quest_kit/core/reward.gd").Call("xp", 50);`, or make them as `.tres` in the editor (easiest). Saves: `QuestLog.Call("to_data").AsGodotDictionary()` and `QuestLog.Call("load_data", data)`.

## Classes

| Class | Role |
|---|---|
| `QKQuest`, `QKObjective`, `QKQuestBook` | Quests as resources: objectives (collect, event, reach), branches, rewards, prerequisites, repeat and time limits, auto-complete, validation |
| `QKReward` | XP, currency, reputation, item or custom reward |
| `QKQuestLog` | States, progress, `accept()`, `report()`, `reach()`, `update_position()`, `turn_in()`, `abandon()`, `fail()`, timers, cooldowns, `get_target()`, tracking, save; signals `state_changed`, `objective_progressed`, `quest_completed`, `reward_granted`, `quest_expired`, `timers_changed`, `changed` |
| `QKQuestZone` | Under an Area2D / Area3D: completes REACH objectives, registers the zone as a target |
| `QKDialogueBridge` | Calls from Dialogue Manager / Dialogic (optional, no dependency) |
| `QKResult`, `QKText` | Outcome codes (`LOCKED`, `NOT_READY`, `NO_ROOM`, `MISSING_ITEMS`, `CHOICE_REQUIRED`, `ON_COOLDOWN`...) and player texts |
| `QKQuestTracker`, `QKJournalWindow` | The HUD tracker and the journal |

Journal controls: click or Enter / A on a quest, the arrows / d-pad move, Q / E or LB / RB switch tabs, Escape / B emits `close_requested`. Rebind the tabs with `qk_previous_tab` / `qk_next_tab` in your Input Map.

## Running the tests

```bash
godot --headless --path <project> --import
godot --headless --path <project> -s res://tests/quest_kit/run_tests.gd
```

## Licenses

- Source code: MIT (`LICENSE.txt`).
- The item art in `addons/inventory_kit/art/` is covered by Inventory Kit's `LICENSE_ART.txt`: free to use in your games, please do not re-upload it; link to the official page instead.
- Found a bug or want a feature? Tell us: https://banc-essai.site-testeurs.workers.dev/
