class_name FuncGodotParser extends RefCounted

class FuncGodotFaceData extends RefCounted:
	var vertices: PackedVector3Array = [];
	var indices: PackedInt32Array = [];
	var normals: PackedVector3Array = [];
	var tangents: PackedFloat32Array = [];
	var vertex_uvs: PackedVector2Array = [];
	var texture: String;
	var uv: Transform2D;
	var uv_axes: PackedVector3Array = [];
	var plane: Plane;

	func get_centroid() -> Vector3:
		return FuncGodotUtil.op_vec3_avg(vertices);
	
	# Old func_godot behavior.
	func get_basis() -> Vector3:
		if vertices.size() < 2:
			push_error("Cannot get winding basis without at least 2 vertices!");
			return Vector3.ZERO;
		return vertices[1] - vertices[0];
	
	func wind() -> void:
		var basis: Vector3 = get_basis();
		var centroid: Vector3 = get_centroid();
		var normal: Vector3 = plane.normal;		
		var cmp_winding_angle: Callable = (
			func(a: Vector3, b: Vector3) -> bool:
				var dir_a: Vector3 = a - centroid;
				var dir_b: Vector3 = b - centroid;
				var u: Vector3 = basis.normalized();
				var v: Vector3 = u.cross(normal).normalized()	
				var a_du: float = dir_a.dot(u);
				var a_dv: float = dir_a.dot(v);
				var b_du: float = dir_b.dot(u);
				var b_dv: float = dir_b.dot(v);	
				return atan2(a_dv, a_du) < atan2(b_dv, b_du);
		);
		
		var _vertices: Array[Vector3];
		_vertices.assign(vertices);
		_vertices.sort_custom(cmp_winding_angle);
		vertices = _vertices;
		return;
	
	func index_vertices() -> void:
		var tri_count: int = vertices.size() - 2;
		indices.resize(tri_count * 3);

		var index: int = 0;
		for i in tri_count:
			indices[index] = 0;
			indices[index + 1] = i + 1;
			indices[index + 2] = i + 2;
			index += 3;
		return;

	# New methods to be tested.
	func get_winding_basis() -> Basis:
		var basis: Basis;
		basis.z = plane.normal.normalized();
		basis.x = Vector3.RIGHT;
		if absf(basis.z.dot(basis.x)) > 0.9:
			basis.x = Vector3.FORWARD;
		basis.x = (basis.x - basis.z * basis.z.dot(basis.x)).normalized();
		basis.y = basis.z.cross(basis.x).normalized();	
		return basis;
	
	func basis_wind() -> void:
		var centroid := get_centroid();
		var basis := get_winding_basis();
		var cmp_winding_angle: Callable = (
			func(lhs: Vector3, rhs: Vector3) -> bool:
				var a := lhs - centroid;
				var b := rhs - centroid;
				return atan2(a.dot(basis.y), a.dot(basis.x)) < atan2(b.dot(basis.y), b.dot(basis.x));
		);

		var _vertices: Array[Vector3] = vertices;
		_vertices.sort_custom(cmp_winding_angle);
		vertices = _vertices;
		return;

class FuncGodotBrushData extends RefCounted:
	var planes: Array[Plane]
	var faces: Array[FuncGodotFaceData]

class FuncGodotPatchData extends RefCounted:
	var texture: String
	var size: PackedInt32Array
	var points: PackedVector3Array
	var uvs: PackedVector2Array

class FuncGodotGroupData extends RefCounted:
	enum GroupType { GROUP, LAYER, };
	var type: GroupType = GroupType.GROUP
	var id: int
	var name: String
	var parent: FuncGodotGroupData = null
	var parent_id: int = -1
	var omit: bool = false

class FuncGodotEntityData extends RefCounted:
	var properties: Dictionary = {}
	var brushes: Array[FuncGodotBrushData] = []
	var patches: Array[FuncGodotPatchData] = []
	var group: FuncGodotGroupData = null

