extends RefCounted
## 用实际音频分段建立时间对应；不采用识别器按字数估计的时间戳。
const Mic = preload("res://scripts/voice/microphone.gd")

static func perception(source: Vector3, forward: Vector3, positions: Dictionary, radius: float) -> Dictionary:
	var heard: Dictionary = {}
	var focus := ""
	var best := 0.0
	var second := 0.0
	for id in positions:
		var offset: Vector3 = positions[id]-source
		var angle := rad_to_deg(forward.angle_to(offset)) if offset.length()>0.01 else 0.0
		# 平滑指向性：正前方完整半径，背后仍有 60% 半径。
		var reach := radius * (0.8+0.2*cos(deg_to_rad(angle)))
		if offset.length()>reach: continue
		heard[id] = {"distance_m":snappedf(offset.length(),0.1),"angle_degrees":snappedf(angle,1.0)}
		if angle<=30.0:
			var score := 1.0-angle/30.0
			if score>best:
				second=best
				best=score
				focus=id
			else: second=maxf(second,score)
	if best-second<0.15: focus=""
	return {"heard":heard,"focus_hint":focus}

static func split(wav: PackedByteArray, samples: Array) -> Array:
	var audio := AudioStreamWAV.load_from_buffer(wav)
	assert(audio!=null and audio.mix_rate==16000)
	var duration := float(audio.data.size())/32000.0
	var cuts: Array[float] = [0.0]
	if not samples.is_empty():
		var anchor: Vector3=samples[0].forward
		var anchor_focus: String=samples[0].get("focus_hint","")
		for sample_index in samples.size():
			var sample: Dictionary=samples[sample_index]
			var at: float=sample.time
			if at-cuts.back()<0.8 or duration-at<0.8: continue
			var changed_focus: bool=sample.get("focus_hint","")!="" and sample.get("focus_hint","")!=anchor_focus
			if anchor.angle_to(sample.forward)<deg_to_rad(35) and not changed_focus: continue
			var later: Dictionary=samples[mini(sample_index+3,samples.size()-1)]
			if sample.forward.angle_to(later.forward)>deg_to_rad(15): continue
			# 转向附近寻找 20ms 最低能量边界，减小截断音节的概率。
			var chosen:=at
			var minimum:=INF
			for step in range(-10,11):
				var candidate:=at+step*0.02
				if candidate-cuts.back()<0.6 or duration-candidate<0.6: continue
				var energy:=0.0
				var center:=int(candidate*16000)
				for index in range(center-160,center+160):
					energy+=pow(float(audio.data.decode_s16(index*2)),2)
				if energy<minimum:
					minimum=energy
					chosen=candidate
			cuts.append(chosen)
			anchor=sample.forward
			anchor_focus=sample.get("focus_hint","")
			if cuts.size()>=6: break
	cuts.append(duration)
	var parts: Array=[]
	for i in cuts.size()-1:
		var raw:=audio.data.slice(int(cuts[i]*16000)*2,mini(int(cuts[i+1]*16000)*2,audio.data.size()))
		var pcm:=PackedFloat32Array()
		for index in raw.size()/2:
			pcm.append(float(raw.decode_s16(index*2))/32768.0)
		# 输入由本项目录音器产生，直接切 PCM，避免重复重采样。
		var header:=Mic.encode_wav(PackedFloat32Array(),16000)
		header.encode_u32(4,36+raw.size())
		header.encode_u32(40,raw.size())
		header.append_array(raw)
		parts.append({"start":cuts[i],"end":cuts[i+1],"wav":header,"pcm":pcm})
	return parts
