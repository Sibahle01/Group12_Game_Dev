extends Node2D
## Drives a single level: reads GameState.current_level, spawns a fixed number of
## bugs that roam the arena, and completes the level once every spawned bug has been
## squashed. Lives in the "level" group. No servers, no timer, no uptime.

const SERVER_SCENE := preload("res://scenes/server.tscn")
const BUG_SCENE := preload("res://scenes/bug.tscn")
const ANT_FRAMES := preload("res://scenes/frames/ant_frames.tres")
const BEETLE_FRAMES := preload("res://scenes/frames/beetle_frames.tres")
const BOSS_FRAMES := preload("res://scenes/frames/boss_frames.tres")
const BUG_BROWN := preload("res://scenes/frames/bug_brown_frames.tres")
const BUG_DARK := preload("res://scenes/frames/bug_dark_frames.tres")
const BUG_OLIVE := preload("res://scenes/frames/bug_olive_frames.tres")
const BUG_MAROON := preload("res://scenes/frames/bug_maroon_frames.tres")
const COFFEE_SCENE := preload("res://scenes/coffee.tscn")              # Cofffeee speed up
const FIELD := Rect2(60, 96, 1032, 492)   # inner play area bugs spawn along

# Per-enemy-type base stats. `frames = null` keeps bug.tscn's default roach.
# `forward` is the direction the sprite sheet is drawn facing (null = directional sheet).
# `splat_color` tints each bug's death goo to roughly its own body colour (brightened so it
# reads against the dark background).
const PRESETS := {
	"roach":  {"frames": null,          "speed": 70.0,  "scale": 2.0, "hp": 1, "forward": null,         "splat_color": Color(0.48, 0.20, 0.34, 0.9), "tint": Color(0.80, 0.45, 1.00)},
	"ant":    {"frames": ANT_FRAMES,    "speed": 85.0,  "scale": 0.5, "hp": 1, "forward": Vector2.UP,   "splat_color": Color(0.46, 0.22, 0.13, 0.9)},
	"beetle": {"frames": BEETLE_FRAMES, "speed": 110.0, "scale": 2.4, "hp": 1, "forward": Vector2.UP,   "splat_color": Color(0.52, 0.54, 0.60, 0.9)},
	# Level 1 bugs: top-down sheets rotated to face travel (art faces down), squish + goo splatter on death.
	"bug_brown":  {"frames": BUG_BROWN,  "speed": 80.0, "scale": 0.55, "hp": 1, "forward": Vector2.DOWN, "splat_color": Color(0.50, 0.24, 0.10, 0.9)},
	"bug_dark":   {"frames": BUG_DARK,   "speed": 80.0, "scale": 0.55, "hp": 1, "forward": Vector2.DOWN, "splat_color": Color(0.32, 0.22, 0.17, 0.9)},
	"bug_olive":  {"frames": BUG_OLIVE,  "speed": 80.0, "scale": 0.55, "hp": 1, "forward": Vector2.DOWN, "splat_color": Color(0.44, 0.40, 0.12, 0.9)},
	"bug_maroon": {"frames": BUG_MAROON, "speed": 80.0, "scale": 0.55, "hp": 1, "forward": Vector2.DOWN, "splat_color": Color(0.58, 0.10, 0.12, 0.9)},
}

# Per-level configuration. `count` is the total bugs to kill (incl. the boss on L3).
const LEVELS := {
	1: {"pool": ["bug_brown", "bug_dark", "bug_olive", "bug_maroon", "roach"],
		"count": 5, "speed_mult": 1.0, "spawn": 2.2, "boss": false},
	2: {"pool": ["beetle", "bug_brown", "bug_dark", "bug_olive", "bug_maroon", "roach"],
		"count": 10, "speed_mult": 1.3, "spawn": 1.7, "boss": false},
	3: {"pool": ["beetle", "ant", "bug_brown", "bug_dark", "bug_olive", "bug_maroon", "roach"],
		"count": 13, "speed_mult": 1.6, "spawn": 1.4, "boss": true},
}

var level := 1
var running := true
var _cfg: Dictionary
var _to_kill := 0       ## bugs still alive or yet to spawn; level ends when this hits 0
var _spawned := 0       ## regular (non-boss) bugs spawned so far
var _spawn_cap := 0     ## how many regular bugs this level spawns
var _servers_alive := 0

@onready var spawn_timer: Timer = $SpawnTimer
@onready var level_label: Label = $HUD/Root/LevelLabel
@onready var overlay: Panel = $HUD/Root/Overlay
@onready var result_label: Label = $HUD/Root/Overlay/ResultLabel

func _ready() -> void:
	add_to_group("level")
	level = GameState.current_level
	_cfg = LEVELS.get(level, LEVELS[1])

	overlay.visible = false
	level_label.text = "LEVEL %d" % level

	_to_kill = int(_cfg["count"])
	_spawn_cap = _to_kill - (1 if _cfg["boss"] else 0)
	_spawn_servers()

	if _cfg["boss"]: 
		if MusicManager.music:
			MusicManager.music.stop()
		var boss_music := AudioStreamPlayer.new()
		add_child(boss_music)
		boss_music.stream = load("res://assets/Audio/536537__xcreenplay__level-5-boss-runxp3wav.wav")
		boss_music.play()
		_spawn_boss()

	spawn_timer.wait_time = _cfg["spawn"]
	spawn_timer.timeout.connect(_on_spawn)
	spawn_timer.start()
	_start_coffee_timer()

