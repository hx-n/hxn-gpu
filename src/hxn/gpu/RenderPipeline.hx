package hxn.gpu;

import hxn.gpu.Descriptors.BlendComponent;
import hxn.gpu.Descriptors.BlendState;
import hxn.gpu.Descriptors.ColorTargetState;
import hxn.gpu.Descriptors.DepthState;
import hxn.gpu.Descriptors.VertexBufferLayout;
import hxnsl.Layout.EntryPoint;

class RenderPipeline extends Pipeline {
	public final vertex:EntryPoint;
	public final fragment:EntryPoint;
	/** The color targets, in the order of the fragment shader's outputs. **/
	public final targets:Array<ColorTargetState>;

	/** The format of the first color target. **/
	public final format:TextureFormat;

	/** The depth test, or null when the pipeline tests no depth. **/
	public final depth:Null<DepthState>;

	public final topology:Topology;
	public final vertexBuffers:Array<VertexBufferLayout>;

	/** The blend state of the first color target, or null when it writes its color as it is. **/
	public final blend:Null<BlendState>;

	@:allow(hxn.gpu) function new(device:GpuDevice, shader:ShaderModule, vertex:EntryPoint, fragment:EntryPoint, targets:Array<ColorTargetState>,
			depth:Null<DepthState>, topology:Topology, vertexBuffers:Array<VertexBufferLayout>, constants:Array<{key:String, value:Float}>) {
		super(device, shader, constants);
		this.vertex = vertex;
		this.fragment = fragment;
		this.targets = targets;
		this.format = targets[0].format;
		this.blend = targets[0].blend;
		this.depth = depth;
		this.topology = topology;
		this.vertexBuffers = vertexBuffers;
	}

	/** Returns the depth test's compare function, `Less` when the state leaves it out. **/
	@:allow(hxn.gpu)
	function depthCompare():CompareFunction
		return depth != null && depth.compare != null ? depth.compare : Less;

	/** Returns whether the pipeline writes depth, true when the state leaves it out. **/
	@:allow(hxn.gpu)
	function depthWrite():Bool
		return depth != null && depth.write != false;

	/**
		Returns the blend state of color target `target` in the form that the drivers take. The first
		code is 1 when blending is on. Then come the operation and the source
		and destination factors of the color, and then those of the alpha.
		Fields that are left out take WebGPU's defaults. `Min` and `Max` take
		both factors as `One`, because they accept no other factor.
	**/
	@:allow(hxn.gpu)
	function blendCodes(target = 0):Array<Int> {
		var blend = targets[target].blend;
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
