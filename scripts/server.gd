extends Area2D

signal destroyed

@export var max_hp: int = 5
var hp: int

@onready var hp_bar: ProgressBar = $ProgressBar
@export var server_name: String = "Server"
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	add_to_group("servers")
	hp = max_hp
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	name_label.text = server_name
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies"):
		take_damage(1)

func take_damage(amount: int = 1) -> void:
	hp -= amount
	hp_bar.value = hp
	if hp <= 0:
		destroyed.emit()
		queue_free()
