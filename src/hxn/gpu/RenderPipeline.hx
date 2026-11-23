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

	/** The blend state, or null when the pipeline writes its color as it is. **/
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
		Returns the blend state in the form that the drivers take. The first
		code is 1 when blending is on. Then come the operation and the source
		and destination factors of the color, and then those of the alpha.
		Fields that are left out take WebGPU's defaults. `Min` and `Max` take
		both factors as `One`, because they accept no other factor.
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