## Parses the map file and returns an array of arrays. The first array is Array[FuncGodotEntityData], while the second array is Array[FuncGodotGroupData].
func parse_map_data(map_file: String) -> Array[Array]:
	var map_data: PackedStringArray = []
	var parse_data: Array[Array] = [[],[]]
	
	# Retrieve real path if needed
	if map_file.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(map_file);
		if !ResourceUID.has_id(uid):
			printerr("Error: failed to retrieve path for UID (%s)" % map_file)
			return []
		map_file = ResourceUID.get_id_path(uid);
	
	# Open the map file
	var file: FileAccess = FileAccess.open(map_file, FileAccess.READ)
	if not file:
		printerr("Error: Failed to open map file (" + map_file + ")")
		return []
	
	# Packed map file resources need to be accessed differently in exported projects.
	if map_file.ends_with(".import"):
		while not file.eof_reached():
			var line: String = file.get_line()
			if line.begins_with("path"):
				file.close()
				line = line.replace("path=", "");
				line = line.replace('"', '')
				var data: String = (load(line) as QuakeMapFile).map_data
				if data.is_empty():
					printerr("Error: Failed to open map file (" + line + ")")
					return []
				map_data = data.split("\n")
				break
	else:
		while not file.eof_reached():
			map_data.append(file.get_line())
	
	# Determine map type and parse data
	if map_file.contains(".map"):
		parse_data = _parse_qmap(map_data)
	elif map_file.contains(".vmf"):
		parse_data = _parse_vmf(map_data)
	
	# Determine group hierarchy
	var groups_data: Array[FuncGodotGroupData] = parse_data[1] as Array[FuncGodotGroupData]
	for g in groups_data:
		if g.parent_id != -1:
			for p in groups_data:
				if p.id == g.parent_id:
					g.parent = p
					break
	
	var entities_data: Array[FuncGodotEntityData] = parse_data[0] as Array[FuncGodotEntityData]
	for i in range(entities_data.size() - 1, -1, -1):
		var e: FuncGodotEntityData = entities_data[i]
		# Delete entities from omitted groups
		if e.group != null and e.group.omit == true:
			entities_data.remove_at(i)
			continue
	
	# Delete omitted groups
	for i in range(groups_data.size() - 1, -1, -1):
		if groups_data[i].omit == true:
			groups_data.remove_at(i)
	
	return parse_data

