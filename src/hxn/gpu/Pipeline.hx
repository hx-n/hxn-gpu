package hxn.gpu;

import hxnsl.Layout.LayoutEntry;

/**
	Base class for compute and render pipelines, which compile a shader's entry points for
	the device.
**/
class Pipeline extends Resource {
	public final shader:ShaderModule;
	public final constants:Array<{key:String, value:Float}>;

	function new(device:GpuDevice, shader:ShaderModule, constants:Array<{key:String, value:Float}>) {
		super(device);
		this.shader = shader;
		this.constants = constants;
	}

	/** The layout entry of `binding` in bind group `group`. **/
	@:allow(hxn.gpu) function layoutEntry(group:Int, binding:Int):LayoutEntry {
		var layout = shader.code.layout;
		var found = group < layout.length ? Lambda.find(layout[group], e -> e.binding == binding) : null;
		if (found == null)
			throw '${shader.code.name} has no binding $binding in group $group';
		return found;
	}
}
