package hxn.gpu;

import hxn.gpu.ShaderSource.ShaderCode;
import hxnsl.Layout.EntryPoint;

/** An hxnsl shader loaded by the device's driver. **/
class ShaderModule extends Resource {
	public final code:ShaderCode;

	@:allow(hxn.gpu) function new(device:GpuDevice, code:ShaderCode) {
		super(device);
		this.code = code;
	}

	/** The entry point named `name`, or the shader's only one for `stage` (vertex, fragment or compute). **/
	@:allow(hxn.gpu) function entryPoint(name:Null<String>, stage:String):EntryPoint {
		var found = [for (e in code.entryPoints) if (e.stage == stage && (name == null || e.name == name)) e];
		if (found.length == 1)
			return found[0];
		if (found.length == 0)
			throw name == null ? '${code.name} has no $stage entry point' : '${code.name} has no $stage entry point $name';
		throw '${code.name} has ${found.length} $stage entry points: name one';
	}
}
