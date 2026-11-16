package hxn.gpu;

/** A 2D image of one mip level. **/
class Texture extends Resource {
	public final width:Int;
	public final height:Int;
	public final format:TextureFormat;
	public final usage:TextureUsage;

	@:allow(hxn.gpu) function new(device:GpuDevice, width:Int, height:Int, format:TextureFormat, usage:TextureUsage) {
		super(device);
		this.width = width;
		this.height = height;
		this.format = format;
		this.usage = usage;
	}
}
