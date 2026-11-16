package hxn.gpu;

import hxn.gpu.Descriptors.Color;

/** One command recorded in a pass. **/
enum Command {
	SetComputePipeline(pipeline:ComputePipeline);
	SetRenderPipeline(pipeline:RenderPipeline);
	SetBindGroup(index:Int, group:BindGroup);
	SetVertexBuffer(slot:Int, buffer:Buffer);
	SetIndexBuffer(buffer:Buffer, format:IndexFormat);
	Dispatch(x:Int, y:Int, z:Int);
	Draw(vertices:Int, instances:Int, firstVertex:Int);
	DrawIndexed(indices:Int, instances:Int, firstIndex:Int);
}

/** One step of a submission. Steps run in order. **/
enum Step {
	ComputeStep(commands:Array<Command>);
	/** A render pass, which clears `target` to `clear` first. **/
	RenderStep(target:Texture, clear:Color, commands:Array<Command>);
	CopyStep(source:Buffer, sourceOffset:Int, destination:Buffer, destinationOffset:Int, size:Int);
}
