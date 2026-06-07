extends Area2D

@onready var life_timer: Timer = $LifeTimer

func _ready() -> void:
	life_timer.wait_time = 5.0
	life_timer.one_shot = true
	life_timer.timeout.connect(queue_free)
	life_timer.start()