func _start_coffee_timer() -> void:
	var wait_time := randf_range(5.0, 15.0)    # La we adjust the time to get the next cofffee
	get_tree().create_timer(wait_time).timeout.connect(func() -> void:
		if running:
			_spawn_coffee()
			_start_coffee_timer()  
	)

# Sever things

func _spawn_servers() -> void:
	var positions := {
		1: [Vector2(220, 120), Vector2(700, 390)],
		2: [Vector2(150, 150), Vector2(550, 300), Vector2(900, 400)],
		3: [Vector2(150, 150), Vector2(400, 300), Vector2(700, 200), Vector2(950, 380)],
	}
	for pos in positions[level]:
		var server := SERVER_SCENE.instantiate()
		var counter := 1
		server.position = pos
		server.server_name = "Server %d" % counter
		server.destroyed.connect(_on_server_destroyed)
		$Servers.add_child(server)
		_servers_alive += 1

func _on_server_destroyed() -> void:
	_servers_alive -= 1
	if _servers_alive <= 0:
		_game_over()

# coffee spawning
func _spawn_coffee() -> void:
	var coffee := COFFEE_SCENE.instantiate()
	coffee.position = Vector2(randf_range(FIELD.position.x + 50, FIELD.end.x - 50),
							  randf_range(FIELD.position.y + 50, FIELD.end.y - 50))
	coffee.collected.connect(func(body): body.drink_coffee())
	add_child(coffee)
# Cofffee must show rendommly

func _game_over() -> void:
	running = false
	spawn_timer.stop()
	get_tree().paused = true
	result_label.text = "ALL SERVERS DESTROYED!\nGAME OVER!"
	overlay.visible = true


# --- Spawning -----------------------------------------------------------

func _on_spawn() -> void:
	if not running or _spawned >= _spawn_cap:
		return
	var pool: Array = _cfg["pool"]
	_spawn_enemy(pool[randi() % pool.size()])
	_spawned += 1
	if _spawned >= _spawn_cap:
		spawn_timer.stop()

func _spawn_enemy(type: String) -> void:
	var p: Dictionary = PRESETS[type]
	var bug := BUG_SCENE.instantiate()
	if p["frames"] != null:
		bug.frames_override = p["frames"]
	bug.speed = float(p["speed"]) * float(_cfg["speed_mult"])
	bug.max_hp = int(p["hp"])
	if p["forward"] != null:
		bug.sprite_forward = p["forward"]
	bug.splat_color = p.get("splat_color", bug.splat_color)
	bug.tint = p.get("tint", Color.WHITE)
	bug.scale = Vector2(p["scale"], p["scale"])
	bug.position = _edge_spawn_point()
	bug.died.connect(_on_bug_died)
	add_child(bug)

func _spawn_boss() -> void:
	var boss := BUG_SCENE.instantiate()
	boss.frames_override = BOSS_FRAMES
	boss.is_boss = true
	boss.speed = 60.0 * float(_cfg["speed_mult"])
	boss.max_hp = 8                # a tougher roamer, but no health bar
	boss.death_linger = 1.2        # Mantis has no death frame -> squish + green goo splatter
	boss.splat_color = Color(0.40, 0.60, 0.20, 0.9)  # mantis green
	boss.scale = Vector2(3.5, 3.5) # 32px Mantis -> ~112px, clearly bigger than the bugs
	boss.position = Vector2(FIELD.position.x + FIELD.size.x * 0.5, FIELD.end.y - 40)
	boss.died.connect(_on_bug_died)
	add_child(boss)

func _edge_spawn_point() -> Vector2:
	# Spawn just inside one of the three non-HUD edges.
	match randi() % 3:
		0: return Vector2(FIELD.position.x + 10, randf_range(FIELD.position.y, FIELD.end.y))      # left
		1: return Vector2(FIELD.end.x - 10, randf_range(FIELD.position.y, FIELD.end.y))           # right
		_: return Vector2(randf_range(FIELD.position.x, FIELD.end.x), FIELD.end.y - 10)           # bottom

# --- Outcomes -----------------------------------------------------------

func _on_bug_died(_b: Node) -> void:
	if not running:
		return
	_to_kill -= 1
	if _to_kill <= 0:
		_level_complete()

func _level_complete() -> void:
	if not running:
		return
	running = false
	spawn_timer.stop()
	if GameState.is_final_level():
		_win()
	else:
		GameState.next_level()

func _win() -> void:
	get_tree().paused = true
	result_label.text = "ALL BUGS SQUASHED!\nYOU WIN!"
	overlay.visible = true

func _on_restart_pressed() -> void:
	GameState.restart()
