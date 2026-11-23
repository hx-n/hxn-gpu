package hxn.gpu;

import hxn.gpu.Command.Step;
import hxn.gpu.Descriptors.Color;

/**
	Records passes and copies for `GpuDevice.submit`. Only one pass can be open at a time.
**/
class CommandEncoder {
	final device:GpuDevice;
	@:allow(hxn.gpu) final steps:Array<Step> = [];
	var open = false;
	var submitted = false;

	@:allow(hxn.gpu) function new(device:GpuDevice) {
		this.device = device;
	}

	public function beginComputePass():ComputePass {
		device.need(Compute, "a compute pass");
		var pass = new ComputePass(this);
		start(ComputeStep(pass.commands));
		return pass;
	}

	/**
		Begins a render pass into `target`. The pass first clears `target` to `clear`,
		which defaults to transparent black. With `keep`, it draws over what `target`
		holds instead, for a layer drawn in a pass of its own.
	**/
	public function beginRenderPass(target:Texture, ?clear:Color, ?keep:Bool = false):RenderPass {
		if (!target.usage.has(RenderTarget))
			throw "a render pass target needs TextureUsage.RenderTarget";
		if (keep && clear != null)
			throw "a render pass either clears its target or keeps it, not both";
		var pass = new RenderPass(this, target);
		start(RenderStep(target, keep ? null : clear != null ? clear : {r: 0, g: 0, b: 0, a: 0}, pass.commands));
		return pass;
	}

	public function copyBufferToBuffer(source:Buffer, sourceOffset:Int, destination:Buffer, destinationOffset:Int, size:Int):Void {
		device.need(BufferCopies, "copyBufferToBuffer");
		if (!source.usage.has(CopySrc) || !destination.usage.has(CopyDst))
			throw "copyBufferToBuffer needs BufferUsage.CopySrc on the source and CopyDst on the destination";
		if (sourceOffset % 4 != 0 || destinationOffset % 4 != 0 || size % 4 != 0)
			throw "copyBufferToBuffer offsets and size are multiples of 4";
		if (sourceOffset + size > source.size || destinationOffset + size > destination.size)
			throw "copyBufferToBuffer goes past the end of a buffer";
		writable();
		if (open)
			throw "end the open pass before a copy";
		steps.push(CopyStep(source, sourceOffset, destination, destinationOffset, size));
	}

	function start(step:Step):Void {
		writable();
		if (open)
			throw "end the open pass before beginning another";
		open = true;
		steps.push(step);
	}

	@:allow(hxn.gpu) function ended():Void
		open = false;

	@:allow(hxn.gpu) function finish():Array<Step> {
		writable();
		if (open)
			throw "end the open pass before submitting";
		submitted = true;
		return steps;
	}

	@:allow(hxn.gpu) function writable():Void
		if (submitted)
			throw "this command encoder was submitted; make a new one";
}
