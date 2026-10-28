# Changelog

All notable changes to Quest Log Kit are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-28

Everything from 1.0 works as before: same API (new parameters are optional), 1.0 saves load unchanged.

### Added
- Rewards beyond items: `QKReward` (XP, currency, reputation, your own kinds; items too) in `QKQuest.extra_rewards`. Non-item rewards reach the game through `QKQuestLog.reward_granted(kind, id, amount)` and the optional `reward_callback`.
- Reward choice: `QKQuest.reward_choices`, `turn_in(quest_id, bag, choice)`, new code `CHOICE_REQUIRED`; the journal shows the choices as buttons.
- Repeatable quests (`repeatable`, `cooldown` in real seconds, `daily` with `QKQuestLog.daily_reset_hour`), `times_completed()`, `has_completed()`, `get_cooldown_left()`, `check_cooldowns()`, injectable `clock`; new code `ON_COOLDOWN`.
- Timed quests (`time_limit`, in play time, saved): `get_time_left()`, `advance_time()`, signals `quest_expired` and `timers_changed`; tracker and journal show the time left.
- Branches: `QKObjective.branch` (alternative paths), `QKQuest.requires_branch` (follow-up for one path only), `get_branch()`.
- Go-to objectives: `QKObjective.Kind.REACH`, `QKObjective.reach()` / `reach_position()`, `QKQuestLog.reach()`, `update_position()`, `register_zone()`; `QKQuestZone` node for Area2D / Area3D.
- Target indicator: `QKQuestLog.get_target()` (quest, objective, position, radius, text) for markers and compasses; `has_position` on any objective.
- `QKDialogueBridge`: calls the log from Dialogue Manager mutations / conditions and Dialogic 2 signal events, with no dependency on either.
- README: dialogue integration and "Using from C#" sections.
- Demo: ten quests (daily, timed, branch with two follow-ups, reward choices), XP / currency / reputation panel, mini-map with a compass, "Next day" button; 32 automated tests.

### Changed
- Save data version 2 (adds timers, completion times and counts, branches). Version 1 data loads as before.

## [1.0.0] - 2026-10-26

### Added
- `QKQuest`, `QKObjective`, `QKQuestBook`: quests as resources (collect and event objectives, optional objectives, rewards, prerequisites, auto-complete) with validation.
- `QKQuestLog`: states (locked, available, in progress, ready, completed, failed), live progress, events, turn-in in one Inventory Kit transaction, abandon, fail, tracking, save / load.
- `QKQuestTracker` (HUD) and `QKJournalWindow` (tabs, details, actions, mouse, keyboard and gamepad).
- Village demo with five quests in the four Inventory Kit art styles; 15 automated tests; translation template.
