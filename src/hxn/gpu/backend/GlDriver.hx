package hxn.gpu.backend;

#if (hxn_gpu_gles || hxn_gpu_webgl2)
import hxn.gpu.Command;
import hxn.gpu.Limits.DefaultLimits;
import haxe.io.Bytes;
#if hxn_gpu_gles
import hxn.gpu.gles.Bindings;
import hxn.gpu.gles.Buffer as NativeBuffer;
import hxn.gpu.gles.BufferTarget;
import hxn.gpu.gles.ClearBits;
import hxn.gpu.gles.ComponentType;
import hxn.gpu.gles.Context;
import hxn.gpu.gles.Display;
import hxn.gpu.gles.Primitive;
import hxn.gpu.gles.Blend as NativeBlend;
import hxn.gpu.gles.Program as NativeProgram;
import hxn.gpu.gles.Sampler as NativeSampler;
import hxn.gpu.gles.Texture as NativeTexture;
import hxn.gpu.gles.TextureFormat as NativeFormat;
import hxn.gpu.gles.Usage;
import hxn.gpu.gles.VertexArray;
import hxn.gpu.gles.Wrap;
import hxn.gpu.gles.Shaders as GlShaders;
#else
import hxn.gpu.webgl2.Bindings;
import hxn.gpu.webgl2.Buffer as NativeBuffer;
import hxn.gpu.webgl2.BufferTarget;
import hxn.gpu.webgl2.ClearBits;
import hxn.gpu.webgl2.ComponentType;
import hxn.gpu.webgl2.Context;
import hxn.gpu.webgl2.Primitive;
import hxn.gpu.webgl2.Blend as NativeBlend;
import hxn.gpu.webgl2.Program as NativeProgram;
import hxn.gpu.webgl2.Sampler as NativeSampler;
import hxn.gpu.webgl2.Texture as NativeTexture;
import hxn.gpu.webgl2.TextureFormat as NativeFormat;
import hxn.gpu.webgl2.Usage;
import hxn.gpu.webgl2.VertexArray;
import hxn.gpu.webgl2.Wrap;
import hxn.gpu.webgl2.Shaders as GlShaders;
#end

/** A render pipeline's linked program and the binding points and texture units of its shader. **/
private class Program {
	public final program:NativeProgram;
	public final bindings:Bindings;
	// The pipeline's blend state, which GL sets when the pipeline is bound.
	public final blend:NativeBlend;

	public function new(program:NativeProgram, bindings:Bindings, blend:NativeBlend) {
		this.program = program;
		this.bindings = bindings;
		this.blend = blend;
	}

	public function close():Void
		program.close();
}

/**
	The native of a surface: the texture its frames are rendered into. GLSL from hxnsl
	flips clip space for textures, so `present` copies the frame into the window's
	framebuffer, whose origin is the bottom left, with its rows reversed.
**/
private class GlSurface {
	public var frame:Null<NativeTexture>;

	public function new() {}

	public function close():Void {
		if (frame != null) {
			frame.close();
			frame = null;
		}
	}
}

/** The native of a window frame: the surface's texture, which the surface closes. **/
private class SurfaceFrame {
	public final texture:NativeTexture;

	public function new(texture:NativeTexture)
		this.texture = texture;

	public function close():Void {}
}

/**
	Placeholder native for shader modules and bind groups: GL links programs per pipeline
	and binds resources at draw time.
**/
private class Unbound {
	public function new() {}

	public function close():Void {}
}

/**
	The OpenGL ES 3.0 backend, for GLES over EGL (hxn-gpu-gles) and WebGL2 in the browser
	(hxn-gpu-webgl2), whose APIs match. GL runs commands in submission order, so no
	barriers are needed.
**/
class GlDriver implements Driver {
	public static final FEATURES:Features = [TextureWrites, IndexedDraws, MultipleVertexBuffers, InstanceVertexBuffers, Presentation];

	/** `EGL_PLATFORM_X11_KHR`, the EGL platform of an Xlib display. **/
	static inline final PLATFORM_X11 = 0x31D5;

	/** `EGL_PLATFORM_WAYLAND_KHR`, the EGL platform of a Wayland display. **/
	static inline final PLATFORM_WAYLAND = 0x31D8;

	public final backend:Backend;
	public final adapter:String;
	public final features:Features = FEATURES;
	public final limits:Limits = DefaultLimits.gles;

	final context:Context;
	final release:() -> Void;
	// The window or canvas the context was made for, whose default framebuffer it presents.
	final target:Null<SurfaceTarget>;

	function new(backend:Backend, context:Context, release:() -> Void, target:Null<SurfaceTarget>) {
		this.backend = backend;
		this.context = context;
		this.release = release;
		this.target = target;
		adapter = context.renderer();
	}

