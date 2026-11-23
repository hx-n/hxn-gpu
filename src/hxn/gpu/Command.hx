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

/**
	The attachments of a render pass, as the drivers take them. Each color
	target is cleared to `clear` first, or drawn over when `clear` is null.
	The depth target, when there is one, is cleared to `clear` first, or
	tested against when `clear` is null.
**/
typedef PassTargets = {
	final colors:Array<{target:Texture, clear:Null<Color>}>;
	final depth:Null<{target:Texture, clear:Null<Float>}>;
}

/** One step of a submission. Steps run in order. **/
enum Step {
	ComputeStep(commands:Array<Command>);
	/**
		Records one render pass into `targets`. Each pass starts with a
		viewport and a scissor that cover the whole of its targets.
	**/
	RenderStep(targets:PassTargets, commands:Array<Command>);
	CopyStep(source:Buffer, sourceOffset:Int, destination:Buffer, destinationOffset:Int, size:Int);
}
