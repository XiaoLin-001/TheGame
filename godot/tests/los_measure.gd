extends SceneTree
## 開發工具（**不是測試**）：量「地形擋住視線」會影響多少（B4.5，使用者：「確認地形起伏對於攻擊可視化的確認」）。
##
## 跑法（不開視窗）：<godot> --headless --path godot --script res://tests/los_measure.gd　　（`LOS_DETAIL=1` 逐座塔列出被擋的比例）
## ① 每關的參考解（`demo` 裡的 `place` 指令）把塔放在哪，敵人走過路徑上每一格時，有多少（塔, 路徑格）組合在射程內卻被地形擋住；
## ② 把每個可蓋的格都當成一座塔（錨／稜鏡／長哨三種射程），有多少格是盲區（射程內的路徑格超過一半被擋）。
## 視線的算法與 `Relief.line_blocked()`／`Stage3D.sight_blocked()` 相同（這裡自給自足，所以換一版地形也能量舊版）。
## **只量、不改規則**：模擬層的射程判定不看地形；要不要讓地形真的擋住是使用者的設計決定。

const CampaignData := preload("res://data/Campaign.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Maps := preload("res://data/Maps.gd")

const SAMPLES := 10
const ENDS := 0.08
const MARGIN := 0.02
const FOE_BODY_Y := 0.2


func _blocked(rel: Dictionary, a: Vector3, b: Vector3) -> bool:
	for k in range(1, SAMPLES + 1):
		var t := ENDS + (1.0 - 2.0 * ENDS) * float(k) / float(SAMPLES + 1)
		var p := a.lerp(b, t)
		if Relief.top_at(rel, Vector2i(floori(p.x), floori(p.z))) > p.y + MARGIN:
			return true
	return false


func _init() -> void:
	var tot_pairs := 0
	var tot_blocked := 0
	for i in CampaignData.count():
		var lv: Dictionary = CampaignData.at(i)
		var map: Dictionary = lv["map"]
		var rel := Relief.build(map)
		var path: Array = Maps.path_of(map)
		var towers: Array = []
		for op: Array in lv["demo"]:
			if String(op[0]) == "place":
				var def := NodeDefs.of(String(op[1]))
				if def.get("tower", false) and float(def.get("rof", 0.0)) > 0.0:
					towers.append([String(op[1]), op[2]])
		var pairs := 0
		var blocked := 0
		var heavy := 0   # 射程內超過一半的路徑格被擋的塔
		var dead := 0    # 超過九成被擋
		var per_tower := ""
		for tw: Array in towers:
			var type: String = tw[0]
			var cell: Vector2i = tw[1]
			var rng := Build.node_range(type, 0)
			var a := Vector3(float(cell.x) + 0.5, Relief.top_at(rel, cell) + Models.height_of(type, 0) * 0.85, float(cell.y) + 0.5)
			var n_in := 0
			var n_bl := 0
			for pc: Vector2i in path:
				if Vector2(pc - cell).length() > rng + 0.0001:
					continue
				var b := Vector3(float(pc.x) + 0.5, Relief.floor_at(rel, pc) + FOE_BODY_Y, float(pc.y) + 0.5)
				n_in += 1
				if _blocked(rel, a, b):
					n_bl += 1
			pairs += n_in
			blocked += n_bl
			if n_in > 0:
				var share := float(n_bl) / float(n_in)
				if share > 0.5:
					heavy += 1
				if share > 0.9:
					dead += 1
				per_tower += " %s%s:%d%%" % [type.substr(0, 3), str(cell), roundi(share * 100.0)]
		tot_pairs += pairs
		tot_blocked += blocked
		print("L%-2d %-8s 塔 %2d  射程內組合 %4d  被擋 %4d (%4.1f%%)  超過一半被擋的塔 %d  幾乎全擋 %d" % [
			i + 1, rel["biome"], towers.size(), pairs, blocked, 100.0 * blocked / maxf(pairs, 1), heavy, dead])
		if OS.has_environment("LOS_DETAIL"):
			print("      ", per_tower)
	print("合計 組合 %d  被擋 %d (%.1f%%)" % [tot_pairs, tot_blocked, 100.0 * tot_blocked / maxf(tot_pairs, 1)])
	# 全部可蓋的格 × 三種射程的塔：有多少格是「盲區」（射程內的路徑格超過一半被擋）。
	for ty: String in ["anchor", "prism", "longcall"]:
		var rng := Build.node_range(ty, 0)
		var cells_tot := 0
		var cells_with_path := 0
		var blind := 0
		var worst := 0.0
		var pairs_all := 0
		var pairs_bl := 0
		for i in CampaignData.count():
			var map: Dictionary = CampaignData.at(i)["map"]
			var rel := Relief.build(map)
			var path: Array = Maps.path_of(map)
			var on_path: Dictionary = {}
			for pc: Vector2i in path:
				on_path[pc] = true
			var size: Vector2i = map["size"]
			for y in size.y:
				for x in size.x:
					var cell := Vector2i(x, y)
					if on_path.has(cell):
						continue
					cells_tot += 1
					var a := Vector3(float(x) + 0.5, Relief.top_at(rel, cell) + Models.height_of(ty, 0) * 0.85, float(y) + 0.5)
					var n_in := 0
					var n_bl := 0
					for pc: Vector2i in path:
						if Vector2(pc - cell).length() > rng + 0.0001:
							continue
						var b := Vector3(float(pc.x) + 0.5, Relief.floor_at(rel, pc) + FOE_BODY_Y, float(pc.y) + 0.5)
						n_in += 1
						if _blocked(rel, a, b):
							n_bl += 1
					if n_in > 0:
						cells_with_path += 1
						pairs_all += n_in
						pairs_bl += n_bl
						if float(n_bl) / float(n_in) > 0.5:
							blind += 1
		print("所有可蓋的格 × %-8s（射程 %.0f）：有路徑在射程內的格 %d / %d，其中盲區（一半以上被擋）%d 格（%.1f%%）；全部組合被擋 %.1f%%" % [
			ty, rng, cells_with_path, cells_tot, blind, 100.0 * blind / maxf(cells_with_path, 1), 100.0 * pairs_bl / maxf(pairs_all, 1)])
	quit(0)
