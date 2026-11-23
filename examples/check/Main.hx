import hxn.gpu.*;
import haxe.io.Bytes;
import Shaders;

/**
	The check CI runs on each backend: a compute shader over a buffer, a render pass into
	a texture, a pass that samples a texture, and a buffer written and read back, with
	each result checked. The orientation, region and layered steps mark one corner of the
	target, so a flipped image fails them. Each step that needs a feature the device lacks prints that it was
	skipped; every other line is the same on all backends.
**/
class Main {
	static function check(ok:Bool, message:String) {
		if (!ok)
			throw message;
	}

	static function failed(e:haxe.Exception) {
		Sys.println('failed: ${e.message}');
		hxn.Loop.exit(1);
	}

	static function closeAll(objects:Array<Resource>) {
		for (o in objects)
			o.close();
	}

	static function main() {
		GpuDevice.open().then(device -> {
			Sys.println('device: ${device.backend}');
			Sys.println('features: ${device.features}');
			compute(device, () -> render(device, () -> blended(device, () -> textured(device, () -> orientation(device, () -> regions(device, () -> layered(device, () -> roundTrip(device, () -> device.close()))))))));
		}, e -> {
			Sys.println('no GPU: ${e.message}');
			hxn.Loop.exit(1);
		});
	}

	static function compute(device:GpuDevice, next:() -> Void) {
		if (!device.features.has(Compute)) {
			Sys.println('compute: ${device.backend} has no compute');
			next();
			return;
		}
		var shader = device.createShader(Tripled);
		var pipeline = device.createComputePipeline({shader: shader});
		var count = 64;
		var input = Bytes.alloc(count * 4);
		for (i in 0...count)
			input.setInt32(i * 4, i);
		var data = device.createBuffer({size: count * 4, usage: Storage, contents: input});
		var group = device.createBindGroup({pipeline: pipeline, group: Tripled.BUFFER_data_GROUP, entries: [{binding: Tripled.BUFFER_data, buffer: data}]});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginComputePass();
		pass.setPipeline(pipeline);
		pass.setBindGroup(Tripled.BUFFER_data_GROUP, group);
		pass.dispatch(Std.int(count / Tripled.ENTRY_POINTS[0].workgroup[0]));
		pass.end();
		device.submit(encoder);
		device.readBuffer(data).then(output -> {
			for (i in 0...count)
				check(output.getInt32(i * 4) == i * 3 + 1, 'value $i is ${output.getInt32(i * 4)}, not ${i * 3 + 1}');
			Sys.println('compute: $count values tripled plus one, the last ${output.getInt32((count - 1) * 4)}');
			closeAll([group, data, pipeline, shader]);
			next();
		}, failed);
	}

	static function floats(device:GpuDevice, values:Array<Float>):Buffer {
		var bytes = Bytes.alloc(values.length * 4);
		for (i in 0...values.length)
			bytes.setFloat(i * 4, values[i]);
		return device.createBuffer({size: bytes.length, usage: Vertex, contents: bytes});
	}

	/** Reads `target` back and checks every pixel is `expected`, within `tolerance`. **/
	static function readTarget(device:GpuDevice, target:Texture, expected:Array<Int>, label:String, next:() -> Void, tolerance = 0) {
		device.readTexture(target).then(pixels -> {
			for (p in 0...target.width * target.height)
				for (c in 0...4)
					check(Math.abs(pixels.get(p * 4 + c) - expected[c]) <= tolerance, '$label: pixel $p channel $c is ${pixels.get(p * 4 + c)}, not ${expected[c]}');
			Sys.println('$label: ${target.width}x${target.height} pixels of ${[for (c in 0...4) pixels.get(c)].join(", ")}');
			next();
		}, failed);
	}

