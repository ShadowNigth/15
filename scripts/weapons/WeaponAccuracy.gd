class_name WeaponAccuracy
extends RefCounted
## Game-tuned bounded spread, independent of deterministic spray/recoil.
## Values are tangent-space cone radii, not Gaussian standard deviations.
static func cone(spec: Dictionary, speed_gs: float, grounded: bool, crouching: bool, scoped: bool, heat: float, alternate: bool = false) -> float:
	var base := float(spec.get("alt_spread", spec.get("spread_base", 0.01))) if alternate else float(spec.get("spread_base", 0.01))
	if bool(spec.get("sniper_scope", false)) and not scoped:
		base = maxf(base, float(spec.get("spread_unscoped", 0.06)))
	var limit := maxf(1.0, float(spec.get("max_speed", 250.0)))
	var movement := clampf((speed_gs / limit - 0.12) / 0.88, 0.0, 1.0)
	var moving := float(spec.get("spread_move", 0.07)) * movement * movement
	var bloom := minf(0.045, pow(clampf(heat - 1.0, 0.0, 20.0) / 20.0, 1.5) * 0.045)
	if int(spec.get("pellets", 1)) > 1:
		bloom *= 0.3  # Pellet cones retain their authored identity.
	var result := base + moving + bloom
	if not grounded:
		result += maxf(0.045, float(spec.get("spread_move", 0.07)))
	elif crouching:
		result *= 0.75
	return clampf(result, 0.0, 0.5)

static func sample_disk(rng: RandomNumberGenerator, radius: float) -> Vector2:
	# Average two uniform disks: centre-weighted, circular and strictly bounded.
	var result := Vector2.ZERO
	for index in 2:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf())
		result += Vector2(cos(angle), sin(angle)) * distance
	return result * (maxf(0, radius) * 0.5)
