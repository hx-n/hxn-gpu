package hxn.gpu;

import hxn.gpu.Command.Step;
import hxn.gpu.Descriptors.Color;
import hxn.gpu.Descriptors.RenderPassDescriptor;

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
		return beginRenderPassWith({colors: [{target: target, clear: clear, keep: keep}]});
	}

	/**
		Begins a render pass into the color attachments and the depth attachment
		of `descriptor`. Every attachment has the same size, and a pipeline set in
		the pass has one target for each color attachment, in the same formats,
		and the depth attachment's format.
	**/
	public function beginRenderPassWith(descriptor:RenderPassDescriptor):RenderPass {
		var colors = descriptor.colors;
		if (colors.length == 0)
			throw "a render pass has at least one color attachment";
		var first = colors[0].target;
		var attached:Array<{target:Texture, clear:Null<Color>}> = [];
		for (c in colors) {
			if (!c.target.usage.has(RenderTarget))
				throw "a render pass target needs TextureUsage.RenderTarget";
			if (c.target.format.isDepth())
				throw 'a color attachment has a color format, not ${c.target.format}';
			if (c.keep == true && c.clear != null)
				throw "a render pass either clears its target or keeps it, not both";
			if (c.target.width != first.width || c.target.height != first.height)
				throw 'the attachments of a render pass have one size, not ${first.width}x${first.height} and ${c.target.width}x${c.target.height}';
			attached.push({target: c.target, clear: c.keep == true ? null : c.clear != null ? c.clear : {r: 0, g: 0, b: 0, a: 0}});
		}
		var depth = descriptor.depth;
		var depthTarget:Null<{target:Texture, clear:Null<Float>}> = null;
		if (depth != null) {
			if (!depth.target.format.isDepth())
				throw 'a depth attachment has a depth format, not ${depth.target.format}';
			if (!depth.target.usage.has(RenderTarget))
				throw "a depth attachment needs TextureUsage.RenderTarget";
			if (depth.keep == true && depth.clear != null)
				throw "a render pass either clears its depth or keeps it, not both";
			if (depth.target.width != first.width || depth.target.height != first.height)
				throw 'the attachments of a render pass have one size, not ${first.width}x${first.height} and ${depth.target.width}x${depth.target.height}';
			depthTarget = {target: depth.target, clear: depth.keep == true ? null : depth.clear != null ? depth.clear : 1.0};
		}
		var targets:hxn.gpu.Command.PassTargets = {colors: attached, depth: depthTarget};
		var pass = new RenderPass(this, targets);
		start(RenderStep(targets, pass.commands));
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
