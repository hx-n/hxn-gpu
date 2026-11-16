package hxn.gpu;

import hxn.gpu.Command;

class RenderPass {
	final encoder:CommandEncoder;
	final target:Texture;
	@:allow(hxn.gpu) final commands:Array<Command> = [];
	var pipeline:Null<RenderPipeline>;
	var indexed = false;
	var ended = false;

	@:allow(hxn.gpu) function new(encoder:CommandEncoder, target:Texture) {
		this.encoder = encoder;
		this.target = target;
	}

	public function setPipeline(pipeline:RenderPipeline):Void {
		recording();
		if (pipeline.format != target.format)
			throw 'the pipeline renders ${pipeline.format}, the target is ${target.format}';
		this.pipeline = pipeline;
		commands.push(SetRenderPipeline(pipeline));
	}

	public function setBindGroup(index:Int, group:BindGroup):Void {
		recording();
		if (group.group != index)
			throw 'bind group ${group.group} set at index $index';
		commands.push(SetBindGroup(index, group));
	}

	public function setVertexBuffer(slot:Int, buffer:Buffer):Void {
		recording();
		if (!buffer.usage.has(Vertex))
			throw "a vertex buffer needs BufferUsage.Vertex";
		commands.push(SetVertexBuffer(slot, buffer));
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
