package hxn.gpu;

import hxn.gpu.Command;

class ComputePass {
	final encoder:CommandEncoder;
	@:allow(hxn.gpu) final commands:Array<Command> = [];
	var pipeline:Null<ComputePipeline>;
	var ended = false;

	@:allow(hxn.gpu) function new(encoder:CommandEncoder) {
		this.encoder = encoder;
	}

	public function setPipeline(pipeline:ComputePipeline):Void {
		recording();
		this.pipeline = pipeline;
		commands.push(SetComputePipeline(pipeline));
	}

	public function setBindGroup(index:Int, group:BindGroup):Void {
		recording();
		if (group.group != index)
			throw 'bind group ${group.group} set at index $index';
		commands.push(SetBindGroup(index, group));
	}

	/** Dispatches an `x` by `y` by `z` grid of workgroups. **/
	public function dispatch(x:Int, ?y:Int = 1, ?z:Int = 1):Void {
		recording();
		if (pipeline == null)
			throw "dispatch needs setPipeline first";
		commands.push(Dispatch(x, y, z));
	}

	public function end():Void {
		recording();
		ended = true;
		encoder.ended();
	}

	function recording():Void {
		if (ended)
			throw "this compute pass has ended";
		encoder.writable();
	}
}
