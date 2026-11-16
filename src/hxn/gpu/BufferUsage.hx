package hxn.gpu;

/**
	How a buffer is used, combined with `|`. `GpuDevice.writeBuffer` and
	`GpuDevice.readBuffer` work on any buffer.
**/
enum abstract BufferUsage(Int) from Int to Int {
	var Vertex = 1;
	var Index = 2;
	var Uniform = 4;
	var Storage = 8;
	/** The source of `CommandEncoder.copyBufferToBuffer`. **/
	var CopySrc = 16;
	/** The destination of `CommandEncoder.copyBufferToBuffer`. **/
	var CopyDst = 32;

	public inline function has(usage:BufferUsage):Bool
		return this & (usage : Int) != 0;

	@:op(A | B) static inline function or(a:BufferUsage, b:BufferUsage):BufferUsage
		return (a : Int) | (b : Int);
}
