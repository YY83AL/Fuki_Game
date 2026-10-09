extends Node
## Общие настройки на всех экранах (автозагрузка GameSettings).
## При запуске всё выключено. Что игрок включает на одном экране — действует и на остальных.

var sounds := false
var music := false
var rain := false
var fog := false
var hybrid := false


## Состояние кнопки меню по её подписи («4 · Звуки» и т.д.). Незнакомая кнопка — как задано.
func get_for(label: String, default_on: bool) -> bool:
	if "Звуки" in label: return sounds
	if "Музыка" in label: return music
	if "Дождь" in label: return rain
	if "Туман" in label: return fog
	if "Гибрид" in label: return hybrid
	return default_on


func set_for(label: String, on: bool) -> void:
	if "Звуки" in label: sounds = on
	elif "Музыка" in label: music = on
	elif "Дождь" in label: rain = on
	elif "Туман" in label: fog = on
	elif "Гибрид" in label: hybrid = on
