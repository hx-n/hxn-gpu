package hxn.gpu;

/**
	How a texture is used, combined with `|`. `GpuDevice.readTexture` works on any
	texture, and `GpuDevice.writeTexture` on any texture when the device has
	`TextureWrites`.
**/
enum abstract TextureUsage(Int) from Int to Int {
	/** Sampled by a shader. **/
	var Sampled = 1;
	/** Written by a shader; needs `StorageTextures`. **/
	var Storage = 2;
	/** The target of a render pass. **/
	var RenderTarget = 4;

	public inline function has(usage:TextureUsage):Bool
		return this & (usage : Int) != 0;

	@:op(A | B) static inline function or(a:TextureUsage, b:TextureUsage):TextureUsage
		return (a : Int) | (b : Int);
}
