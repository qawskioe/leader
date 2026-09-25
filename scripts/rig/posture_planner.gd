extends RefCounted
## 纯运动学预检：仅计算Transform，不修改渲染骨架或世界物体。
const LIMBS={"Hand.L":["UpperArm.L","Forearm.L"],"Hand.R":["UpperArm.R","Forearm.R"],"Foot.L":["Thigh.L","Shin.L"],"Foot.R":["Thigh.R","Shin.R"]}
var rests: Array[Transform3D]=[]
var parents: Array[int]=[]
var indices: Dictionary={}
var lengths: Dictionary={}
var rest_positions: Dictionary={}
var _standing:=Vector3.INF
var _candidates: Array[Dictionary]=[]

func initialize(skeleton: Skeleton3D) -> void:
 for index in skeleton.get_bone_count():
  rests.append(skeleton.get_bone_rest(index));parents.append(skeleton.get_bone_parent(index));indices[skeleton.get_bone_name(index)]=index
  rest_positions[skeleton.get_bone_name(index)]=skeleton.get_bone_global_rest(index).origin
 for name in LIMBS:
  var a: Vector3=rest_positions[LIMBS[name][0]];var b: Vector3=rest_positions[LIMBS[name][1]];var c: Vector3=rest_positions[name]
  var upper:=a.distance_to(b);var lower:=b.distance_to(c)
  lengths[name]={"minimum":sqrt(upper*upper+lower*lower+2*upper*lower*cos(deg_to_rad(145))),"maximum":sqrt(upper*upper+lower*lower+2*upper*lower*cos(deg_to_rad(5))),"comfortable":(upper+lower)*.94}

func _global(index: int, overrides: Dictionary, cache: Dictionary) -> Transform3D:
 if cache.has(index):return cache[index]
 var local: Transform3D=overrides.get(index,rests[index])
 var result:=local if parents[index]<0 else _global(parents[index],overrides,cache)*local
 cache[index]=result
 return result

func _prepare(standing: Vector3) -> void:
 if standing.is_equal_approx(_standing):return
 _standing=standing;_candidates.clear()
 for step in 25:
  var weight:=float(step)/24
  var hip:=standing;hip.y=lerpf(standing.y,.25,weight);hip.z-=.12*weight
  var hip_index: int=indices.Hips
  var parent:=_global(parents[hip_index],{}, {})
  var hip_local: Transform3D=rests[hip_index];hip_local.origin=parent.affine_inverse()*hip
  for lean_step in 17:
   var lean:=deg_to_rad(lean_step*5)
   var overrides: Dictionary={hip_index:hip_local}
   for name in ["Spine","Chest"]:
    var index: int=indices[name];var pose: Transform3D=rests[index]
    pose.basis=Basis(pose.basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,lean*(.7 if name=="Spine" else .3))).scaled(pose.basis.get_scale())
    overrides[index]=pose
   var cache: Dictionary={};var roots: Dictionary={}
   for name in LIMBS:roots[name]=_global(indices[LIMBS[name][0]],overrides,cache).origin
   _candidates.append({"hip":hip,"lean":lean,"roots":roots,"base_cost":weight*.002+float(lean_step)/16*.003})

func choose(standing: Vector3, hands: Dictionary, feet: Dictionary) -> Dictionary:
 _prepare(standing)
 var best: Dictionary={};var best_cost:=INF
 for candidate in _candidates:
  var valid:=true
  for foot in feet:
   var distance: float=candidate.roots[foot].distance_to(feet[foot])
   if distance<lengths[foot].minimum+.008 or distance>lengths[foot].maximum+.002:valid=false;break
  if not valid:continue
  var cost: float=candidate.base_cost;var error:=0.0
  for hand in hands:
   var distance: float=candidate.roots[hand].distance_to(hands[hand])
   cost+=maxf(0,distance-lengths[hand].comfortable)+maxf(0,lengths[hand].minimum+.008-distance)
   error=maxf(error,maxf(distance-lengths[hand].maximum,lengths[hand].minimum-distance))
  if cost<best_cost:
   best_cost=cost;best={"hip":candidate.hip,"lean":candidate.lean,"error_m":maxf(0,error),"cost":cost}
 return best
