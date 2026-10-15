class_name CityTerrainElevation
extends RefCounted
## A map-wide display range, cached until land or water heights change.
var _signature: Array = []
var _range := Vector2(0, 31)


func range_for(city: CityState) -> Vector2:
	if city == null:
		return Vector2(0, 31)
	var signature := [city.get_instance_id(), city.chunk_revision("ALTM")]
	if signature == _signature:
		return _range
	_signature = signature
	var lowest := 31
	var highest := 0
	for word: int in city.altitude_words:
		var land := word & Sc2AltitudeLayout.LAND_MASK
		var water := (word >> Sc2AltitudeLayout.WATER_SHIFT) & Sc2AltitudeLayout.LEVEL_MASK
		if water > land:
			continue
		lowest = mini(lowest, land)
		highest = maxi(highest, land)
	if lowest > highest:
		_range = Vector2(0, 31)
	else:
		# Small bumps must not consume the full contrast budget. Flat maps stay neutral.
		var center := (lowest + highest) * 0.5
		var half_span := maxf(4.0, (highest - lowest) * 0.5)
		_range = Vector2(center - half_span, center + half_span)
	return _range
