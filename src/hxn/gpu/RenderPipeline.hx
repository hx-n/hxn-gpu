package hxn.gpu;

import hxn.gpu.Descriptors.BlendComponent;
import hxn.gpu.Descriptors.BlendState;
import hxn.gpu.Descriptors.VertexBufferLayout;
import hxnsl.Layout.EntryPoint;

class RenderPipeline extends Pipeline {
	public final vertex:EntryPoint;
	public final fragment:EntryPoint;
	public final format:TextureFormat;
	public final topology:Topology;
	public final vertexBuffers:Array<VertexBufferLayout>;

	/** How it blends into the target, or null to write its color as it is. **/
	public final blend:Null<BlendState>;

	@:allow(hxn.gpu) function new(device:GpuDevice, shader:ShaderModule, vertex:EntryPoint, fragment:EntryPoint, format:TextureFormat, topology:Topology,
			vertexBuffers:Array<VertexBufferLayout>, constants:Array<{key:String, value:Float}>, blend:Null<BlendState>) {
		super(device, shader, constants);
		this.vertex = vertex;
		this.fragment = fragment;
		this.format = format;
		this.topology = topology;
		this.vertexBuffers = vertexBuffers;
		this.blend = blend;
	}

	/**
		The blend state as the drivers take it: whether blending is on, then
		the operation and the source and destination factors of the color,
		then of the alpha, with WebGPU's defaults filled in. `Min` and `Max`
		default both factors to `One`, the only factor they take.
	**/
	@:allow(hxn.gpu)
	function blendCodes():Array<Int> {
		if (blend == null)
			return [0, BlendOperation.Add, BlendFactor.One, BlendFactor.Zero, BlendOperation.Add, BlendFactor.One, BlendFactor.Zero];
		return [1].concat(component(blend.color)).concat(component(blend.alpha));
	}

	static function component(c:BlendComponent):Array<Int> {
		var operation:BlendOperation = c.operation != null ? c.operation : BlendOperation.Add;
		var extreme = operation == BlendOperation.Min || operation == BlendOperation.Max;
		var source:BlendFactor = c.srcFactor != null ? c.srcFactor : BlendFactor.One;
		var destination:BlendFactor = c.dstFactor != null ? c.dstFactor : extreme ? BlendFactor.One : BlendFactor.Zero;
		return [operation, source, destination];
	}
}
