extends Node3D
## 固定世界尺寸的头顶面板，所有内容使用同一布局，不做距离补偿。
var view: SubViewport
var sprite: Sprite3D
var title: Label
var status: Label
var speech: Label
var panel: PanelContainer

func _ready() -> void:
	view=SubViewport.new();view.size=Vector2i(720,180)
	view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	panel=PanelContainer.new();panel.size=Vector2(720,180);view.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.035,0.045,0.93)
	style.content_margin_left=20;style.content_margin_right=20
	style.content_margin_top=15;style.content_margin_bottom=15
	panel.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);panel.add_child(box)
	title=_label(box,52,1);status=_label(box,40,2);speech=_label(box,44,4)
	sprite=Sprite3D.new();sprite.texture=view.get_texture();sprite.pixel_size=0.002
	sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.shaded=false
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.position.y=180*0.002/2.0;add_child(sprite)

func _label(box: VBoxContainer, size: int, lines: int) -> Label:
	var label:=Label.new();label.add_theme_font_size_override("font_size",size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.max_lines_visible=lines
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(label);return label

func update_content(name_text: String, status_text: String, speech_text: String, compact: bool=false) -> void:
	title.text=name_text if compact else name_text+" · E 详情"
	status.text=status_text;status.visible=not compact and not status_text.is_empty()
	speech.text=speech_text;speech.visible=not compact and not speech_text.is_empty()
	var width:=720
	if compact:
		width=int(ceil(title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,52).x))+40

	# 内容区随行数收缩；世界中的宽度固定，不按玩家距离放大。
	var height:=30
	var visible_labels:=0
	for label in [title,status,speech]:
		if not label.visible:continue
		var lines:=maxi(1,mini(label.get_line_count(),label.max_lines_visible))
		height+=int(ceil(label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))*lines))
		visible_labels+=1
	height+=maxi(0,visible_labels-1)*12
	height=maxi(height,100)
	if view.size!=Vector2i(width,height):
		view.size=Vector2i(width,height);panel.size=Vector2(width,height)
		sprite.position.y=height*0.002/2.0
