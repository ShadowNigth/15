class_name GameplayInputGate
extends RefCounted
## Original modal ownership: weak owners, no autoload or gameplay time pause.
static var _owners: Dictionary = {}
static var _restore_mode: int = Input.MOUSE_MODE_CAPTURED
static var generation: int = 0

static func acquire(owner: Node) -> void:
	_prune()
	if _owners.has(owner.get_instance_id()):
		return
	if _owners.is_empty():
		_restore_mode = Input.mouse_mode
	_owners[owner.get_instance_id()] = weakref(owner)
	generation += 1
	if not owner.tree_exiting.is_connected(release.bind(owner)):
		owner.tree_exiting.connect(release.bind(owner), CONNECT_ONE_SHOT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func release(owner: Node, capture_mouse: bool = true) -> void:
	if _owners.erase(owner.get_instance_id()):
		generation += 1
	_prune()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if not _owners.is_empty() or not capture_mouse else _restore_mode

static func _prune() -> void:
	for key in _owners.keys():
		if not is_instance_valid((_owners[key] as WeakRef).get_ref()):
			_owners.erase(key)
			generation += 1

static func blocked() -> bool:
	_prune()
	return not _owners.is_empty()
