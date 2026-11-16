package hxn.gpu;

/** A texture's pixel format. **/
enum abstract TextureFormat(Int) {
	var R8Unorm;
	var Rgba8Unorm;
	var Rgba8UnormSrgb;
	var Bgra8Unorm;
	var Bgra8UnormSrgb;
	var R32Float;
	var Rgba16Float;
	var Rgba32Float;

	/** Bytes per pixel. **/
	public function bytesPerPixel():Int {
		return switch (cast this : TextureFormat) {
			case R8Unorm: 1;
			case Rgba8Unorm | Rgba8UnormSrgb | Bgra8Unorm | Bgra8UnormSrgb | R32Float: 4;
			case Rgba16Float: 8;
			case Rgba32Float: 16;
		}
	}

	public function toString():String {
		return switch (cast this : TextureFormat) {
			case R8Unorm: "r8unorm";
			case Rgba8Unorm: "rgba8unorm";
			case Rgba8UnormSrgb: "rgba8unorm-srgb";
			case Bgra8Unorm: "bgra8unorm";
			case Bgra8UnormSrgb: "bgra8unorm-srgb";
			case R32Float: "r32float";
			case Rgba16Float: "rgba16float";
			case Rgba32Float: "rgba32float";
		}
	}
}