	/**
		Reads `target` back and checks that its top-left `corner` by `corner` pixels are
		`inside` and the rest `outside`, or with `bottomRight` the bottom-right corner.
	**/
	static function readCorner(device:GpuDevice, target:Texture, corner:Int, inside:Array<Int>, outside:Array<Int>, label:String, message:String,
			next:() -> Void, bottomRight = false) {
		device.readTexture(target).then(pixels -> {
			for (y in 0...target.height)
				for (x in 0...target.width) {
					var within = bottomRight ? x >= target.width - corner && y >= target.height - corner : x < corner && y < corner;
					var expected = within ? inside : outside;
					var p = (y * target.width + x) * 4;
					for (c in 0...4)
						check(pixels.get(p + c) == expected[c], '$label: pixel $x, $y channel $c is ${pixels.get(p + c)}, not ${expected[c]}');
				}
			Sys.println('$label: $message');
			next();
		}, failed);
	}

	static function render(device:GpuDevice, next:() -> Void) {
		var shader = device.createShader(Tinted);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [{stride: 8, attributes: [{location: Tinted.INPUT_position, format: Float32x2, offset: 0}]}]
		});
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});
		var positions = floats(device, [-1, -1, 1, -1, -1, 1, 1, 1]);
		var params = Bytes.alloc(Tinted.PARAMS_SIZE);
		var tint = [0.25, 0.5, 0.75, 1.0];
		for (i in 0...4)
			params.setFloat(Tinted.PARAMS_tint + i * 4, tint[i]);
		var uniforms = device.createBuffer({size: params.length, usage: Uniform, contents: params});
		var group = device.createBindGroup({pipeline: pipeline, group: Tinted.PARAMS_GROUP, entries: [{binding: Tinted.PARAMS_BINDING, buffer: uniforms}]});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(target);
		pass.setPipeline(pipeline);
		pass.setBindGroup(Tinted.PARAMS_GROUP, group);
		pass.setVertexBuffer(0, positions);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readTarget(device, target, [for (c in tint) Math.round(c * 255)], "render", () -> {
			closeAll([group, uniforms, positions, target, pipeline, shader]);
			next();
		});
	}

	// A half-transparent red quad over a blue target, with `Blend.alpha`: half red, half blue, opaque.
	static function blended(device:GpuDevice, next:() -> Void) {
		var shader = device.createShader(Tinted);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [{stride: 8, attributes: [{location: Tinted.INPUT_position, format: Float32x2, offset: 0}]}],
			blend: Blend.alpha
		});
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});
		var positions = floats(device, [-1, -1, 1, -1, -1, 1, 1, 1]);
		var params = Bytes.alloc(Tinted.PARAMS_SIZE);
		var tint = [1.0, 0.0, 0.0, 0.5];
		for (i in 0...4)
			params.setFloat(Tinted.PARAMS_tint + i * 4, tint[i]);
		var uniforms = device.createBuffer({size: params.length, usage: Uniform, contents: params});
		var group = device.createBindGroup({pipeline: pipeline, group: Tinted.PARAMS_GROUP, entries: [{binding: Tinted.PARAMS_BINDING, buffer: uniforms}]});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(target, {r: 0, g: 0, b: 1, a: 1});
		pass.setPipeline(pipeline);
		pass.setBindGroup(Tinted.PARAMS_GROUP, group);
		pass.setVertexBuffer(0, positions);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readTarget(device, target, [128, 0, 128, 255], "blend", () -> {
			closeAll([group, uniforms, positions, target, pipeline, shader]);
			next();
		}, 1);
	}

	static function textured(device:GpuDevice, next:() -> Void) {
		if (!device.features.has(TextureWrites)) {
			Sys.println('textured: ${device.backend} has no texture writes');
			next();
			return;
		}
		var shader = device.createShader(Textured);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [
				{
					stride: 16,
					attributes: [
						{location: Textured.INPUT_position, format: Float32x2, offset: 0},
						{location: Textured.INPUT_uv, format: Float32x2, offset: 8}
					]
				}
			]
		});
		// A 2x2 image of one color.
		var color = [40, 80, 120, 255];
		var image = device.createTexture({width: 2, height: 2, format: Rgba8Unorm, usage: Sampled});
		var pixels = Bytes.alloc(2 * 2 * 4);
		for (i in 0...4)
			for (c in 0...4)
				pixels.set(i * 4 + c, color[c]);
		device.writeTexture(image, pixels);
		var sampler = device.createSampler();
		var group = device.createBindGroup({
			pipeline: pipeline,
			group: Textured.TEXTURE_image_GROUP,
			// The image's sampler has the next binding.
			entries: [{binding: Textured.TEXTURE_image, texture: image}, {binding: Textured.TEXTURE_image + 1, sampler: sampler}]
		});
		var vertices = floats(device, [-1, -1, 0, 1, 1, -1, 1, 1, -1, 1, 0, 0, 1, 1, 1, 0]);
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(target);
		pass.setPipeline(pipeline);
		pass.setBindGroup(Textured.TEXTURE_image_GROUP, group);
		pass.setVertexBuffer(0, vertices);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readTarget(device, target, color, "textured", () -> {
			closeAll([group, sampler, image, vertices, target, pipeline, shader]);
			next();
		});
	}

	// Red over clip space x -1 to 0 and y 0 to 1 fills the top-left quarter.
	static function orientation(device:GpuDevice, next:() -> Void) {
		var shader = device.createShader(Tinted);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [{stride: 8, attributes: [{location: Tinted.INPUT_position, format: Float32x2, offset: 0}]}]
		});
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});
		var positions = floats(device, [-1, 0, 0, 0, -1, 1, 0, 1]);
		var params = Bytes.alloc(Tinted.PARAMS_SIZE);
		params.setFloat(Tinted.PARAMS_tint, 1);
		params.setFloat(Tinted.PARAMS_tint + 12, 1);
		var uniforms = device.createBuffer({size: params.length, usage: Uniform, contents: params});
		var group = device.createBindGroup({pipeline: pipeline, group: Tinted.PARAMS_GROUP, entries: [{binding: Tinted.PARAMS_BINDING, buffer: uniforms}]});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(target, {r: 0, g: 0, b: 0, a: 1});
		pass.setPipeline(pipeline);
		pass.setBindGroup(Tinted.PARAMS_GROUP, group);
		pass.setVertexBuffer(0, positions);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readCorner(device, target, 2, [255, 0, 0, 255], [0, 0, 0, 255], "orientation", "clip space toward -x and +y is the top left", () -> {
			closeAll([group, uniforms, positions, target, pipeline, shader]);
			next();
		});
	}

	// The image is blue, with a 2x2 red region written at 2, 2 from rows 12 bytes apart.
	// Sampled with uv 0, 0 at the top left, its bottom-right quarter is red.
	static function regions(device:GpuDevice, next:() -> Void) {
		if (!device.features.has(TextureWrites)) {
			Sys.println('regions: ${device.backend} has no texture writes');
			next();
			return;
		}
		var image = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: Sampled});
		var blue = Bytes.alloc(4 * 4 * 4);
		for (i in 0...16) {
			blue.set(i * 4 + 2, 255);
			blue.set(i * 4 + 3, 255);
		}
		device.writeTexture(image, blue);
		// Two rows of two red pixels, the first padded with a green one.
		var red = Bytes.alloc(12 + 8);
		for (i in [0, 1, 3, 4]) {
			red.set(i * 4, 255);
			red.set(i * 4 + 3, 255);
		}
		red.set(2 * 4 + 1, 255);
		red.set(2 * 4 + 3, 255);
		device.writeTexture(image, red, {x: 2, y: 2, width: 2, height: 2}, 12);

		var shader = device.createShader(Textured);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [
				{
					stride: 16,
					attributes: [
						{location: Textured.INPUT_position, format: Float32x2, offset: 0},
						{location: Textured.INPUT_uv, format: Float32x2, offset: 8}
					]
				}
			]
		});
		var sampler = device.createSampler();
		var group = device.createBindGroup({
			pipeline: pipeline,
			group: Textured.TEXTURE_image_GROUP,
			entries: [{binding: Textured.TEXTURE_image, texture: image}, {binding: Textured.TEXTURE_image + 1, sampler: sampler}]
		});
		var vertices = floats(device, [-1, -1, 0, 1, 1, -1, 1, 1, -1, 1, 0, 0, 1, 1, 1, 0]);
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});

		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(target);
		pass.setPipeline(pipeline);
		pass.setBindGroup(Textured.TEXTURE_image_GROUP, group);
		pass.setVertexBuffer(0, vertices);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readCorner(device, target, 2, [255, 0, 0, 255], [0, 0, 255, 255], "regions", "a 2x2 region written at 2, 2 samples as the bottom right", () -> {
			closeAll([group, sampler, image, vertices, target, pipeline, shader]);
			next();
		}, true);
	}

	// The first pass clears to blue. The second keeps it and draws a full-screen quad of the
	// second instance in the buffer, red, with the viewport on the left half and the scissor
	// on the top half: the top-left quarter is red.
	static function layered(device:GpuDevice, next:() -> Void) {
		if (!device.features.has(InstanceVertexBuffers)) {
			Sys.println('layered: ${device.backend} has no instance vertex buffers');
			next();
			return;
		}
		var shader = device.createShader(Placed);
		var pipeline = device.createRenderPipeline({
			shader: shader,
			format: Rgba8Unorm,
			topology: TriangleStrip,
			vertexBuffers: [
				{stride: 8, attributes: [{location: Placed.INPUT_position, format: Float32x2, offset: 0}]},
				{
					stride: 24,
					perInstance: true,
					attributes: [
						{location: Placed.INPUT_offset, format: Float32x2, offset: 0},
						{location: Placed.INPUT_color, format: Float32x4, offset: 8}
					]
				}
			]
		});
		var corners = floats(device, [-1, -1, 1, -1, -1, 1, 1, 1]);
		// Two instances: green, then red. The pass reads from the second.
		var instances = floats(device, [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1]);
		var target = device.createTexture({width: 4, height: 4, format: Rgba8Unorm, usage: RenderTarget});

		var encoder = device.createCommandEncoder();
		encoder.beginRenderPass(target, {r: 0, g: 0, b: 1, a: 1}).end();
		var pass = encoder.beginRenderPass(target, null, true);
		pass.setPipeline(pipeline);
		pass.setViewport(0, 0, 2, 4);
		pass.setScissorRect(0, 0, 4, 2);
		pass.setVertexBuffer(0, corners);
		pass.setVertexBuffer(1, instances, 24);
		pass.draw(4);
		pass.end();
		device.submit(encoder);
		readCorner(device, target, 2, [255, 0, 0, 255], [0, 0, 255, 255], "layered",
			"a kept pass draws the offset instance inside the viewport and scissor", () -> {
				closeAll([instances, corners, target, pipeline, shader]);
				next();
			});
	}

	static function roundTrip(device:GpuDevice, next:() -> Void) {
		var count = 16;
		var values = Bytes.alloc(count * 4);
		for (i in 0...count)
			values.setInt32(i * 4, i * 7);
		var data = device.createBuffer({size: count * 4, usage: Uniform});
		device.writeBuffer(data, 0, values);
		device.readBuffer(data).then(read -> {
			for (i in 0...count)
				check(read.getInt32(i * 4) == i * 7, 'value $i is ${read.getInt32(i * 4)}, not ${i * 7}');
			Sys.println('buffer: $count values written and read back, the last ${read.getInt32((count - 1) * 4)}');
			data.close();
			next();
		}, failed);
	}
}