func _parse_qmap(map_data: PackedStringArray) -> Array[Array]:
	var entities_data: Array[FuncGodotEntityData] = []
	var groups_data: Array[FuncGodotGroupData] = []
	var ent: FuncGodotEntityData = null
	var brush: FuncGodotBrushData = null
	var patch: FuncGodotPatchData = null
	var scope: int = 0 # Scope level, to keep track of where we are in PatchDef parsing
	
	for line in map_data:
		line = line.replace("\t", "")
		
		#region START DATA
		# Start entity, brush, or patchdef
		if line.begins_with("{"):
			if not ent:
				ent = FuncGodotEntityData.new()
			else:
				if not patch:
					brush = FuncGodotBrushData.new()
				else:
					scope += 1
			continue
		#endregion
		
		#region COMMIT DATA
		# Commit entity or brush
		if line.begins_with("}"):
			if brush:
				ent.brushes.append(brush)
				brush = null
			elif patch:
				if scope:
					scope -= 1
				else:
					ent.patches.append(patch)
					patch = null
			else:
				# TrenchBroom layers and groups
				if ent.properties["classname"] == "func_group" and ent.properties.has("_tb_type"):
					# Merge TB Group / Layer structural brushes with worldspawn
					if entities_data.size():
						entities_data[0].brushes.append_array(ent.brushes)
					
					# Create group data
					var group: FuncGodotGroupData = FuncGodotGroupData.new()
					var props: Dictionary = ent.properties
					group.id = props["_tb_id"] as int
					if props["_tb_type"] == "_tb_layer":
						group.type = FuncGodotGroupData.GroupType.GROUP
						group.name = "layer_"
					else:
						group.name = "group_"
					group.name = group.name + str(group.id)
					if props["_tb_name"] != "Unnamed":
						group.name = group.name + "_" + (props["_tb_name"] as String).replace(" ", "_")
					if props.has("_tb_layer"):
						group.parent_id = props["_tb_layer"] as int
					if props.has("_tb_group"):
						group.parent_id = props["_tb_group"] as int
					if props.has("_tb_layer_omit_from_export"):
						group.omit = true
					
					# Commit group
					groups_data.append(group)
					
				# Commit entity
				else:
					entities_data.append(ent)
				ent = null
			continue
		#endregion
		
		#region PROPERTY DATA
		# Retrieve key value pairs
		if line.begins_with("\""):
			var tokens: PackedStringArray = line.split("\" \"")
			var key: String = tokens[0].trim_prefix("\"")
			var value: String = tokens[1].trim_suffix("\"")
			ent.properties[key] = value
		#endregion
		
		#region BRUSH DATA
		if brush and line.begins_with("("):
			line = line.replace("(","")
			var tokens: PackedStringArray = line.split(" ) ")
			
			# Retrieve plane data
			var points: PackedVector3Array
			points.resize(3) 
			for i in 3:
				tokens[i] = tokens[i].trim_prefix("(")
				var pts: PackedFloat64Array = tokens[i].split_floats(" ", false)
				var point: Vector3 = Vector3(pts[0], pts[1], pts[2])
				points[i] = point

			var plane := Plane(points[0], points[1], points[2]);
			brush.planes.append(plane);

			var face: FuncGodotFaceData = FuncGodotFaceData.new()
			face.plane = plane;

			# Retrieve texture data
			var tex: String = String()
			if tokens[3].begins_with("\""): # textures with spaces get surrounded by double quotes
				tex = tokens[3].split("\"")[0]
			else:
				tex = tokens[3].split(" ")[0]
			face.texture = tex
			
			# Retrieve UV data
			var uv: Transform2D = Transform2D.IDENTITY
			tokens = tokens[3].lstrip(tex + " ").split(" ] ")
			# Valve 220
			if tokens.size() > 1:
				var coords: PackedFloat64Array
				for i in 2: # Save Axis Vectors separately
					coords = tokens[i].trim_prefix("[ ").split_floats(" ", false)
					face.uv_axes.append(Vector3(coords[0], coords[1], coords[2]))
					uv.origin[i] = coords[3]
				coords = tokens[2].split_floats(" ", false)
				var r: float = deg_to_rad(coords[0])
				uv.x = Vector2(cos(r), -sin(r)) * coords[1]
				uv.y = Vector2(sin(r), cos(r)) * coords[2]
			# Quake Standard
			else:
				var coords: PackedFloat64Array = tokens[0].split_floats(" ", false)
				uv.origin = Vector2(coords[0], coords[1])
				var r: float = deg_to_rad(coords[2])
				uv.x = Vector2(cos(r), -sin(r)) * coords[3]
				uv.y = Vector2(sin(r), cos(r)) * coords[4]
			face.uv = uv
			
			brush.faces.append(face)
			continue
		#endregion
	
		#region PATCH DATA
		if patch:
			if line.begins_with("("):
				line = line.replace("( ","")
				# Retrieve patch control points
				if patch.size:
					var tokens: PackedStringArray = line.replace("(", "").split(" )", false)
					for i in tokens.size():
						var subtokens: PackedFloat64Array = tokens[i].split_floats(" ", false)
						patch.points.append(Vector3(subtokens[0], subtokens[1], subtokens[2]))
						patch.uvs.append(Vector2(subtokens[3], subtokens[4]))
				# Retrieve patch size
				else:
					var tokens: PackedStringArray = line.replace(")","").split(" ", false)
					patch.size.resize(tokens.size())
					for i in tokens.size():
						patch.size[i] = tokens[i].to_int()
			# Retrieve patch texture
			elif not line.begins_with(")"):
				patch.texture = line.replace("\"","")
		
		if line.begins_with("patchDef"):
			brush = null
			patch = FuncGodotPatchData.new()
			continue
		#endregion
	
	#region ASSIGN GROUPS
	for e in entities_data:
		var group_id: int = -1
		if e.properties.has("_tb_layer"):
			group_id = e.properties["_tb_layer"] as int
		elif e.properties.has("_tb_group"):
			group_id = e.properties["_tb_group"] as int
		if group_id != -1:
			for g in groups_data:
				if g.id == group_id:
					e.group = g
					break
	#endregion
	
	return [entities_data, groups_data]

