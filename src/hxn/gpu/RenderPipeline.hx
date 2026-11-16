package hxn.gpu;

import hxn.gpu.Descriptors.VertexBufferLayout;
import hxnsl.Layout.EntryPoint;

class RenderPipeline extends Pipeline {
	public final vertex:EntryPoint;
	public final fragment:EntryPoint;
	public final format:TextureFormat;
	public final topology:Topology;
	public final vertexBuffers:Array<VertexBufferLayout>;

	@:allow(hxn.gpu) function new(device:GpuDevice, shader:ShaderModule, vertex:EntryPoint, fragment:EntryPoint, format:TextureFormat, topology:Topology,
			vertexBuffers:Array<VertexBufferLayout>, constants:Array<{key:String, value:Float}>) {
		super(device, shader, constants);
		this.vertex = vertex;
		this.fragment = fragment;
		this.format = format;
		this.topology = topology;
		this.vertexBuffers = vertexBuffers;
	}
}
