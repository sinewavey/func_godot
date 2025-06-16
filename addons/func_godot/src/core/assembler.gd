@tool class_name FuncGodotAssembler extends Node3D;

const GroupData		:= FuncGodotParser.FuncGodotGroupData;
const EntityData 	:= FuncGodotParser.FuncGodotEntityData;

const _SIGNATURE: String = "[ASM]";

signal build_failed;
signal build_complete;

@export_tool_button("Build Map") var build_fnc: Callable = build;
@export_tool_button("Clear") var clear_fnc: Callable = clear_children;

@export_category("Map")
@export_file("*.map") var map_file: String = "";
@export var map_settings: FuncGodotMapSettings

@export_category("Build")
@export_flags("Unwrap UV2:1","Block Thread:2", "Show Profiling Info:4") var build_flags: int = 0;

func fail_build(reason: String, notify: bool = false) -> void:
	push_error(_SIGNATURE, reason);
	if notify:
		build_failed.emit();	
	return;

func clear_children() -> void:
	for child in get_children():
		remove_child(child);
		child.queue_free();
	return;

func verify() -> bool:
	if map_file.is_empty():
		fail_build("Cannot build empty map file.");
		return false;

	if !FileAccess.file_exists(map_file):
		fail_build("Map file %s does not exist." % map_file);
		return false;

	return true;

func build() -> void:
	prints(_SIGNATURE, "Building...");
	clear_children();

	if !verify():
		fail_build("Verification failed; aborting map build", true);
		return;
	
	# Parse and collect map data
	var parser := FuncGodotParser.new();
	var parse: Array[Array] = parser.parse_map_data(map_file);
	var entities: Array[EntityData] = parse[0];
	var groups: Array[GroupData] = parse[1];
	
	# Free up some memory now that we have the data
	parser = null;
	parse = [];

	# Retrieve geometry
	var entity_meshes: Array[Mesh] = [];
	var entity_collision_shapes: Array[Shape3D] = [];
	var generator := FuncGodotGeometryGenerator.new(map_settings);
	
	generator.build(entities, groups, entity_meshes, entity_collision_shapes);
	
	# Iteration variables
	var scene_root: Node = get_tree().edited_scene_root;
	var entity_node: Node = null;
	var entity_mesh: Mesh = null;
	var entity_collision_shape: Shape3D = null;
	
	for entity_index in entities.size():
		var entity_name: String = "entity_%s" % entity_index;

		entity_node = Node3D.new();
		prints(_SIGNATURE, "Assembling entity", entity_name);

		entity_mesh = entity_meshes[entity_index];
		entity_collision_shape = entity_collision_shapes[entity_index];	
		
		var mi: MeshInstance3D = null;
		var cs: CollisionShape3D = null;

		if entity_mesh:
			mi = MeshInstance3D.new();
			mi.mesh = entity_mesh;
			entity_node.add_child(mi);
			mi.name = entity_name + "_mesh_instance";

		if entity_collision_shape:
			cs = CollisionShape3D.new();
			cs.shape = entity_collision_shape;
			entity_node.add_child(cs);
			cs.name = entity_name + "_collision_shape";
		
		add_child(entity_node);

		entity_node.name = entity_name + "_" + entities[entity_index].properties.classname;
		entity_node.set_owner(scene_root);
		
		if mi:
			mi.set_owner(scene_root);
		
		if cs:
			cs.set_owner(scene_root);

	
	prints(_SIGNATURE, "Build complete");
	build_complete.emit();
	return;


