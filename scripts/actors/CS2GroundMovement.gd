class_name CS2GroundMovement
extends RefCounted
## Experimental Source-style ground movement approximation, NOT Valve code/Rubikon.
## Units use this project's 1/32 map scale, not Source 2 model inches.
## Opposite input brakes through ordinary acceleration; no instant-stop cheat.
const ACCELERATION: float = 5.5
const FRICTION: float = 5.2
const STOP_SPEED: float = 80.0 / 32.0
const MAX_SLICE: float = 1.0 / 128.0

static func step(current: Vector3, wish: Vector3, max_speed: float, delta: float) -> Vector3:
	if delta <= 0.0:
		return current
	var horizontal := Vector2(current.x, current.z)
	var input := Vector2(wish.x, wish.z).limit_length(1.0)
	var wish_speed := maxf(0.0, max_speed) * input.length()
	var direction := input.normalized()
	# Integrate forces in small slices to reduce physics-rate sensitivity.
	# This does not timestamp input or substep Godot collisions (not "subtick").
	var remaining := delta
	while remaining > 0.000001:
		var dt := minf(remaining, MAX_SLICE)
		remaining -= dt
		var speed := horizontal.length()
		if speed > 0.0:
			var after := maxf(0.0, speed - maxf(speed, STOP_SPEED) * FRICTION * dt)
			horizontal *= after / speed
		if wish_speed > 0.0:
			var missing := wish_speed - horizontal.dot(direction)
			if missing > 0.0:
				horizontal += direction * minf(missing, ACCELERATION * wish_speed * dt)
	return Vector3(horizontal.x, current.y, horizontal.y)
