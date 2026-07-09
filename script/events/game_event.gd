class_name GameEvent
extends RefCounted

var trigger: GameTrigger.Type
var source: Card
var primary_target: Variant = null
var extra: Dictionary = {}


static func create(
	trigger_type: GameTrigger.Type,
	source_card: Card,
	target: Variant = null,
	extra_data: Dictionary = {}
) -> GameEvent:
	var event := GameEvent.new()
	event.trigger = trigger_type
	event.source = source_card
	event.primary_target = target
	event.extra = extra_data
	return event
