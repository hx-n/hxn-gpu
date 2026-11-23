package hxn.gpu;

import hxn.gpu.Command;

class RenderPass {
	final encoder:CommandEncoder;
	final targets:PassTargets;
	// The size that every attachment has.
	final width:Int;
	final height:Int;
	@:allow(hxn.gpu) final commands:Array<Command> = [];
	var pipeline:Null<RenderPipeline>;
	var indexed = false;
	var ended = false;

	@:allow(hxn.gpu) function new(encoder:CommandEncoder, targets:PassTargets) {
		this.encoder = encoder;
		this.targets = targets;
		width = targets.colors[0].target.width;
		height = targets.colors[0].target.height;
	}

	public function setPipeline(pipeline:RenderPipeline):Void {
		recording();
		var formats = [for (c in targets.colors) c.target.format];
		var wanted = [for (t in pipeline.targets) t.format];
		if (formats.join(",") != wanted.join(","))
			throw 'the pipeline renders ${wanted.join(", ")}, and the pass\'s targets are ${formats.join(", ")}';
		var depth = targets.depth != null ? targets.depth.target.format : null;
		var pipelineDepth = pipeline.depth != null ? pipeline.depth.format : null;
		if (depth != pipelineDepth)
			throw 'the pipeline tests depth in ${pipelineDepth != null ? '$pipelineDepth' : "no target"}, and the pass has ${depth != null ? 'a $depth' : "no"} depth target';
		this.pipeline = pipeline;
		commands.push(SetRenderPipeline(pipeline));
	}

	public function setBindGroup(index:Int, group:BindGroup):Void {
		recording();
		if (group.group != index)
			throw 'bind group ${group.group} set at index $index';
		commands.push(SetBindGroup(index, group));
	}

	/**
		Reads vertex buffer `slot` from `buffer`, starting `offset` bytes in. One buffer
		can then hold several batches of instances.
	**/
	public function setVertexBuffer(slot:Int, buffer:Buffer, ?offset:Int = 0):Void {
		recording();
		if (!buffer.usage.has(Vertex))
			throw "a vertex buffer needs BufferUsage.Vertex";
		if (offset < 0 || offset % 4 != 0 || offset >= buffer.size)
			throw 'a vertex buffer offset is a multiple of 4 inside the buffer, not $offset in ${buffer.size} bytes';
		commands.push(SetVertexBuffer(slot, buffer, offset));
	}

	/**
		Maps clip space onto the rectangle `x`, `y`, `width`, `height` of the target, in
		pixels from its top-left corner. Each pass starts with the whole target.
	**/
	public function setViewport(x:Float, y:Float, width:Float, height:Float):Void {
		recording();
		if (x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > this.width || y + height > this.height)
			throw 'a viewport lies inside the ${this.width}x${this.height} target, not at $x, $y, ${width}x$height';
		commands.push(SetViewport(x, y, width, height));
	}

	/**
		Draws only inside the rectangle `x`, `y`, `width`, `height` of the target, in
		pixels from its top-left corner. Each pass starts with the whole target.
	**/
	public function setScissorRect(x:Int, y:Int, width:Int, height:Int):Void {
		recording();
		if (x < 0 || y < 0 || width < 0 || height < 0 || x + width > this.width || y + height > this.height)
			throw 'a scissor rectangle lies inside the ${this.width}x${this.height} target, not at $x, $y, ${width}x$height';
		commands.push(SetScissor(x, y, width, height));
	}

	public function setIndexBuffer(buffer:Buffer, format:IndexFormat):Void {
		recording();
		buffer.device.need(IndexedDraws, "setIndexBuffer");
		if (!buffer.usage.has(Index))
			throw "an index buffer needs BufferUsage.Index";
		indexed = true;
		commands.push(SetIndexBuffer(buffer, format));
	}

	public function draw(vertices:Int, ?instances:Int = 1, ?firstVertex:Int = 0):Void {
		recording();
		if (pipeline == null)
			throw "draw needs setPipeline first";
		commands.push(Draw(vertices, instances, firstVertex));
	}

	public function drawIndexed(indices:Int, ?instances:Int = 1, ?firstIndex:Int = 0):Void {
		recording();
		if (pipeline == null)
			throw "drawIndexed needs setPipeline first";
		if (!indexed)
			throw "drawIndexed needs setIndexBuffer first";
		commands.push(DrawIndexed(indices, instances, firstIndex));
	}

	public function end():Void {
		recording();
		ended = true;
		encoder.ended();
	}

	function recording():Void {
		if (ended)
			throw "this render pass has ended";
		encoder.writable();
	}
}
