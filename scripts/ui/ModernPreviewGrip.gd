class_name ModernPreviewGrip
extends Node
## Cosmetic-only support fit. Never instantiates a CSActor or changes gameplay RNG.
var rig: Skeleton3D
var animation: AnimationPlayer
var avatar := "sas"
var weapon := "m4a1"
var fitter := ClassicPoseFit.new()

static func fit_support(skeleton: Skeleton3D, fit: ClassicPoseFit, appearance: String, wid: String) -> void:
	if not ModernAgentPose.is_modern(skeleton) or int(GameData.weapons.get(wid, {}).get("slot", 0)) != 1:
		return
	var support: Array = ModernAgentPose.table(appearance, wid).get("support", [])
	if support.size() == 3:
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_R"))
		fit.fit_modern_support(skeleton, hand * Vector3(support[0], support[1], support[2]))

static func attach(model: Node3D, skeleton: Skeleton3D, player: AnimationPlayer, appearance: String, wid: String) -> void:
	var helper := ModernPreviewGrip.new()
	helper.rig = skeleton
	helper.animation = player
	helper.avatar = appearance
	helper.weapon = wid
	helper.process_priority = 100
	model.add_child(helper)

func _process(_delta: float) -> void:
	if not is_instance_valid(rig) or not is_instance_valid(animation) or not animation.active:
		return
	fitter.restore()
	# Re-evaluate sparse native channels before correcting them, not last frame's IK.
	if animation.is_playing():
		animation.advance(0)
	var current := String(animation.current_animation)
	if not any_action(current):
		fit_support(rig, fitter, avatar, weapon)

static func any_action(clip: String) -> bool:
	return "reload" in clip or "draw" in clip or "shoot" in clip or "swing" in clip
