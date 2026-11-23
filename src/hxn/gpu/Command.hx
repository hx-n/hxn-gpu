package hxn.gpu;

import hxn.gpu.Descriptors.Color;

/** One command recorded in a pass. **/
enum Command {
	SetComputePipeline(pipeline:ComputePipeline);
	SetRenderPipeline(pipeline:RenderPipeline);
	SetBindGroup(index:Int, group:BindGroup);
	SetVertexBuffer(slot:Int, buffer:Buffer, offset:Int);
	SetIndexBuffer(buffer:Buffer, format:IndexFormat);
	/** The rectangle is in pixels from the target's top-left corner. **/
	SetViewport(x:Float, y:Float, width:Float, height:Float);
	/** The rectangle is in pixels from the target's top-left corner. **/
	SetScissor(x:Int, y:Int, width:Int, height:Int);
	Dispatch(x:Int, y:Int, z:Int);
	Draw(vertices:Int, instances:Int, firstVertex:Int);
	DrawIndexed(indices:Int, instances:Int, firstIndex:Int);
}

/** One step of a submission. Steps run in order. **/
enum Step {
	ComputeStep(commands:Array<Command>);
	/**
		Records one render pass. The pass first clears `target` to `clear`, or
		draws over what `target` holds when `clear` is null. Each pass starts
		with a viewport and a scissor that cover the whole target.
	**/
	RenderStep(target:Texture, clear:Null<Color>, commands:Array<Command>);
	CopyStep(source:Buffer, sourceOffset:Int, destination:Buffer, destinationOffset:Int, size:Int);
}
