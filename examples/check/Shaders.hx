/** Each value becomes three times itself plus one. **/
class Tripled implements hxn.gpu.Shader {
	static var SRC = {
		@param var data : RWBuffer<Int>;

		function main() {
			setLayout(16);
			var i = computeVar.globalInvocation.x;
			data[i] = data[i] * 3 + 1;
		}
	};
}

/** Fills what it covers with `tint`. **/
class Tinted implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}

/** Fills what it covers with `image`, sampled at the vertices' uv. **/
class Textured implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec2, uv : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var image : Sampler2D;
		var calculatedUV : Vec2;

		function vertex() {
			calculatedUV = input.uv;
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = image.get(calculatedUV);
		}
	};
}

/** Each instance draws the quad moved by its `offset` and filled with its `color`. **/
class Placed implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec2, offset : Vec2, color : Vec4 };
		var output : { position : Vec4, color : Vec4 };
		var tint : Vec4;

		function vertex() {
			tint = input.color;
			output.position = vec4(input.position + input.offset, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}

/** Each vertex has a position in clip space, depth included, and a color that the fragment takes. **/
class Deep implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec3, color : Vec4 };
		var output : { position : Vec4, color : Vec4 };
		var shade : Vec4;

		function vertex() {
			shade = input.color;
			output.position = vec4(input.position, 1);
		}

		function fragment() {
			output.color = shade;
		}
	};
}

/** Writes red into the first color target and green into the second. **/
class Split implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4, second : Vec4 };

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = vec4(1, 0, 0, 1);
			output.second = vec4(0, 1, 0, 1);
		}
	};
}
