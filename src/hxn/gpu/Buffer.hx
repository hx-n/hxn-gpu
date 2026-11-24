package hxn.gpu;

/** GPU memory: vertices, indices, uniforms or storage. **/
class Buffer extends Resource {
	public final size:Int;
	public final usage:BufferUsage;

	// The last submission that used the buffer, in the form its driver gives. A driver that writes the buffer's memory directly waits only for it.
	@:allow(hxn.gpu) var use:Any = null;

	@:allow(hxn.gpu) function new(device:GpuDevice, size:Int, usage:BufferUsage) {
		super(device);
		this.size = size;
		this.usage = usage;
	}
}
