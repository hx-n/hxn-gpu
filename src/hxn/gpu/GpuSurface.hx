package hxn.gpu;

/**
	A window or the web page's canvas, which a device renders frames into and
	presents. Configure it with a size, then for each frame render into
	`currentTexture()` and call `present()`. Configure it again when the
	window is resized.
**/
class GpuSurface extends Resource {
	public final target:SurfaceTarget;
	public var format(default, null):TextureFormat;
	public var width(default, null) = 0;
	public var height(default, null) = 0;
	/** Whether `present` waits for the display's refresh. **/
	public var vsync(default, null) = true;
	var frame:Null<Texture>;

	@:allow(hxn.gpu) function new(device:GpuDevice, target:SurfaceTarget) {
		super(device);
		this.target = target;
	}

	/** The format this surface presents best, which `configure` uses by default. **/
	public function preferredFormat():TextureFormat {
		live();
		return device.driver.surfaceFormat(this);
	}

	/** Sets the size of the frames, in pixels, and their format; again after a resize. **/
	public function configure(width:Int, height:Int, ?format:TextureFormat, ?vsync:Bool = true):Void {
		live();
		if (width <= 0 || height <= 0)
			throw 'a surface is at least 1x1 pixels, not ${width}x$height';
		this.width = width;
		this.height = height;
		this.format = format != null ? format : preferredFormat();
		this.vsync = vsync;
		frame = null;
		device.driver.configureSurface(this);
	}

	/**
		The texture of the frame being drawn, which a render pass renders into.
		It is the same texture until `present`.
	**/
	public function currentTexture():Texture {
		live();
		if (width == 0)
			throw "configure the surface before taking a frame";
		if (frame == null)
			frame = device.driver.surfaceTexture(this);
		return frame;
	}

	/** Shows the current frame, after the work submitted before. **/
	public function present():Void {
		live();
		if (frame == null)
			throw "present needs a frame: take one with currentTexture() and render into it";
		device.driver.present(this, frame);
		frame = null;
	}
}
