class_name CS2ExperimentalPhysics
extends RefCounted
## Tunable offline approximation. Not Valve Rubikon, subtick or articulated ragdolls.
const GRAVITY := 800.0 / 32.0
const JUMP_SPEED := 301.993 / 32.0
const AIR_ACCEL := 12.0
const AIR_WISH_CAP := 30.0 / 32.0
const GRENADE_GRAVITY := GRAVITY * 0.4
const OBJECT_GRAVITY := GRAVITY
const GRENADE_RESTITUTION := 0.45
const OBJECT_RESTITUTION := 0.25
const CORPSE_DRAG := 5.0

static func enabled() -> bool:
	return GameData.movement_profile == "cs2_experimental"

static func air_step(current: Vector3, wish: Vector3, speed: float, delta: float) -> Vector3:
	var input := Vector3(wish.x, 0, wish.z).limit_length(1.0)
	var direction := input.normalized()
	var wish_speed := maxf(0.0, speed) * input.length()
	var cap := minf(wish_speed, AIR_WISH_CAP)
	var remaining := maxf(0.0, delta)
	while remaining > 0.000001:
		var dt := minf(remaining, CS2GroundMovement.MAX_SLICE)
		remaining -= dt
		var missing := cap - current.dot(direction)
		if missing > 0:
			current += direction * minf(missing, AIR_ACCEL * wish_speed * dt)
	return current

static func impact(current: Vector3, normal: Vector3, restitution: float, friction: float = 0.2) -> Vector3:
	var n := normal.normalized()
	var inward := current.dot(n)
	if inward >= 0:
		return current
	var tangent := current - n * inward
	return tangent * (1.0 - clampf(friction, 0, 1)) - n * inward * clampf(restitution, 0, 1)
