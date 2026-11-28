package hxn.gpu;

#if macro
import haxe.macro.Context;

/** Checks at compile time that the drivers given with `-lib` are versions hxn-gpu supports. **/
class Setup {
	/** The oldest driver version hxn-gpu supports in each major.minor series. **/
	static final supported = [
		"hxn-gpu-metal" => "0.2.3",
		"hxn-gpu-vulkan" => "0.3.4",
		"hxn-gpu-d3d12" => "0.2.3",
		"hxn-gpu-gles" => "0.3.3",
		"hxn-gpu-webgpu" => "0.3.6",
		"hxn-gpu-webgl2" => "0.3.5"
	];

	public static function check():Void {
		for (lib => oldest in supported) {
			var version = Context.definedValue(lib);
			if (version == null)
				continue;
			// A haxelib dev checkout defines the library without a version.
			if (version == "1" || version == "")
				continue;
			var want = oldest.split(".");
			var have = version.split(".");
			var series = want[0] + "." + want[1];
			var patch = have.length > 2 ? Std.parseInt(have[2]) : 0;
			if (have[0] != want[0] || have[1] != want[1] || patch == null || patch < Std.parseInt(want[2]))
				Context.fatalError('hxn-gpu supports $lib $series.x from $oldest, not $version: install it with haxelib install $lib', Context.currentPos());
		}
		// The GLES and WebGL2 backends share one implementation, so only one of the two
		// drivers can be given.
		if (Context.defined("hxn-gpu-gles") && Context.defined("hxn-gpu-webgl2"))
			Context.fatalError("hxn-gpu-gles and hxn-gpu-webgl2 cannot be given together: GLES is for native programs, WebGL2 for the browser", Context.currentPos());
		// iOS has no managed storage, so Metal textures there are shared.
		var triple = Context.definedValue("hxn_triple");
		if (Context.defined("iphoneos") || Context.defined("iphonesim") || (triple != null && triple.indexOf("apple-ios") >= 0))
			haxe.macro.Compiler.define("hxn_gpu_ios");
		// -D hxn_gpu_backend names backends this program compiles in.
		var named = Context.definedValue("hxn_gpu_backend");
		if (named != null && named != "1")
			for (part in named.split(",")) {
				var name = StringTools.trim(part).toLowerCase();
				if (!supported.exists('hxn-gpu-$name'))
					Context.fatalError('-D hxn_gpu_backend names $name: the backends are metal, vulkan, d3d12, gles, webgpu and webgl2', Context.currentPos());
				if (!Context.defined('hxn-gpu-$name'))
					Context.fatalError('-D hxn_gpu_backend names $name, which is not compiled in: add -lib hxn-gpu-$name', Context.currentPos());
			}
		if (!Context.defined("hxnsl"))
			Context.fatalError("hxn-gpu needs hxnsl: add -lib hxnsl", Context.currentPos());
	}
}
#end
