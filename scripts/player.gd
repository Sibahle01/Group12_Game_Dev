extends CharacterBody2D
## The IT technician. WASD movement with 4-direction idle/run/attack animations,
## a melee attack that squashes nearby bugs, and its own HP pool.

signal hp_changed(hp: int, max_hp: int)
signal died

@export var speed: float = 240.0
@export var max_hp: int = 100
@export var attack_range: float = 90.0      ## reach of the melee swing
@export var invuln_time: float = 1.0        ## i-frames after taking a bite
@export var regen_rate: float = 6.0         ## HP restored per second once regen kicks in
@export var regen_delay: float = 2.5        ## seconds without a bite before regen starts


const FIREWALL_SCENE := preload("res://scenes/firewall.tscn")

var firewalls_remaining := 3
var hp: int
var facing: String = "down"                 ## down / up / left / right
var is_attacking: bool = false
var invuln_timer: float = 0.0
var _since_hit: float = 999.0               ## time since the last bite
var _regen_accum: float = 0.0               ## fractional HP banked toward the next point
var is_caffeinated: bool = false     # initially no coffee

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var swing_sword: AudioStreamPlayer2D = $SwingSword

#Firewall added
@onready var fw_icons := [
	$"../HUD/Root/FirewallIcons/FW1",
	$"../HUD/Root/FirewallIcons/FW2",
	$"../HUD/Root/FirewallIcons/FW3"
]

# Firewall Fuction 
func _update_firewall_icons() -> void:
	var icons = [
		get_tree().get_root().find_child("FW1", true, false),
		get_tree().get_root().find_child("FW2", true, false),
		get_tree().get_root().find_child("FW3", true, false),
	]
	for i in range(3):
		if icons[i]:
			icons[i].modulate.a = 1.0 if i < firewalls_remaining else 0.3
			
func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	anim.animation_finished.connect(_on_anim_finished)
	_update_firewall_icons()

func _physics_process(delta: float) -> void:
	if invuln_timer > 0.0:
		invuln_timer -= delta
		# Flash while invulnerable.
		anim.modulate.a = 0.4 if int(invuln_timer * 20) % 2 == 0 else 1.0
	else:
		anim.modulate.a = 1.0

	_since_hit += delta
	if _since_hit >= regen_delay and hp > 0 and hp < max_hp:
		_regen_accum += regen_rate * delta
		if _regen_accum >= 1.0:
			var gained := int(_regen_accum)
			_regen_accum -= gained
			hp = min(max_hp, hp + gained)
			hp_changed.emit(hp, max_hp)

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("attack"):
		swing_sword.play()
		_start_attack()
		return
		
	if Input.is_action_just_pressed("firewall") and firewalls_remaining > 0:
		var fw := FIREWALL_SCENE.instantiate()
		fw.global_position = global_position
		get_parent().add_child(fw)
		firewalls_remaining -= 1
		_update_firewall_icons()

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()

	if direction != Vector2.ZERO:
		_update_facing(direction)
		anim.play("run_" + facing)
	else:
		anim.play("idle_" + facing)

func _update_facing(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		facing = "right" if direction.x > 0 else "left"
	else:
		facing = "down" if direction.y > 0 else "up"

func _start_attack() -> void:
	is_attacking = true
	anim.play("attack_" + facing)
	_strike()

#Function for cofffee
func drink_coffee() -> void:
	if is_caffeinated:
		return
	is_caffeinated = true
	speed *= 2.0
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		speed /= 2.0
		is_caffeinated = false
	)


## Squash every bug within reach in the facing direction.
func _strike() -> void:
	var dir := _facing_vector()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > attack_range:
			continue
		# Only hit things roughly in front of us.
		if dir.dot(to_enemy.normalized()) < 0.3:
			continue
		if enemy.has_method("squash"):
			enemy.squash(self)

func _facing_vector() -> Vector2:
	match facing:
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up": return Vector2.UP
		_: return Vector2.DOWN

func _on_anim_finished() -> void:
	if anim.animation.begins_with("attack"):
		is_attacking = false

## Called by bugs when they bite back during a squash.
func take_damage(amount: int) -> void:
	if invuln_timer > 0.0:
		return
	hp = max(0, hp - amount)
	invuln_timer = invuln_time
	_since_hit = 0.0
	_regen_accum = 0.0
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		died.emit()