	public static function open(surface:Null<SurfaceTarget>):Future<Driver> {
		return Settled.attempt(() -> {
			#if hxn_gpu_gles
			// A context presents only to the window it is made for, so a surface's window decides the display.
			var display:Display = switch (surface) {
				case null: Display.headless();
				case Window(3, handles): Display.native(PLATFORM_X11, handles[2]);
				case Window(1 | 2 | 5, _): Display.native(0, 0);
				case Window(4, handles): Display.native(PLATFORM_WAYLAND, handles[2]);
				case Window(platform, _): throw 'GLES presents to Xlib, Wayland, Win32, AppKit through ANGLE and Android windows, not platform $platform';
				case Canvas: throw "GLES has no web page canvas: use WebGL2";
			}
			var context = try switch (surface) {
				case Window(3, handles): display.createWindowContext(handles[0], haxe.Int64.toInt(handles[1]));
				// Sized when the surface is configured.
				case Window(4, handles): display.createWaylandContext(handles[0], 1, 1);
				case Window(_, handles): display.createWindowContext(handles[0], 0);
				case _: display.createContext();
			} catch (e:haxe.Exception) {
				display.close();
				throw e;
			}
			(new GlDriver(Gles, context, display.close, surface) : Driver);
			#else
			switch (surface) {
				case Window(_, _): throw "WebGL2 presents to the web page's canvas, not a window";
				case _:
			}
			(new GlDriver(WebGL2, Context.create(), () -> {}, Canvas) : Driver);
			#end
		}).flatMap(driver -> {
			#if hxn_gpu_webgl2
			// With threads the context draws on a canvas of its own and shows its frames on the page's.
			if (surface != null)
				return (cast driver : GlDriver).context.claimCanvas().map(_ -> driver);
			#end
			return Future.resolved(driver);
		});
	}

	public function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void {
		var target = buffer.usage.has(Index) ? BufferTarget.ElementArray : buffer.usage.has(Uniform) ? BufferTarget.Uniform : buffer.usage.has(Vertex) ? BufferTarget.Array : BufferTarget.CopyRead;
		var native = contents != null
			&& contents.length == buffer.size ? context.createBufferWith(target, contents, Usage.DynamicDraw) : context.createBuffer(target, buffer.size,
				Usage.DynamicDraw);
		if (contents != null && contents.length < buffer.size)
			native.write(0, contents);
		buffer.native = native;
	}

	public function createTexture(texture:Texture):Void {
		texture.native = context.createTexture(texture.width, texture.height, format(texture.format));
	}

	public function createSampler(sampler:Sampler):Void {
		var filter = sampler.filter == Linear ? FilterOf.linear : FilterOf.nearest;
		var wrap = wrapOf(sampler.address);
		sampler.native = context.createSampler(filter, filter, wrap, wrap);
	}

	public function createShader(shader:ShaderModule):Void {
		shader.native = new Unbound();
	}

	public function createComputePipeline(pipeline:ComputePipeline):Void {
		throw '$backend has no compute';
	}

	public function createRenderPipeline(pipeline:RenderPipeline):Void {
		var code = pipeline.shader.code;
		if (code.glslVertex == null)
			throw code.glslMissing != null ? '${code.name} has no GLSL ES: ${code.glslMissing}' : '${code.name} has no GLSL ES: implement hxn.gpu.Shader';
		var bindings = new Bindings(code.glslBindings);
		var b = @:privateAccess pipeline.blendCodes();
		pipeline.native = new Program(GlShaders.program(context, code.glslVertex, code.glslFragment, bindings), bindings, {
			enabled: b[0] == 1,
			colorOperation: b[1],
			colorSource: b[2],
			colorDestination: b[3],
			alphaOperation: b[4],
			alphaSource: b[5],
			alphaDestination: b[6]
		});
	}

