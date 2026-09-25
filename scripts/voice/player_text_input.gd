extends CanvasLayer
## 文字替代收音；提交后与语音共用空间听闻和角色决策。
var voice: Node
var panel: PanelContainer
var edit: LineEdit
var notice: Label
func _ready() -> void:
	layer=15
	panel=PanelContainer.new();panel.position=Vector2(24,90);panel.size=Vector2(650,90);add_child(panel)
	var box:=VBoxContainer.new();panel.add_child(box)
	notice=Label.new();notice.text="输入要说的话 · Enter 发送 · Escape 取消";box.add_child(notice)
	edit=LineEdit.new();edit.placeholder_text="面向交谈对象，说出你的话";edit.max_length=500;box.add_child(edit)
	edit.text_submitted.connect(submit)
	panel.hide()
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if panel.visible and event.physical_keycode==KEY_ESCAPE:
		close();get_viewport().set_input_as_handled()
	elif not panel.visible and event.physical_keycode==KEY_T and not voice.menu.is_open() and get_viewport().gui_get_focus_owner()==null:
		notice.text="输入要说的话 · Enter 发送 · Escape 取消"
		panel.show();edit.clear();edit.grab_focus();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
func submit(value: String) -> void:
	var error: String=voice.say_text(value)
	if not error.is_empty():notice.text=error;return
	close()
func close() -> void:
	edit.release_focus();panel.hide();Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
