@tool
class_name ExitConfirm
extends Control

# 退出确认 modal。设计：design README §7
# 用法：作为 main_menu 子节点 instance，初始 visible=false，调用 show_modal()
# 通过 cancelled / confirmed 信号回调

signal cancelled
signal confirmed

@onready var _bg: ColorRect = $Bg
@onready var _dialog: ChamferPanel = $Center/Dialog
@onready var _cancel_btn: SecondaryButton = $Center/Dialog/Buttons/CancelButton
@onready var _confirm_btn: SecondaryButton = $Center/Dialog/Buttons/ConfirmButton

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cancel_btn.pressed.connect(_on_cancel)
	_confirm_btn.pressed.connect(_on_confirm)

func show_modal() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_modal() -> void:
	visible = false

func _on_cancel() -> void:
	AudioManager.play_ui_click()
	hide_modal()
	cancelled.emit()

func _on_confirm() -> void:
	AudioManager.play_ui_click()
	confirmed.emit()
	# 由调用方决定是否真正 quit / hide，这里不主动 hide

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()
			accept_event()
