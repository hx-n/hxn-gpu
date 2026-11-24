package hxn.gpu;

/** The type of one vertex attribute. **/
enum abstract VertexFormat(Int) {
	var Float32;
	var Float32x2;
	var Float32x3;
	var Float32x4;
	var Uint32;
	var Sint32;

	/** Four bytes, each read as a float from 0 to 1, such as an RGBA color. **/
	var Unorm8x4;

	/** How many components it has. **/
	public function components():Int {
		return switch (cast this : VertexFormat) {
			case Float32 | Uint32 | Sint32: 1;
			case Float32x2: 2;
			case Float32x3: 3;
			case Float32x4 | Unorm8x4: 4;
		}
	}

	/** How many bytes it takes. **/
	public function bytes():Int {
		return switch (cast this : VertexFormat) {
			case Unorm8x4: 4;
			case _: components() * 4;
		}
	}
}
