class_name MusicBoxPlayback
extends CityAudioController
## Independent user playlist. Never connected to simulation music activity.

signal song_finished(track_id: int)


func _on_music_track_finished(track_id: int) -> void:
	if track_id == current_track_id:
		stop_music()
		song_finished.emit(track_id)
