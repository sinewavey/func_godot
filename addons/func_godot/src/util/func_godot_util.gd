## General-purpose utility functions namespaced to FuncGodot for compatibility
class_name FuncGodotUtil

const M_EPSILON: float = 0.008;

const VEC3_UP_ID		:= Vector3(0.0, 0.0, 1.0)
const VEC3_RIGHT_ID		:= Vector3(0.0, 1.0, 0.0)
const VEC3_FORWARD_ID 	:= Vector3(1.0, 0.0, 0.0)

## Print debug messages. True to print, false to ignore
const DEBUG : bool = true


## Const-predicated print function to avoid excess log spam. Print msg if [constant DEBUG] is `true`.
static func debug_print(msg) -> void:
	if(DEBUG):
		print(msg)

## Return a string that corresponds to the current OS's newline control character(s)
static func newline() -> String:
	if OS.get_name() == "Windows":
		return "\r\n"
	else:
		return "\n"

## Create a dictionary suitable for creating a category with name when overriding [method Object._get_property_list]
static func category_dict(name: String) -> Dictionary:
	return property_dict(name, TYPE_STRING, -1, "", PROPERTY_USAGE_CATEGORY)

## Creates a property with name and type from [enum @GlobalScope.Variant.Type].
## Optionally, provide hint from [enum @GlobalScope.PropertyHint] and corresponding hint_string, and usage from [enum @GlobalScope.PropertyUsageFlags].
static func property_dict(name: String, type: int, hint: int = -1, hint_string: String = "", usage: int = -1) -> Dictionary:
	var dict := {
		'name': name,
		'type': type
	}

	if hint != -1:
		dict['hint'] = hint

	if hint_string != "":
		dict['hint_string'] = hint_string

	if usage != -1:
		dict['usage'] = usage

	return dict

## Math

static func op_vec2_divi(lhs: Vector2, rhs: Vector2) -> Vector2:
	lhs.x /= rhs.x;
	lhs.y /= rhs.y;
	return lhs;

static func op_vec3_sum(lhs: Vector3, rhs: Vector3) -> Vector3: 
	return lhs + rhs;

static func op_vec3_avg(array: Array[Vector3]) -> Vector3:
	if !array.size():
		push_error("Cannot average empty Vector3 array!");
		return Vector3();
	return array.reduce(op_vec3_sum, Vector3()) / array.size();

static func op_swizzle_vec3_w(xyz: Vector3, w: float) -> PackedFloat32Array:
	var out := PackedFloat32Array();
	out.resize(4);
	for i in 3:
		out[i] = xyz[i];
	out[3] = w;
	return out;

# Conversion from id tech coordinate systems to Godot, from a top-down perspective.
static func id_to_opengl(vec: Vector3) -> Vector3: return Vector3(vec.y, vec.z, vec.x);

# Check if a point is inside a convex hull defined by a series of planes.
# Godot offers Plane::is_point_over, however it's useful to consider M_EPSILON.
static func is_point_in_convex_hull(planes: Array[Plane], vertex: Vector3) -> bool:
	for plane in planes:
		var distance: float = plane.normal.dot(vertex) - plane.d;
		if distance > M_EPSILON:
			return false;
	return true;

## Patch tools

# Returns the control points that defines a cubic curve for a equivalent input quadratic curve
# Godot has built in functions to handle curves, though they are handled in a cubic way.
static func elevate_quadratic(p0: Vector3, p1: Vector3, p2: Vector3) -> Array[Vector3]:
	return [p0, p0 + (2.0/3.0) * (p1 - p0), p2 + (2.0/3.0) * (p1 - p2), p2 ];

# Create a Curve3D and bake points.
static func create_curve(start: Vector3, control: Vector3, end: Vector3, bake_interval: float = 0.05) -> Curve3D:
	var ret := Curve3D.new();
	ret.bake_interval = bake_interval;
	update_ref_curve(ret, start, control, end, bake_interval);
	return ret;

