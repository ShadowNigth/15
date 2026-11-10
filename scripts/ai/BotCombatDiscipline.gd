class_name BotCombatDiscipline
extends RefCounted
## Original policy: actual-shot burst accounting, independent of recoil decay.
## No enemy-position access; caller supplies already perceived range.
static func burst_limit(distance: float, sniper: bool, slot: int) -> int:
	if sniper or slot == 2:
		return 1
	if distance > 23.0:
		return 3
	if distance > 11.5:
		return 5
	return 10

static func stable_enough(distance: float, speed: float, sniper: bool, slot: int) -> bool:
	if sniper:
		return speed < 0.9
	if slot == 1 and distance > 11.5:
		return speed < 1.35
	return true

static func advance_objective(distance: float, urgent: bool, has_route: bool, reloading: bool) -> bool:
	# Nearby threats still interrupt. Reload cover takes priority over exposed travel.
	return urgent and has_route and not reloading and distance > 16.0
