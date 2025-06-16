class_name FuncGodotGeometryGenerator extends RefCounted;

# TODO: REMOVE TEMPORARY SPECS BELOW
@warning_ignore_start("UNUSED_PARAMETER", "UNASSIGNED_VARIABLE", "UNUSED_VARIABLE")
const _SIGNATURE: String = "[GEN]";

# Namespacing
const M_EPSILON 	:= FuncGodotUtil.M_EPSILON;
const M_EPSILON2 	:= M_EPSILON * M_EPSILON;

const GroupData		:= FuncGodotParser.FuncGodotGroupData;
const EntityData 	:= FuncGodotParser.FuncGodotEntityData;
const BrushData 	:= FuncGodotParser.FuncGodotBrushData;
const PatchData 	:= FuncGodotParser.FuncGodotPatchData;
const FaceData 		:= FuncGodotParser.FuncGodotFaceData;

# Class members

var map_settings: FuncGodotMapSettings = null;
var entity_data: Array[EntityData];
var entity_meshes: Array[Mesh];
var entity_shapes: Array[Shape3D];
var texture_map: Dictionary[String, Material];

func _init(settings: FuncGodotMapSettings = null) -> void:
	map_settings = settings;
	return;

func build_texture_map() -> void:
	texture_map.clear();
	for entity in entity_data:
		for brush in entity.brushes:
			for face in brush.faces:
				if filter_face(face):
					continue;

				var tex: String = face.texture;
				if texture_map.has(tex):
					continue;

				var material := load(map_settings.base_texture_dir.path_join(face.texture) + ".tres");
				if !material:
					material = map_settings.default_material.duplicate(true);
					if material is StandardMaterial3D:
						material.albedo_texture = load(map_settings.base_texture_dir.path_join(face.texture) + ".png"); 

				texture_map[face.texture] = material;
	return;

## Patches

func sample_bezier_curve(controls: Array[Vector3], t: float) -> Vector3:
	var points: Array[Vector3] = controls.duplicate();
	for i in controls.size():
		for j in controls.size() - 1 - i:
			points[j] = points[j].lerp(points[j + 1], t)

	return points[0];

func sample_bezier_surface(controls: Array[Vector3], width: int, height: int, u: float, v: float) -> Vector3:
	var curve: Array[Vector3] = [];

	for x in range(width):
		var col: Array[Vector3] = [];
		for y in range(height):
			var idx := y * width + x;
			col.append(controls[idx]);

		curve.append(sample_bezier_curve(col, v));

	return sample_bezier_curve(curve, u);

# Generate patch triangle indices
func get_triangle_indices(width: int, height: int) -> Array[int]:
	var indices := [] as Array[int]
	if width < 2 or height < 2:
		return indices
	
	for row in range(height - 1):
		for col in range(width - 1):
			## First triangle of the square; top left, top right, bottom left
			indices.append(col + row * width)             
			indices.append((col + 1) + row * width)       
			indices.append(col + (row + 1) * width)      
			 
			## Second triangle of the square; top right, bottom right, bottom left
			indices.append((col + 1) + row * width)       
			indices.append((col + 1) + (row + 1) * width) 
			indices.append(col + (row + 1) * width)      
	return indices

func create_patch_mesh(data: Array[PatchData], mesh: Mesh):
	return;

## Brushes

func generate_brush_vertices(entity_index: int, brush_index: int) -> void:
	var entity: EntityData = entity_data[entity_index];
	var brush: BrushData = entity.brushes[brush_index];
	var face_count: int = brush.planes.size();	
	
	var do_phong: bool = entity.properties.get("_phong", 0) != 0;
	var phong_angle_str: String = entity.properties.get("_phong_angle", "89")
	var phong_angle: float = float(phong_angle_str) if phong_angle_str.is_valid_float() else 89.0
	
	# Check for valid planar intersections and clean up duplicates to prepare face geometry
	for f0 in face_count:
		var face: FaceData = brush.faces[f0];
		var plane: Plane = brush.planes[f0];
		for f1 in face_count:
			for f2 in face_count:
				var value: Variant = plane.intersect_3(brush.planes[f1], brush.planes[f2]);
				if value == null: 
					continue;	

				var vertex: Vector3 = value;
				if !FuncGodotUtil.is_point_in_convex_hull(brush.planes, vertex): 
					continue;
				
				var merged: bool = false;
				for f3 in range(f0):
					var other_face: FaceData = brush.faces[f3];
					for i in other_face.vertices.size():
						if other_face.vertices[i].distance_squared_to(vertex) < M_EPSILON2:
							vertex = other_face.vertices[i];
							merged = true;
							break;
					if merged: break;

				var normal := plane.normal;
				# TODO: phong here
				
				var uv: Vector2 = FuncGodotUtil.get_vertex_uv(vertex, face, Vector2i(64, 64));
				var tangent: PackedFloat32Array = FuncGodotUtil.get_face_tangent(face);
				var duplicate_index: int = -1;
				for i in face.vertices.size():
					if face.vertices[i] == vertex:
						duplicate_index = i;
						break;
			
				if duplicate_index < 0:
					face.vertices.append(vertex);
					face.normals.append(normal);
					face.vertex_uvs.append(uv);
					face.tangents.append_array(tangent);
				else:
					face.normals[duplicate_index] += normal;
	
	for face in brush.faces:
		for i in face.vertices.size():
			face.normals[i] = face.normals[i].normalized();
	return;

