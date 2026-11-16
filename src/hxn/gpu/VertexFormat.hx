package hxn.gpu;

/** The type of one vertex attribute. **/
enum abstract VertexFormat(Int) {
	var Float32;
	var Float32x2;
	var Float32x3;
	var Float32x4;
	var Uint32;
	var Sint32;

	/** How many 32-bit components it has. **/
	public function components():Int {
		return switch (cast this : VertexFormat) {
			case Float32 | Uint32 | Sint32: 1;
			case Float32x2: 2;
			case Float32x3: 3;
			case Float32x4: 4;
		}
	}
}
