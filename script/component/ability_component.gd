class_name AbilityComponent
extends Node

var _owner: Card
var _native_abilities: Array[Ability] = []
var _granted_abilities: Array[Ability] = []
var _silenced_ability_ids: Array[String] = []
## 儲存 Ability.Tag 的整數值
var _silenced_tags: Array[int] = []


func setup(owner: Card, native_abilities: Array[Ability] = []) -> void:
	_owner = owner
	_native_abilities = native_abilities.duplicate()
	_connect_owner_signals()
	EventBus.piece_moved.connect(_on_piece_moved)


func _exit_tree() -> void:
	if EventBus.piece_moved.is_connected(_on_piece_moved):
		EventBus.piece_moved.disconnect(_on_piece_moved)


func register_native(abilities: Array[Ability]) -> void:
	for ability: Ability in abilities:
		if ability and not _native_abilities.has(ability):
			_native_abilities.append(ability)


func grant_ability(ability: Ability) -> void:
	if ability == null:
		return
	_granted_abilities.append(ability)


func grant_ability_copy_from(source: Ability) -> void:
	if source == null:
		return
	var copy := source.duplicate(true) as Ability
	if copy:
		grant_ability(copy)


func get_native_abilities() -> Array[Ability]:
	return _native_abilities.duplicate()


func clear_granted_abilities() -> void:
	_granted_abilities.clear()


func silence_ability(ability_id: String) -> void:
	if not _silenced_ability_ids.has(ability_id):
		_silenced_ability_ids.append(ability_id)


func silence_tag(tag: Ability.Tag) -> void:
	var tag_int: int = tag
	if not _silenced_tags.has(tag_int):
		_silenced_tags.append(tag_int)


func clear_silence() -> void:
	_silenced_ability_ids.clear()
	_silenced_tags.clear()


func is_ability_active(ability: Ability) -> bool:
	if _silenced_ability_ids.has(ability.id):
		return false
	for tag: int in ability.tags:
		if _silenced_tags.has(tag):
			return false
	return true


func dispatch(trigger_type: GameTrigger.Type, target: Variant = null, extra: Dictionary = {}) -> void:
	if _owner == null:
		return
	var ctx := GameEvent.create(trigger_type, _owner, target, extra)
	for ability: Ability in _get_all_abilities():
		if not ability.matches_trigger(trigger_type):
			continue
		if not is_ability_active(ability):
			continue
		if not ability.can_run(ctx):
			continue
		ability.run(ctx)


func _get_all_abilities() -> Array[Ability]:
	var result: Array[Ability] = []
	result.append_array(_native_abilities)
	result.append_array(_granted_abilities)
	return result


func _connect_owner_signals() -> void:
	if not _owner is Piece:
		return
	var piece := _owner as Piece
	if piece.attack_component:
		if not piece.attack_component.on_hit.is_connected(_on_attack_hit):
			piece.attack_component.on_hit.connect(_on_attack_hit)
		if not piece.attack_component.on_kill.is_connected(_on_attack_kill):
			piece.attack_component.on_kill.connect(_on_attack_kill)


func _on_attack_hit(target: Piece) -> void:
	dispatch(GameTrigger.Type.ON_ATTACK_HIT, target)


func _on_attack_kill(target: Piece) -> void:
	dispatch(GameTrigger.Type.ON_ATTACK_KILL, target)


func _on_piece_moved(moved_piece: Piece) -> void:
	if not _owner is Piece:
		return
	var piece := _owner as Piece
	if not piece.is_on_board:
		return
	dispatch(GameTrigger.Type.ON_PIECE_MOVED, moved_piece)
