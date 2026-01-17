extends Node
## Game State - Match state tracking
## Works with Steam lobby system - syncs via Steam P2P

signal player_added(steam_id: int, player_data: Dictionary)
signal player_removed(steam_id: int)
signal player_updated(steam_id: int, player_data: Dictionary)
signal match_phase_changed(phase: MatchPhase)
signal zone_updated(zone_data: Dictionary)

enum MatchPhase {
	LOBBY,
	STARTING,
	IN_GAME,
	ENDED
}

# Player data structure: {steam_id: {name, alive, kills, team}}
var players: Dictionary = {}

# Match state
var match_phase: MatchPhase = MatchPhase.LOBBY
var match_start_time: float = 0.0
var alive_count: int = 0

# Zone state (for BR circle)
var zone := {
	"center": Vector3.ZERO,
	"radius": 1000.0,
	"target_radius": 1000.0,
	"shrink_rate": 0.0,
	"damage_per_second": 1.0
}


func _ready() -> void:
	reset()


## Reset all game state
func reset() -> void:
	players.clear()
	match_phase = MatchPhase.LOBBY
	match_start_time = 0.0
	alive_count = 0
	zone = {
		"center": Vector3.ZERO,
		"radius": 1000.0,
		"target_radius": 1000.0,
		"shrink_rate": 0.0,
		"damage_per_second": 1.0
	}


## Add a player to the game
func add_player(steam_id: int, player_name: String) -> void:
	var player_data := {
		"name": player_name,
		"alive": true,
		"kills": 0,
		"team": 0
	}
	
	players[steam_id] = player_data
	alive_count = _count_alive()
	
	player_added.emit(steam_id, player_data)


## Remove a player from the game
func remove_player(steam_id: int) -> void:
	if players.has(steam_id):
		players.erase(steam_id)
		alive_count = _count_alive()
		player_removed.emit(steam_id)


## Update player data
func update_player(steam_id: int, data: Dictionary) -> void:
	if players.has(steam_id):
		for key in data:
			players[steam_id][key] = data[key]
		
		alive_count = _count_alive()
		player_updated.emit(steam_id, players[steam_id])


## Set match phase
func set_match_phase(phase: MatchPhase) -> void:
	match_phase = phase
	
	if phase == MatchPhase.IN_GAME:
		match_start_time = Time.get_unix_time_from_system()
	
	match_phase_changed.emit(phase)


## Update zone state
func update_zone(center: Vector3, radius: float, target_radius: float, shrink_rate: float, damage: float) -> void:
	zone.center = center
	zone.radius = radius
	zone.target_radius = target_radius
	zone.shrink_rate = shrink_rate
	zone.damage_per_second = damage
	
	zone_updated.emit(zone)


## Mark a player as dead
func kill_player(steam_id: int, killer_id: int = 0) -> void:
	if players.has(steam_id):
		players[steam_id].alive = false
		
		if killer_id > 0 and players.has(killer_id):
			players[killer_id].kills += 1
			player_updated.emit(killer_id, players[killer_id])
		
		alive_count = _count_alive()
		player_updated.emit(steam_id, players[steam_id])
		
		if alive_count <= 1 and match_phase == MatchPhase.IN_GAME:
			set_match_phase(MatchPhase.ENDED)


## Get player data by steam ID
func get_player(steam_id: int) -> Dictionary:
	return players.get(steam_id, {})


## Get all alive players
func get_alive_players() -> Array:
	var alive := []
	for steam_id in players:
		if players[steam_id].alive:
			alive.append(steam_id)
	return alive


## Get the winner
func get_winner() -> int:
	var alive := get_alive_players()
	return alive[0] if alive.size() == 1 else 0


## Count alive players
func _count_alive() -> int:
	var count := 0
	for steam_id in players:
		if players[steam_id].alive:
			count += 1
	return count


## Get player count
func get_player_count() -> int:
	return players.size()
