import haxe.io.Bytes;
import hxn.gpu.*;
import Shaders;

/**
	Presents to a window, or in a web page to its canvas: three frames, each
	cleared to one color with a tinted quad drawn over the middle, the last
	read back before it is shown where the backend can read a frame.
**/
class Main {
	static inline final SIZE = 64;

	/** What the frames are presented to. **/
	static final WHERE = #if (emscripten || wasm) "the web page's canvas" #else "a window" #end;

	static function failed(e:haxe.Exception) {
		Sys.println('failed: ${e.message}');
		hxn.Loop.exit(1);
	}

	static function main() {
		var attributes = new hxn.window.WindowAttributes();
		attributes.title("hxn-gpu present");
		attributes.width(SIZE);
		attributes.height(SIZE);
		var window = hxn.window.Window.open(attributes);
		attributes.close();
		var target = SurfaceTargets.ofWindow(window);
		GpuDevice.open({surface: target, required: [Presentation]}).then(device -> {
			Sys.println('device: ${device.backend}');
			var surface = device.createSurface(target);
			surface.configure(window.width(), window.height(), surface.preferredFormat(), false);
			var shader = device.createShader(Tinted);
			var pipeline = device.createRenderPipeline({
				shader: shader,
				format: surface.format,
				topology: TriangleStrip,
				vertexBuffers: [
					{stride: 8, attributes: [{location: Tinted.INPUT_position, format: Float32x2, offset: 0}]}
				]
			});
			var corners = [-0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5];
			var quad = Bytes.alloc(corners.length * 4);
			for (i in 0...corners.length)
				quad.setFloat(i * 4, corners[i]);
			var positions = device.createBuffer({size: quad.length, usage: Vertex, contents: quad});
			var params = Bytes.alloc(Tinted.PARAMS_SIZE);
			for (i in 0...4)
				params.setFloat(Tinted.PARAMS_tint + i * 4, 1.0);
			var uniforms = device.createBuffer({size: params.length, usage: Uniform, contents: params});
			var group = device.createBindGroup({pipeline: pipeline, group: Tinted.PARAMS_GROUP, entries: [{binding: Tinted.PARAMS_BINDING, buffer: uniforms}]});
			var colors = [[0.0, 0.0, 1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]];
			function frame(i:Int) {
				while (true) {
					switch window.poll() {
						case Resized(_, _):
							surface.configure(window.width(), window.height(), surface.preferredFormat(), false);
						case None:
							break;
						case _:
					}
				}
				var c = colors[i];
				var texture = surface.currentTexture();
				var encoder = device.createCommandEncoder();
				var pass = encoder.beginRenderPass(texture, {
					r: c[0],
					g: c[1],
					b: c[2],
					a: 1
				});
				pass.setPipeline(pipeline);
				pass.setBindGroup(Tinted.PARAMS_GROUP, group);
				pass.setVertexBuffer(0, positions);
				pass.draw(4);
				pass.end();
				device.submit(encoder);
				function next() {
					surface.present();
					if (i + 1 < colors.length)
						frame(i + 1);
					else
						device.completed().then(_ -> {
							for (o in ([group, uniforms, positions, pipeline, shader, surface] : Array<Resource>))
								o.close();
							device.close();
							window.close();
						}, failed);
				}
				if (i + 1 < colors.length || device.backend == Metal) {
					if (i + 1 == colors.length)
						Sys.println('present: ${colors.length} frames to $WHERE');
					next();
					return;
				}
				// The last frame: a corner is the clear color, the middle is the white quad.
				device.readTexture(texture).then(pixels -> {
					var bgra = surface.format == Bgra8Unorm || surface.format == Bgra8UnormSrgb;
					var corner = [for (k in 0...3) pixels.get(bgra ? 2 - k : k)];
					// A window on a high-density display can be larger in pixels than asked.
					var middle = (texture.height >> 1) * texture.width * 4 + (texture.width >> 1) * 4;
					var centre = [for (k in 0...3) pixels.get(middle + k)];
					var expected = [for (v in c) Math.round(v * 255)];
					if (corner.join(",") != expected.join(",") || centre.join(",") != "255,255,255")
						throw 'the last frame has ${corner.join(", ")} in a corner and ${centre.join(", ")} in the middle';
					Sys.println('present: ${colors.length} frames to $WHERE, the last ${expected.join(", ")} around a white quad');
					next();
				}, failed);
			}
			frame(0);
		}, e -> {
			Sys.println('no GPU to present with: ${e.message}');
			hxn.Loop.exit(1);
		});
	}
}
