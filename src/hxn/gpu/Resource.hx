package hxn.gpu;

/** Base class for objects a device creates. Each holds driver objects until `close()`. **/
class Resource {
	@:allow(hxn.gpu) final device:GpuDevice;
	@:allow(hxn.gpu) final id:Int;
	// The backend's driver objects.
	@:allow(hxn.gpu) var native:Null<{function close():Void;}>;

	static var count = 0;

	function new(device:GpuDevice) {
		this.device = device;
		id = ++count;
	}

	/** Releases the driver objects. The resource is unusable after. **/
	public function close():Void {
		if (native != null) {
			native.close();
			native = null;
		}
	}

	function live():Void {
		if (native == null)
			throw '${Type.getClassName(Type.getClass(this))} $id is closed';
	}
}
