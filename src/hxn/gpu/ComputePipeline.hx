package hxn.gpu;

import hxnsl.Layout.EntryPoint;

class ComputePipeline extends Pipeline {
	public final entryPoint:EntryPoint;

	@:allow(hxn.gpu) function new(device:GpuDevice, shader:ShaderModule, entryPoint:EntryPoint, constants:Array<{key:String, value:Float}>) {
		super(device, shader, constants);
		this.entryPoint = entryPoint;
	}
}
