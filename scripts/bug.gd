extends CharacterBody2D
## Generic bug. It just roams the arena at random and dies when the player's melee
## attack reaches it -- splattering on the way out. Harmless: it attacks nothing.
##
## One scene (bug.tscn) is reused for every enemy type; the level manager sets
## `frames_override`, stats and scale when it spawns each bug. The Level 3 Mantis is
## the same script with a bigger body and a few more hit points.

signal died(bug: Node)

@export var speed: float = 90.0
@export var is_boss: bool = false
@export var max_hp: int = 1                  ## hits to kill (Mantis takes several)
@export var frames_override: SpriteFrames    ## set by the spawner to pick the bug's look
@export var sprite_forward: Vector2 = Vector2.UP  ## direction a single-frame sheet is drawn facing
@export var death_linger: float = 1.1        ## seconds the corpse lies before poofing
@export var splat_color: Color = Color(0.48, 0.20, 0.34, 0.9)  ## goo tint, set per bug
@export var tint: Color = Color.WHITE        ## sprite recolor (e.g. purple roach); white = untinted

var hp: int

var wander_dir: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var is_squashed: bool = false
var player: Node2D = null
var target_server: Node2D = null

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var death_sound: AudioStreamPlayer2D = $DeathSound

func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	hp = max_hp
	if frames_override:
		anim.sprite_frames = frames_override
	anim.modulate = tint
	_choose_wander()

func _physics_process(delta: float) -> void:
	if is_squashed:
		return
	_move_smart(delta)

# Lets make the bugs smart:

func _move_smart(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		_choose_wander()
		var servers := get_tree().get_nodes_in_group("servers")
		var valid := servers.filter(func(s): return is_instance_valid(s))
		if valid.size() > 0:
			target_server = valid[randi() % valid.size()]

	var move_dir := wander_dir

	if is_instance_valid(target_server):
		var to_server := (target_server.global_position - global_position).normalized()
		move_dir = (move_dir + to_server * 0.6).normalized()

	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		if to_player.length() < 90.0:
			move_dir -= to_player.normalized() * 1.0     # Avoidence strength
			move_dir = move_dir.normalized()

	velocity = move_dir * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		_choose_wander()
	_play_move(velocity)
	
func _wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		_choose_wander()
	velocity = wander_dir * speed
	var collision := move_and_collide(velocity * delta)
	if collision:
		_choose_wander()
	_play_move(velocity)

func _choose_wander() -> void:
	wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	wander_timer = randf_range(1.0, 2.5)

## Pick a directional walk animation if the sprite has them, otherwise a
## generic "move" / "default" loop rotated to face the travel direction.
func _play_move(dir: Vector2) -> void:
	var sf := anim.sprite_frames
	if sf == null:
		return
	if sf.has_animation("walk_down"):
		# Directional sheet (roach, beetle, Mantis): the frames already face the right way.
		anim.play("walk_" + _dir_name(dir))
	elif sf.has_animation("move"):
		anim.play("move")
		_orient(dir)
	elif sf.has_animation("default"):
		anim.play("default")
		_orient(dir)

## Name the cardinal direction `dir` points in (matches the walk_* suffixes).
func _dir_name(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"

## Rotate a single-frame sheet (the colored bugs, ant) so its drawn front points along `dir`.
## Directional sheets (roach, beetle, Mantis) use per-direction frames and stay un-rotated.
func _orient(dir: Vector2) -> void:
	if dir.length_squared() < 0.001:
		return
	if anim.sprite_frames and anim.sprite_frames.has_animation("walk_down"):
		return
	anim.rotation = dir.angle() - sprite_forward.angle()

## Called by the player's melee strike. Tough bugs (the Mantis) survive several hits;
## others die in a splatter immediately. The bug never hits back.
func squash(_by_player: Node = null) -> void:
	if is_squashed:
		return

	hp -= 1
	if hp > 0:
		# Survived the hit: flash and shrug it off.
		_flash_hit()
		return

	is_squashed = true

	speed = 0.0
	velocity = Vector2.ZERO
	$CollisionShape2D.set_deferred("disabled", true)

	_play_death()
	died.emit(self)

	# Killing the last bug completes the level, which changes the scene and
	# detaches us mid-call -- get_tree() would be null below. Nothing left to do.
	if not is_inside_tree():
		return

	# Lie on the floor briefly, then poof and free.
	get_tree().create_timer(death_linger).timeout.connect(func() -> void:
		anim.visible = false
		$CPUParticles2D.emitting = true
		get_tree().create_timer(0.4).timeout.connect(queue_free)
	)

## Death visuals: every bug flings a burst of goo tinted to its own colour. Bugs with a
## real squashed pose (roach, ant) play it; the rest squish flat and wide to read as a splat.
func _play_death() -> void:
	death_sound.play()
	anim.rotation = 0.0   # corpse lies flat regardless of travel heading

	# Colour-matched goo burst for every bug.
	$CPUParticles2D.color = splat_color
	$CPUParticles2D.emitting = true

	if anim.sprite_frames and anim.sprite_frames.has_animation("squashed"):
		anim.play("squashed")
	else:
		# No death frame (Level 1 bugs, beetle, Mantis): squish the sprite flat and wide,
		# bleeding toward a darkened version of its goo colour.
		anim.stop()
		var splat := create_tween()
		splat.set_parallel(true)
		splat.tween_property(anim, "scale:y", 0.2, 0.22)
		splat.tween_property(anim, "scale:x", 1.5, 0.22)
		splat.tween_property(anim, "modulate", splat_color.darkened(0.3), 0.22)

func _flash_hit() -> void:
	anim.modulate = Color(1, 0.4, 0.4)
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(anim):
			anim.modulate = tint
	)
