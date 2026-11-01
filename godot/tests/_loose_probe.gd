extends SceneTree
func _init() -> void:
	for k in ["kolonia_stawowa","babudy_gora","rajsko_wilczkowice","lipowiec_kobylec","maly_bor","goliath"]:
		var t := Track.new(Track.load_def(k))
		var tot := 0.0
		for z in t.loose: tot += z.y - z.x
		print(k, " loose spans=", t.loose.size(), " loose m=", snappedf(tot,1), " of ", snappedf(t.L,1))
	var sh: Shader = load("res://shaders/road.gdshader")
	print("shader ok ", sh != null)
	quit()