# Update a Curve3D given quadratic inputs.
static func update_ref_curve(curve: Curve3D, p0: Vector3, p1: Vector3, p2: Vector3, bake_interval: float = 0.05) -> void:
	curve.clear_points();
	curve.bake_interval = bake_interval;
	curve.add_point(p0, (p1 - p0) * (2.0 / 3.0));
	curve.add_point(p1, (p1 - p0) * (1.0 / 3.0), (p2 - p1) * (1.0 / 3.0));
	curve.add_point(p2, (p2 - p1 * (2.0 / 3.0)));
	return

## Mesh data tooling

static func get_valve_uv(vertex: Vector3, face: FuncGodotParser.FuncGodotFaceData, texture_size: Vector2i) -> Vector2:
	var ret: Vector2;
	var scale := face.uv.get_scale();
	for i in 2:
		ret[i] = face.uv_axes[i].dot(vertex) + face.uv.origin[i];
		if !is_zero_approx(scale[i]):
			ret[i] /= scale[i];
		ret[i] /= texture_size[i];
	return ret;

static func get_quake_uv(vertex: Vector3, face: FuncGodotParser.FuncGodotFaceData, texture_size: Vector2i) -> Vector2:
	# Maybe incorrect
	var normal := face.plane.normal;
	var dx := absf(normal.dot(VEC3_RIGHT_ID));
	var dy := absf(normal.dot(VEC3_UP_ID));
	var dz := absf(normal.dot(VEC3_FORWARD_ID));
	
	var uv_out: Vector2;
	if (dy >= dx) && (dy >= dz):
		uv_out = Vector2(vertex.x, -vertex.y);
	elif (dx >= dy) && (dx >= dz):
		uv_out = Vector2(vertex.x, -vertex.z);
	elif (dz >= dy) && (dz >= dx):
		uv_out = Vector2(vertex.y, -vertex.z);
	
	return op_vec2_divi(uv_out, texture_size);

static func get_vertex_uv(vertex: Vector3, face: FuncGodotParser.FuncGodotFaceData, texture_size: Vector2i) -> Vector2:
	if face.uv_axes.size() >= 2:
		return get_valve_uv(vertex, face, texture_size);
	else:
		return get_quake_uv(vertex, face, texture_size);

static func get_valve_tangent(u: Vector3, v: Vector3, normal: Vector3) -> PackedFloat32Array:
	u = u.normalized();
	v = v.normalized();
	return op_swizzle_vec3_w(u, -signf(normal.cross(u).dot(v)));

static func get_quake_tangent(normal: Vector3, uv_y_scale: float, uv_rotation: float) -> PackedFloat32Array:
	var dx := normal.dot(VEC3_RIGHT_ID);
	var dy := normal.dot(VEC3_UP_ID);
	var dz := normal.dot(VEC3_FORWARD_ID);
	var dxa := absf(dx);
	var dya := absf(dy);
	var dza := absf(dz);
	var u_axis: Vector3;
	var v_sign: float = 0.0;
	
	if dya >= dxa and dya >= dza:
		u_axis = VEC3_FORWARD_ID; 
		v_sign = signf(dy);
	elif dxa >= dya and dxa >= dza:
		u_axis = VEC3_FORWARD_ID
		v_sign = -signf(dx);
	elif dza >= dya and dza >= dxa:
		u_axis = VEC3_RIGHT_ID; 
		v_sign = signf(dz);
		
	v_sign *= signf(uv_y_scale);
	u_axis = u_axis.rotated(normal, deg_to_rad(-uv_rotation) * v_sign);
	return op_swizzle_vec3_w(u_axis, v_sign);

static func get_face_tangent(face: FuncGodotParser.FuncGodotFaceData) -> PackedFloat32Array:
	if face.uv_axes.size() >= 2:
		return get_valve_tangent(face.uv_axes[0], face.uv_axes[1], face.plane.normal);
	else:
		return get_quake_tangent(face.plane.normal, face.uv.get_scale().y, face.uv.get_rotation());