	public function createBindGroup(group:BindGroup):Void {
		group.native = new Unbound();
	}

	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		(cast buffer.native : NativeBuffer).write(offset, bytes);
	}

	public function writeTexture(texture:Texture, region:hxn.gpu.Descriptors.TextureRegion, bytes:Bytes, bytesPerRow:Int):Void {
		var row = region.width * texture.format.bytesPerPixel();
		var packed = bytes;
		if (bytesPerRow != row || bytes.length != row * region.height) {
			packed = Bytes.alloc(row * region.height);
			for (y in 0...region.height)
				packed.blit(y * row, bytes, y * bytesPerRow, row);
		}
		nativeTexture(texture).write(region.x, region.y, region.width, region.height, packed);
	}

	public function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes> {
		var native:NativeBuffer = cast buffer.native;
		return Settled.attempt(() -> native.read(offset, size));
	}

	public function readTexture(texture:Texture):Future<Bytes> {
		return Settled.attempt(() -> {
			if (texture.format != Rgba8Unorm && texture.format != Rgba8UnormSrgb)
				throw '$backend reads back only rgba8 textures, not ${texture.format}';
			var framebuffer = context.createFramebuffer(nativeTexture(texture));
			context.bindFramebuffer(framebuffer);
			var pixels = context.readPixels(0, 0, texture.width, texture.height);
			framebuffer.close();
			pixels;
		});
	}

	public function submit(steps:Array<Step>):Void {
		for (step in steps)
			switch (step) {
				case RenderStep(target, clear, list):
					render(target, clear, list);
				case ComputeStep(_):
					throw '$backend has no compute';
				case CopyStep(_, _, _, _, _):
					throw '$backend has no buffer copies';
			}
		context.flush();
	}

	public function completed():Future<hxn.Unit> {
		return (context.completed());
	}

	public function createSurface(surface:GpuSurface):Void {
		if (target == null)
			throw '$backend presents only to the window it opened for: pass the surface target to GpuDevice.open';
		var same = switch [surface.target, target] {
			case [Window(p, h), Window(q, k)]: p == q && h[0] == k[0];
			case [Canvas, Canvas]: true;
			case _: false;
		}
		if (!same)
			throw '$backend presents only to the window it opened for, which this is not';
		surface.native = new GlSurface();
	}

	public function surfaceFormat(surface:GpuSurface):TextureFormat
		return Rgba8Unorm;

	public function configureSurface(surface:GpuSurface):Void {
		if (surface.format != Rgba8Unorm && surface.format != Rgba8UnormSrgb)
			throw '$backend presents rgba8 frames, not ${surface.format}';
		(cast surface.native : GlSurface).close();
		#if hxn_gpu_gles
		context.resizeWindow(surface.width, surface.height);
		context.swapInterval(surface.vsync ? 1 : 0);
		#else
		context.setSize(surface.width, surface.height);
		#end
	}

	public function surfaceTexture(surface:GpuSurface):Texture {
		var native:GlSurface = cast surface.native;
		if (native.frame == null)
			native.frame = context.createTexture(surface.width, surface.height, format(surface.format));
		var frame = new Texture(surface.device, surface.width, surface.height, surface.format, RenderTarget);
		frame.native = new SurfaceFrame(native.frame);
		return frame;
	}

	public function present(surface:GpuSurface, frame:Texture):Void {
		var framebuffer = context.createFramebuffer(nativeTexture(frame));
		context.blitFlipped(framebuffer, frame.width, frame.height);
		framebuffer.close();
		#if hxn_gpu_gles
		context.swapBuffers();
		#else
		context.present();
		#end
	}

	public function close():Void {
		context.close();
		release();
	}

	// Rows are addressed from the target's first row: GLSL from hxnsl flips clip space, so
	// the top of what is drawn is row 0, and viewport and scissor rectangles need no flip.
	function render(target:Texture, clear:Null<hxn.gpu.Descriptors.Color>, list:Array<Command>):Void {
		var framebuffer = context.createFramebuffer(nativeTexture(target));
		context.bindFramebuffer(framebuffer);
		context.viewport(0, 0, target.width, target.height);
		context.scissorTest(false);
		if (clear != null)
			context.clear(ClearBits.Color, clear.r, clear.g, clear.b, clear.a);
		var pipeline:Null<RenderPipeline> = null;
		var groups = new Map<Int, BindGroup>();
		var vertexBuffers = new Map<Int, {buffer:Buffer, offset:Int}>();
		var index:Null<{buffer:Buffer, format:IndexFormat}> = null;
		// Vertex arrays created in this pass, keyed by pipeline and buffers.
		var arrays = new Map<String, VertexArray>();
		function vertexArray():VertexArray {
			var key = '${pipeline.id}:' + [for (slot => b in vertexBuffers) '$slot=${b.buffer.id}+${b.offset}'].join(",") + (index != null ? '/${index.buffer.id}' : "");
			var found = arrays.get(key);
			if (found != null)
				return found;
			var vao = context.createVertexArray();
			for (slot in 0...pipeline.vertexBuffers.length) {
				var layout = pipeline.vertexBuffers[slot];
				var bound = vertexBuffers.get(slot);
				if (bound == null)
					throw 'the pipeline reads vertex buffer $slot, which is not set';
				var buffer = bound.buffer;
				for (a in layout.attributes) {
					switch (a.format) {
						case Uint32 | Sint32:
							vao.integerAttribute(a.location, cast buffer.native, 1, a.format == Uint32 ? ComponentType.UnsignedInt : ComponentType.Int,
								layout.stride, a.offset + bound.offset);
						case _:
							vao.attribute(a.location, cast buffer.native, a.format.components(), ComponentType.Float, false, layout.stride, a.offset + bound.offset);
					}
					if (layout.perInstance == true)
						vao.divisor(a.location, 1);
				}
			}
			if (index != null)
				vao.elementBuffer(cast index.buffer.native);
			arrays.set(key, vao);
			return vao;
		}
		function bindGroups():Void {
			var program:Program = cast pipeline.native;
			for (g => group in groups)
				for (i in 0...group.entries.length) {
					var entry = group.entries[i];
					switch (group.layout[i].type) {
						case "uniform":
							context.bindUniformBuffer(program.bindings.uniformBlock(g, entry.binding), cast entry.buffer.native);
						case "texture":
							var sampler = samplerFor(pipeline, groups, g, entry.binding);
							context.bindTexture(program.bindings.textureUnit(g, entry.binding), cast entry.texture.native, cast sampler.native);
						case _:
					}
				}
		}
		for (command in list)
			switch (command) {
				case SetRenderPipeline(p):
					pipeline = p;
					var program:Program = cast p.native;
					context.setBlend(program.blend);
					context.useProgram(program.program);
				case SetBindGroup(i, group):
					groups.set(i, group);
				case SetVertexBuffer(slot, buffer, offset):
					vertexBuffers.set(slot, {buffer: buffer, offset: offset});
				case SetViewport(x, y, width, height):
					context.viewport(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
				case SetScissor(x, y, width, height):
					context.scissorTest(true);
					context.scissor(x, y, width, height);
				case SetIndexBuffer(buffer, format):
					index = {buffer: buffer, format: format};
				case Draw(vertices, instances, first):
					context.bindVertexArray(vertexArray());
					bindGroups();
					context.drawArrays(primitive(pipeline.topology), first, vertices, instances);
				case DrawIndexed(indices, instances, first):
					context.bindVertexArray(vertexArray());
					bindGroups();
					var size = index.format == Uint16 ? 2 : 4;
					context.drawElements(primitive(pipeline.topology), indices, index.format == Uint16 ? ComponentType.UnsignedShort : ComponentType.UnsignedInt,
						first * size, instances);
				case _:
			}
		context.scissorTest(false);
		for (vao in arrays)
			vao.close();
		framebuffer.close();
	}

	static function nativeTexture(texture:Texture):NativeTexture {
		return Std.isOfType(texture.native, SurfaceFrame) ? (cast texture.native : SurfaceFrame).texture : cast texture.native;
	}

	/**
		Finds, among the bound groups, the sampler the shader pairs with the texture at
		`group` and `binding`.
	**/
	static function samplerFor(pipeline:RenderPipeline, groups:Map<Int, BindGroup>, group:Int, binding:Int):Sampler {
		for (stage in pipeline.shader.code.glslBindings)
			for (texture in stage.textures)
				if (texture.group == group && texture.binding == binding && texture.sampler != null) {
					var owner = groups.get(texture.sampler.group);
					var found = owner == null ? null : Lambda.find(owner.entries, e -> e.binding == texture.sampler.binding);
					if (found == null || found.sampler == null)
						throw 'the texture at group $group, binding $binding is sampled with group ${texture.sampler.group}, binding ${texture.sampler.binding}, which is not set';
					return found.sampler;
				}
		throw 'the shader samples no texture at group $group, binding $binding';
	}

	static function format(format:TextureFormat):NativeFormat {
		return switch (format) {
			case R8Unorm: R8;
			case Rgba8Unorm: Rgba8;
			case Rgba8UnormSrgb: Srgb8Alpha8;
			case R32Float: R32f;
			case Rgba16Float: Rgba16f;
			case Rgba32Float: Rgba32f;
			case Bgra8Unorm | Bgra8UnormSrgb: throw 'OpenGL ES has no $format textures';
		}
	}

	static function primitive(topology:Topology):Primitive {
		return switch (topology) {
			case PointList: Points;
			case LineList: Lines;
			case LineStrip: LineStrip;
			case TriangleList: Triangles;
			case TriangleStrip: TriangleStrip;
		}
	}

	static function wrapOf(mode:AddressMode):Wrap {
		return switch (mode) {
			case ClampToEdge: ClampToEdge;
			case Repeat: Repeat;
			case MirrorRepeat: MirroredRepeat;
		}
	}
}

#if hxn_gpu_gles
private typedef FilterType = hxn.gpu.gles.Filter;
#else
private typedef FilterType = hxn.gpu.webgl2.Filter;
#end

private class FilterOf {
	public static final nearest:FilterType = FilterType.Nearest;
	public static final linear:FilterType = FilterType.Linear;
}
#end