func generate_entity_vertices(entity_index: int) -> void:
	var entity: EntityData = entity_data[entity_index];
	for brush_index in entity.brushes.size():
		generate_brush_vertices(entity_index, brush_index);
	return;

func wind_entity_faces(entity_index: int) -> void:
	var entity: EntityData = entity_data[entity_index];
	for brush in entity.brushes:
		for face in brush.faces:
			face.wind();
	return;

# Perhaps merge with winding step
func index_entity_faces(entity_index: int) -> void:
	var entity: EntityData = entity_data[entity_index];
	for brush in entity.brushes:
		for face in brush.faces:
			face.index_vertices();
	return;

func filter_face(face: FaceData) -> bool:
	if (face.texture == map_settings.skip_texture
		|| face.texture == map_settings.clip_texture
	 	|| face.texture == map_settings.origin_texture
		):
		return true;
	return false;

func generate_entity_surfaces(entity_index: int) -> void:
	# MULTISURFACE SCOPE BEGIN 
	var entity: EntityData = entity_data[entity_index];
	var surfaces: Dictionary[String, Array] = {};

	for brush in entity.brushes:
		for face in brush.faces:
			if filter_face(face):
				continue;
			if !surfaces.has(face.texture):
				surfaces[face.texture] = [];
			surfaces[face.texture].append(face);
	
	var mesh := ArrayMesh.new();
	var arrays: Array;
	var faces: Array;
	
	var id_to_opengl_scaled: Callable = func(v: Vector3) -> Vector3:
		return FuncGodotUtil.id_to_opengl(v) * map_settings.scale_factor;

	for texture_name in surfaces.keys():
		# SURFACE SCOPE BEGIN
		arrays.resize(ArrayMesh.ARRAY_MAX);
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array();
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array();
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array();
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array();
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array();
		faces = surfaces[texture_name];

		var out_indices: Array;
		var index_offset: int = 0;

		for face in faces:
			# FACE SCOPE BEGIN
			if filter_face(face) || face.vertices.size() < 3:
				continue;

			var op_int_add: Callable = (
				func(a: int) -> int: return a + index_offset;
			);

			# Offset indices for place in new surface
			var vertices: Array = Array(face.vertices).map(id_to_opengl_scaled);
			var normals: Array = Array(face.normals).map(FuncGodotUtil.id_to_opengl);
			var indices: Array = Array(face.indices).map(op_int_add);

			# Append face data to surface array
			arrays[ArrayMesh.ARRAY_VERTEX].append_array(vertices);
			arrays[ArrayMesh.ARRAY_NORMAL].append_array(normals);
			arrays[ArrayMesh.ARRAY_TANGENT].append_array(face.tangents);
			arrays[ArrayMesh.ARRAY_TEX_UV].append_array(face.vertex_uvs);	
			arrays[ArrayMesh.ARRAY_INDEX].append_array(indices);
			index_offset += face.vertices.size();
			# FACE SCOPE END 

		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays);
		mesh.surface_set_name(mesh.get_surface_count() - 1, texture_name);
		mesh.surface_set_material(mesh.get_surface_count() - 1, texture_map[texture_name]);
		# SURFACE SCOPE END

	# MULTISURFACE SCOPE END 
	var shape: Shape3D;

	entity_meshes[entity_index] = mesh;
	entity_shapes[entity_index] = shape;
	return;

# Main build process
func build(
	entities: Array[EntityData], 	# Input array for entitiy data.
	groups: Array[GroupData],		# Input array for group data. Maybe unneeded.
	meshes: Array[Mesh],			# In/out array for entitity meshes.
	shapes: Array[Shape3D]			# In/out array for entity collision shapes.
	) -> Error:

	if meshes.size():	
		push_warning("Inout meshes array contained data; this will be overwritten!");
	if shapes.size(): 
		push_warning("Inout shapes array contained data; this will be overwritten!");
	
	var n_entities: int = entities.size();
	prints(_SIGNATURE, "Preparing %s entities" % n_entities);
	
	entity_data = entities;	
	entity_meshes = meshes;
	entity_shapes = shapes;
	
	meshes.clear();
	shapes.clear();
	meshes.resize(n_entities);	
	shapes.resize(n_entities);

	prints(_SIGNATURE, "Gathering materials...");
	build_texture_map();
	
	var task_id: int;
	# Brush geometry generation
	prints(_SIGNATURE, "Generating brush vertices");
	task_id = WorkerThreadPool.add_group_task(generate_entity_vertices, n_entities, -1, false, "Generate Brush Vertices")
	WorkerThreadPool.wait_for_group_task_completion(task_id);
	
	prints(_SIGNATURE, "Winding brush faces");
	task_id = WorkerThreadPool.add_group_task(wind_entity_faces, n_entities, -1, false, "Wind Brush Faces")
	WorkerThreadPool.wait_for_group_task_completion(task_id);
	
	prints(_SIGNATURE, "Index brush face vertices");
	task_id = WorkerThreadPool.add_group_task(index_entity_faces, n_entities, -1, false, "Index Brush Faces")
	WorkerThreadPool.wait_for_group_task_completion(task_id);
	
	prints(_SIGNATURE, "Generating surfaces");
	task_id = WorkerThreadPool.add_group_task(generate_entity_surfaces, n_entities, -1, false, "Generate Surfaces")
	WorkerThreadPool.wait_for_group_task_completion(task_id);

	prints(_SIGNATURE, "Geometry generation complete");
	return OK;