func _parse_vmf(map_data: PackedStringArray) -> Array[Array]:
	var entities_data: Array[FuncGodotEntityData] = []
	var groups_data: Array[FuncGodotGroupData] = []
	var ent: FuncGodotEntityData = null
	var brush: FuncGodotBrushData = null
	var group: FuncGodotGroupData = null
	var group_parent_hierarchy: Array[FuncGodotGroupData] = []
	var scope: int = 0
	
	for line in map_data:
		line = line.replace("\t", "")
		
		#region START DATA
		if line.begins_with("entity") or line.begins_with("world"):
			ent = FuncGodotEntityData.new()
			continue
		if line.begins_with("solid"):
			brush = FuncGodotBrushData.new()
			continue
		if brush and line.begins_with("{"):
			scope += 1
			continue
		if line == "visgroup":
			if group != null:
				groups_data.append(group)
				group_parent_hierarchy.append(group)
			group = FuncGodotGroupData.new()
			if group_parent_hierarchy.size():
				group.parent = group_parent_hierarchy.back()
				group.parent_id = group.parent.id
			continue
		#endregion
		
		#region COMMIT DATA
		if line.begins_with("}"):
			if scope > 0:
				scope -= 1
			if not scope:
				if brush:
					ent.brushes.append(brush)
					brush = null
				elif ent:
					entities_data.append(ent)
					ent = null
				elif group:
					groups_data.append(group)
					group = null
				elif group_parent_hierarchy.size():
					group_parent_hierarchy.pop_back()
			continue
		#endregion
		
		# Retrieve key value pairs
		if (ent or group) and line.begins_with("\""):
			var tokens: PackedStringArray = line.split("\" \"")
			var key: String = tokens[0].trim_prefix("\"")
			var value: String = tokens[1].trim_suffix("\"")
			
			#region BRUSH DATA
			if brush:
				if scope > 1:
					var uv: Transform2D = Transform2D.IDENTITY
					match key:
						"plane":
							tokens = value.replace("(", "").split(")", false)
							var points: PackedVector3Array
							points.resize(3) 
							for i in 3:
								tokens[i] = tokens[i].trim_prefix("(")
								var pts: PackedFloat64Array = tokens[i].split_floats(" ", false)
								var point: Vector3 = Vector3(pts[0], pts[1], pts[2])
								points[i] = point
							brush.planes.append(Plane(points[0], points[1], points[2]))
							brush.faces.append(FuncGodotFaceData.new())
							continue
						"material":
							if brush.faces.size():
								brush.faces[-1].texture = value
							continue
						"uaxis", "vaxis":
							if brush.faces.size():
								value = value.replace("[", "")
								var vals: PackedFloat64Array = value.replace("]", "").split_floats(" ", false)
								brush.faces[-1].uv_axes.append(Vector3(vals[0], vals[1], vals[2]))
								if key.begins_with("u"):
									uv.origin.x = vals[3]
									uv.x *= vals[4]
								else:
									uv.origin.y = vals[3]
									uv.y *= vals[4]
							continue
						"rotation":
							if brush.faces.size():
								var r: float = deg_to_rad(value.to_float())
								# Can we rely on uvaxis always coming before rotation?
								uv.x = Vector2(cos(r), -sin(r)) * uv.x.length()
								uv.y = Vector2(sin(r), cos(r)) * uv.y.length()
								brush.faces[-1].uv = uv
							continue
						"visgroupid":
							# Don't put worldspawn into a group
							if entities_data.size():
								# Only nodes can be organized into groups in the SceneTree, so only use the first brush's group
								if not ent.properties.has(key):
									ent.properties[key] = value
			#endregion
			elif ent:
				ent.properties[key] = value
				continue
			elif group:
				if key == "name":
					group.name = "group_%s_" + value
				elif key == "visgroupid":
					group.id = value.to_int()
					group.name = group.name % value
					group.name = group.name.replace(" ", "_")
				continue
	
	#region ASSIGN GROUPS
	for e in entities_data:
		if e.properties.has("visgroupid"):
			var group_id: int = e.properties["visgroupid"] as int
			for g in groups_data:
				if g.id == group_id:
					e.group = g
					break
	#endregion
	
	return [entities_data, groups_data]

