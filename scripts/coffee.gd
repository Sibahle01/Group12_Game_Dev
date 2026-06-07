extends Area2D

signal collected(body)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Despawn after 8 seconds if not collected
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		collected.emit(body)
		queue_free()
