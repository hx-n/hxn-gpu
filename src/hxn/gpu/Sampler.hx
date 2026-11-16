package hxn.gpu;

/** How a shader reads a texture. **/
class Sampler extends Resource {
	public final filter:Filter;
	public final address:AddressMode;

	@:allow(hxn.gpu) function new(device:GpuDevice, filter:Filter, address:AddressMode) {
		super(device);
		this.filter = filter;
		this.address = address;
	}
}
