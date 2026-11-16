package hxn.gpu;

/** GPU memory: vertices, indices, uniforms or storage. **/
class Buffer extends Resource {
	public final size:Int;
	public final usage:BufferUsage;

	@:allow(hxn.gpu) function new(device:GpuDevice, size:Int, usage:BufferUsage) {
		super(device);
		this.size = size;
		this.usage = usage;
	}
}
