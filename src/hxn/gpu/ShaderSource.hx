package hxn.gpu;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import haxe.io.Bytes;
import hxnsl.Layout;

/** The code and tables an hxnsl shader class carries for the compiled-in backends. **/
typedef ShaderCode = {
	final name:String;
	final layout:Array<Array<LayoutEntry>>;
	final entryPoints:Array<EntryPoint>;
	final ?wgsl:String;
	final ?msl:String;
	final ?mslSlots:Array<MslEntry>;
	final ?metallib:() -> Null<Bytes>;
	final ?hlsl:String;
	final ?hlslSlots:Array<HlslBinding>;
	final ?dxil:String->Null<Bytes>;
	final ?spirv:() -> Bytes;
	final ?glslVertex:String;
	final ?glslFragment:String;
	final ?glslBindings:Array<GlslBindings>;
	/** Why the shader has no GLSL ES, if it has none. **/
	final ?glslMissing:String;
}

/**
	A shader for `GpuDevice.createShader`: an hxnsl shader class that implements
	`hxn.gpu.Shader`, such as `device.createShader(Tinted)`, or its `ShaderCode`.
**/
@:forward
abstract ShaderSource(ShaderCode) from ShaderCode to ShaderCode {
	@:from macro static function ofClass(e:Expr):ExprOf<ShaderSource> {
		var c = switch (Context.follow(Context.typeof(e))) {
			case TAnonymous(a):
				switch (a.get().status) {
					case AClassStatics(c): c.get();
					case _: null;
				}
			case _: null;
		};
		if (c == null)
			Context.error("a shader is an hxnsl shader class, such as Tinted", e.pos);
		var names = [for (f in c.statics.get()) f.name];
		if (names.indexOf("LAYOUT") < 0)
			Context.error('${c.name} is not an hxnsl shader: implement hxn.gpu.Shader', e.pos);
		var fields:Array<ObjectField> = [
			{field: "name", expr: macro $v{c.name}},
			{field: "layout", expr: macro $e.LAYOUT},
			{field: "entryPoints", expr: macro $e.ENTRY_POINTS}
		];
		function add(field:String, from:String, value:Expr)
			if (names.indexOf(from) >= 0)
				fields.push({field: field, expr: value});
		add("wgsl", "WGSL", macro $e.WGSL);
		add("msl", "MSL", macro $e.MSL);
		add("mslSlots", "MSL_SLOTS", macro $e.MSL_SLOTS);
		add("metallib", "metallib", macro() -> $e.metallib());
		add("hlsl", "HLSL", macro $e.HLSL);
		add("hlslSlots", "HLSL_SLOTS", macro $e.HLSL_SLOTS);
		add("dxil", "dxil", macro entry -> $e.dxil(entry));
		add("spirv", "spirv", macro() -> $e.spirv());
		add("glslVertex", "GLSL_VERTEX", macro $e.GLSL_VERTEX);
		add("glslFragment", "GLSL_FRAGMENT", macro $e.GLSL_FRAGMENT);
		add("glslBindings", "GLSL_BINDINGS", macro $e.GLSL_BINDINGS);
		add("glslMissing", "GLSL_MISSING", macro $e.GLSL_MISSING);
		var record = {expr: EObjectDecl(fields), pos: e.pos};
		return macro($record : hxn.gpu.ShaderSource.ShaderCode);
	}
}
