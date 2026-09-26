extends Control


func _ready() -> void:
	# 简单自检：把引擎版本显示到界面上。
	# 改游戏内容后只需换 pck，重新打开时这里的版本/文案变化
	# 能直观确认新 pck 确实生效了。
	var label := $Label as Label
	if label:
		label.text = "MyGame\nGodot %s" % Engine.get_version_info().string
