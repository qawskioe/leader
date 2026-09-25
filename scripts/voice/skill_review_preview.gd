extends Node3D
## 展示隔离进程发布的关键帧；本游戏不执行候选代码。
var picture: Sprite3D
var caption: Label3D
var job:=""
var last_file:=""
var clock:=0.0
var display_in_panel:=false

func _ready() -> void:
	picture=Sprite3D.new();picture.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	picture.pixel_size=0.0016;picture.shaded=false;add_child(picture)
	caption=Label3D.new();caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size=24;caption.pixel_size=0.0018;caption.position.y=-0.59
	caption.outline_size=8;add_child(caption);hide()

func show_job(value: String) -> void:
	if value==job: return
	job=value;last_file="";hide()
	picture.texture=null;caption.text=""

func _process(delta: float) -> void:
	clock+=delta
	if clock<0.3 or job.is_empty() or not job.is_valid_identifier(): return
	clock=0.0
	var base:="res://services/skill-runtime/runtime/jobs/"+job+"/"
	if not FileAccess.file_exists(base+"preview.json"): return
	var json:=JSON.new()
	if json.parse(FileAccess.get_file_as_string(base+"preview.json"))!=OK: return # 写入中，下次再读。
	var data: Variant=json.data
	if not data is Dictionary: return
	var path:=str(data.get("file",""))
	var pieces:=path.split("/")
	if pieces.size()!=2 or not pieces[0].is_valid_identifier() or not pieces[1].begins_with("frame_") or not pieces[1].ends_with(".jpg") or ".." in path: return
	if path==last_file: return
	var frame:=Image.load_from_file(base+path)
	if frame==null or frame.is_empty(): return
	picture.texture=ImageTexture.create_from_image(frame)
	caption.text="独立验证 · 关键帧 %.1fs\n%s"%[float(data.get("time_ms",0))/1000.0,str(data.get("stage",""))]
	last_file=path
	visible=not display_in_panel
