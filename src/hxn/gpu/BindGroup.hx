package hxn.gpu;

import hxn.gpu.Descriptors.BindGroupEntry;
import hxnsl.Layout.LayoutEntry;

/**
	The buffers, textures and samplers for one bind group of a shader, as its `LAYOUT`
	describes them. Use it with pipelines made from that shader.
**/
class BindGroup extends Resource {
	public final shader:ShaderModule;
	public final group:Int;
	public final entries:Array<BindGroupEntry>;
	/** The layout entry for each entry, in the same order. **/
	@:allow(hxn.gpu) final layout:Array<LayoutEntry>;

	@:allow(hxn.gpu) function new(device:GpuDevice, shader:ShaderModule, group:Int, entries:Array<BindGroupEntry>, layout:Array<LayoutEntry>) {
		super(device);
		this.shader = shader;
		this.group = group;
		this.entries = entries;
		this.layout = layout;
	}
}
