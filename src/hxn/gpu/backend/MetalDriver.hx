package hxn.gpu.backend;

#if hxn_gpu_metal
import hxn.gpu.Command;
import hxn.gpu.Limits.DefaultLimits;
import hxn.gpu.metal.Buffer as NativeBuffer;
import hxn.gpu.metal.CommandBuffer;
import hxn.gpu.metal.CommandQueue;
import hxn.gpu.metal.ComputeEncoder;
import hxn.gpu.metal.Device as NativeDevice;
import hxn.gpu.metal.Drawable;
import hxn.gpu.metal.Layer;
import hxn.gpu.metal.Function;
import hxn.gpu.metal.Library;
import hxn.gpu.metal.RenderEncoder;
import hxn.gpu.metal.Texture as NativeTexture;
import haxe.io.Bytes;
import hxnsl.Layout.MslEntry;
import hxnsl.Layout.MslResource;

/** A Metal shader: its library and the functions loaded from it. **/
private class Program {
	public final library:Library;
	public final functions = new Map<String, Function>();

	public function new(library:Library) {
		this.library = library;
	}

	public function named(name:String):Function {
		var found = functions.get(name);
		if (found == null) {
			found = library.functionNamed(name);
			functions.set(name, found);
		}
		return found;
	}

	public function close():Void {
		for (f in functions)
			f.close();
		library.close();
	}
}

/** A window's `CAMetalLayer`, made when the surface is first configured, and the drawable of the frame being drawn. **/
private class MetalSurface {
	public var layer:Null<Layer>;
	public var format:Null<TextureFormat>;
	public var drawable:Null<Drawable>;

	public function new() {}

	public function close():Void {
		if (drawable != null)
			drawable.close();
		if (layer != null)
			layer.close();
	}
}

/** Placeholder native for bind groups, which Metal binds at draw time. **/
private class Unbound {
	public function new() {}

	public function close():Void {}
}

/** The Metal backend, over hxn-gpu-metal. Metal tracks hazards between commands itself. **/
class MetalDriver implements Driver {
	public static final FEATURES:Features = [
		Compute,
		StorageTextures,
		TextureWrites,
		BindingOffsets,
		MultipleVertexBuffers,
		InstanceVertexBuffers,
		Presentation
	];

	/**
		Buffer argument index for vertex buffer slot 0. Slot n uses this minus n, above
		the indices the shader's own buffers use.
	**/
	static inline final VERTEX_BUFFERS = 30;

	public final backend:Backend = Metal;
	public final adapter:String;
	public final features:Features = FEATURES;
	public final limits:Limits = DefaultLimits.webgpu;

	final device:NativeDevice;
	final queue:CommandQueue;
	// The last command buffer committed, and when it completes.
	var last:Null<CommandBuffer>;
	var lastDone:Future<hxn.Unit> = Future.resolved(hxn.Unit.Nothing);

	function new(device:NativeDevice) {
		this.device = device;
		queue = device.newCommandQueue();
		adapter = device.name();
	}

	// The textures of window frames, which a layer's drawable lends and the CPU cannot read.
	final frames = new Map<Int, Bool>();

	public static function open(surface:Null<SurfaceTarget>):Future<Driver> {
		return Settled.attempt(() -> (new MetalDriver(NativeDevice.systemDefault()) : Driver));
	}

	public function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void {
		var native = contents != null && contents.length == buffer.size ? device.newBufferWith(contents) : device.newBuffer(buffer.size);
		if (contents != null && contents.length < buffer.size)
			native.write(0, contents);
		buffer.native = native;
	}

	public function createTexture(texture:Texture):Void {
		var usage = 0;
		if (texture.usage.has(Sampled))
			usage |= hxn.gpu.metal.TextureUsage.ShaderRead;
		if (texture.usage.has(Storage))
			usage |= hxn.gpu.metal.TextureUsage.ShaderRead | hxn.gpu.metal.TextureUsage.ShaderWrite;
		if (texture.usage.has(RenderTarget))
			usage |= hxn.gpu.metal.TextureUsage.RenderTarget;
		texture.native = device.newTexture({
			width: texture.width,
			height: texture.height,
			format: format(texture.format),
			usage: usage,
			storage: STORAGE
		});
	}

	public function createSampler(sampler:Sampler):Void {
		var filter = sampler.filter == Linear ? hxn.gpu.metal.Filter.Linear : hxn.gpu.metal.Filter.Nearest;
		sampler.native = device.newSampler({minFilter: filter, magFilter: filter, address: address(sampler.address)});
	}

	public function createShader(shader:ShaderModule):Void {
		var code = shader.code;
		if (code.msl == null)
			throw '${code.name} has no MSL: implement hxn.gpu.Shader';
		shader.native = new Program(hxn.gpu.metal.Shaders.library(device, code.metallib != null ? code.metallib() : null, code.msl));
	}

	public function createComputePipeline(pipeline:ComputePipeline):Void {
		pipeline.native = device.newComputePipeline(programOf(pipeline.shader).named(pipeline.entryPoint.name));
	}

	public function createRenderPipeline(pipeline:RenderPipeline):Void {
		var program = programOf(pipeline.shader);
		var attributes:Array<hxn.gpu.metal.VertexAttribute> = [];
		var layouts:Array<hxn.gpu.metal.VertexLayout> = [];
		for (slot in 0...pipeline.vertexBuffers.length) {
			var buffer = pipeline.vertexBuffers[slot];
			for (a in buffer.attributes)
				attributes.push({
					location: a.location,
					format: vertexFormat(a.format),
					offset: a.offset,
					buffer: VERTEX_BUFFERS - slot
				});
			layouts.push({buffer: VERTEX_BUFFERS - slot, stride: buffer.stride, perInstance: buffer.perInstance == true});
		}
		pipeline.native = device.newRenderPipeline(program.named(pipeline.vertex.name), program.named(pipeline.fragment.name), format(pipeline.format),
			attributes, layouts);
	}

	public function createBindGroup(group:BindGroup):Void {
		group.native = new Unbound();
	}

	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		idle();
		(cast buffer.native : NativeBuffer).write(offset, bytes);
	}

	public function writeTexture(texture:Texture, bytes:Bytes):Void {
		idle();
		(cast texture.native : NativeTexture).write(bytes, texture.width * texture.format.bytesPerPixel());
	}

	public function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes> {
		var native:NativeBuffer = cast buffer.native;
		return lastDone.map(_ -> native.read(offset, size));
	}

	public function readTexture(texture:Texture):Future<Bytes> {
		if (frames.exists(texture.id))
			throw "a Metal window frame is only drawn into and presented: it cannot be read back";
		var native:NativeTexture = cast texture.native;
		var done = lastDone;
		#if !hxn_gpu_ios
		// Synchronize first, so the CPU copy of a managed texture has what the GPU wrote.
		if (texture.usage.has(RenderTarget) || texture.usage.has(Storage)) {
			var commands = queue.commandBuffer();
			commands.synchronize(native);
			done = commit(commands);
		}
		#end
		var row = texture.width * texture.format.bytesPerPixel();
		return done.map(_ -> native.read(row));
	}

	public function submit(steps:Array<Step>):Void {
		var commands = queue.commandBuffer();
		for (step in steps)
			switch (step) {
				case ComputeStep(list):
					compute(commands.computeEncoder(), list);
				case RenderStep(target, clear, list):
					render(commands.renderEncoder(cast target.native, hxn.gpu.metal.LoadAction.Clear, clear.r, clear.g, clear.b, clear.a), target, list);
				case CopyStep(_, _, _, _, _):
					throw "Metal has no buffer copies";
			}
		commit(commands);
	}

	public function completed():Future<hxn.Unit> {
		return lastDone;
	}

	public function createSurface(surface:GpuSurface):Void {
		switch (surface.target) {
			case Window(1 | 6, _):
				surface.native = new MetalSurface();
			case Window(platform, _):
				throw 'Metal presents to AppKit and UIKit windows, not platform $platform';
			case Canvas:
				throw "Metal has no web page canvas";
		}
	}

	public function surfaceFormat(surface:GpuSurface):TextureFormat
		return Bgra8Unorm;

	public function configureSurface(surface:GpuSurface):Void {
		var native:MetalSurface = cast surface.native;
		// A layer has one pixel format, so a new format takes a new layer.
		if (native.layer != null && native.format != surface.format) {
			native.layer.close();
			native.layer = null;
		}
		if (native.layer == null) {
			var view = switch (surface.target) {
				case Window(_, handles): handles[0];
				case Canvas: throw "Metal has no web page canvas";
			}
			native.layer = Layer.attach(device, view, format(surface.format));
			native.format = surface.format;
		}
		native.layer.setDrawableSize(surface.width, surface.height);
	}

	public function surfaceTexture(surface:GpuSurface):Texture {
		var native:MetalSurface = cast surface.native;
		var drawable = native.layer.nextDrawable();
		if (drawable == null)
			throw "the window's layer has no drawable to give";
		native.drawable = drawable;
		var frame = new Texture(surface.device, surface.width, surface.height, surface.format, RenderTarget);
		frame.native = drawable.texture();
		frames.set(frame.id, true);
		return frame;
	}

	public function present(surface:GpuSurface, frame:Texture):Void {
		var native:MetalSurface = cast surface.native;
		var drawable = native.drawable;
		native.drawable = null;
		frames.remove(frame.id);
		var commands = queue.commandBuffer();
		commands.present(drawable);
		commit(commands).then(_ -> {
			frame.close();
			drawable.close();
		}, _ -> drawable.close());
	}

	public function close():Void {
		idle();
		queue.close();
		device.close();
	}

	// Commits `commands` and records them as the last committed. The future settles when
	// they complete.
	function commit(commands:CommandBuffer):Future<hxn.Unit> {
		var done = (commands.completed());
		commands.commit();
		last = commands;
		lastDone = done;
		function release() {
			if (last == commands)
				last = null;
			commands.close();
		}
		done.then(_ -> release(), _ -> release());
		return done;
	}

	// Blocks until committed work finishes, so the CPU can write memory the GPU is using.
	function idle():Void {
		if (last != null)
			last.waitUntilCompleted();
	}

	function compute(encoder:ComputeEncoder, list:Array<Command>):Void {
		var pipeline:Null<ComputePipeline> = null;
		var groups = new Map<Int, BindGroup>();
		for (command in list)
			switch (command) {
				case SetComputePipeline(p):
					pipeline = p;
					encoder.setPipeline(cast p.native);
				case SetBindGroup(index, group):
					groups.set(index, group);
				case Dispatch(x, y, z):
					var entry = slotsOf(pipeline, pipeline.entryPoint.name);
					bind(entry, 4, groups, (r, e) -> switch (r.kind) {
						case "buffer": encoder.setBuffer(cast e.buffer.native, e.offset != null ? e.offset : 0, r.index);
						case "texture": encoder.setTexture(cast e.texture.native, r.index);
						case _: encoder.setSampler(cast e.sampler.native, r.index);
					});
					var sizes = sizesOf(entry, groups);
					if (sizes != null)
						encoder.setBytes(sizes, entry.sizesBuffer);
					var size = pipeline.entryPoint.workgroup;
					encoder.dispatchThreadgroups(x, y, z, size[0], size.length > 1 ? size[1] : 1, size.length > 2 ? size[2] : 1);
				case _:
			}
		encoder.end();
		encoder.close();
	}

	function render(encoder:RenderEncoder, target:Texture, list:Array<Command>):Void {
		var pipeline:Null<RenderPipeline> = null;
		var groups = new Map<Int, BindGroup>();
		encoder.setViewport(0, 0, target.width, target.height);
		for (command in list)
			switch (command) {
				case SetRenderPipeline(p):
					pipeline = p;
					encoder.setPipeline(cast p.native);
				case SetBindGroup(index, group):
					groups.set(index, group);
				case SetVertexBuffer(slot, buffer):
					encoder.setVertexBuffer(cast buffer.native, 0, VERTEX_BUFFERS - slot);
				case Draw(vertices, instances, first):
					var vertex = slotsOf(pipeline, pipeline.vertex.name);
					bind(vertex, 1, groups, (r, e) -> switch (r.kind) {
						case "buffer": encoder.setVertexBuffer(cast e.buffer.native, e.offset != null ? e.offset : 0, r.index);
						case _: throw "hxn-gpu-metal binds no textures or samplers to a vertex function";
					});
					var vertexSizes = sizesOf(vertex, groups);
					if (vertexSizes != null)
						encoder.setVertexBytes(vertexSizes, vertex.sizesBuffer);
					var fragment = slotsOf(pipeline, pipeline.fragment.name);
					bind(fragment, 2, groups, (r, e) -> switch (r.kind) {
						case "buffer": encoder.setFragmentBuffer(cast e.buffer.native, e.offset != null ? e.offset : 0, r.index);
						case "texture": encoder.setFragmentTexture(cast e.texture.native, r.index);
						case _: encoder.setFragmentSampler(cast e.sampler.native, r.index);
					});
					var fragmentSizes = sizesOf(fragment, groups);
					if (fragmentSizes != null)
						encoder.setFragmentBytes(fragmentSizes, fragment.sizesBuffer);
					encoder.draw(primitive(pipeline.topology), first, vertices, instances);
				case _:
			}
		encoder.end();
		encoder.close();
	}

	/**
		Calls `set` for each resource `entry` reads in `stage` (LAYOUT's
		visibility bit: 1 vertex, 2 fragment, 4 compute), with the bind group
		entry bound there.
	**/
	static function bind(entry:MslEntry, stage:Int, groups:Map<Int, BindGroup>, set:(MslResource, hxn.gpu.Descriptors.BindGroupEntry) -> Void):Void {
		for (resource in entry.resources) {
			var group = groups.get(resource.group);
			if (group == null)
				throw 'the pipeline reads bind group ${resource.group}, which is not set';
			var i = 0;
			while (i < group.entries.length && group.entries[i].binding != resource.binding)
				i++;
			if (group.layout[i].visibility & stage != 0)
				set(resource, group.entries[i]);
		}
	}

	/**
		The sizes buffer for `entry`: the byte length of each storage buffer it reads, in
		group and binding order.
	**/
	static function sizesOf(entry:MslEntry, groups:Map<Int, BindGroup>):Null<Bytes> {
		if (entry.sizesBuffer == null)
			return null;
		var storage = [];
		for (resource in entry.resources) {
			if (resource.kind != "buffer")
				continue;
			var group = groups.get(resource.group);
			var i = 0;
			while (group.entries[i].binding != resource.binding)
				i++;
			var type = group.layout[i].type;
			if (type == "storage" || type == "read-only-storage")
				storage.push({key: resource.group * 65536 + resource.binding, entry: group.entries[i]});
		}
		storage.sort((a, b) -> a.key - b.key);
		var sizes = Bytes.alloc(storage.length * 4);
		for (i in 0...storage.length) {
			var e = storage[i].entry;
			var offset = e.offset != null ? e.offset : 0;
			sizes.setInt32(i * 4, e.size != null ? e.size : e.buffer.size - offset);
		}
		return sizes;
	}

	static function slotsOf(pipeline:Pipeline, entryPoint:String):MslEntry {
		var found = Lambda.find(pipeline.shader.code.mslSlots, e -> e.entryPoint == entryPoint);
		if (found == null)
			throw '${pipeline.shader.code.name} has no MSL slots for $entryPoint';
		return found;
	}

	static function programOf(shader:ShaderModule):Program {
		return cast shader.native;
	}

	// macOS uses managed textures so the CPU can read what the GPU wrote; iOS has only
	// shared storage.
	static final STORAGE = #if hxn_gpu_ios hxn.gpu.metal.StorageMode.Shared #else hxn.gpu.metal.StorageMode.Managed #end;

	static function format(format:TextureFormat):hxn.gpu.metal.PixelFormat {
		return switch (format) {
			case R8Unorm: R8Unorm;
			case Rgba8Unorm: Rgba8Unorm;
			case Rgba8UnormSrgb: Rgba8UnormSrgb;
			case Bgra8Unorm: Bgra8Unorm;
			case Bgra8UnormSrgb: Bgra8UnormSrgb;
			case R32Float: R32Float;
			case Rgba16Float: Rgba16Float;
			case Rgba32Float: Rgba32Float;
		}
	}

	static function vertexFormat(format:VertexFormat):hxn.gpu.metal.VertexFormat {
		return switch (format) {
			case Float32: Float;
			case Float32x2: Float2;
			case Float32x3: Float3;
			case Float32x4: Float4;
			case Uint32: UInt;
			case Sint32: Int;
		}
	}

	static function primitive(topology:Topology):hxn.gpu.metal.Primitive {
		return switch (topology) {
			case PointList: Point;
			case LineList: Line;
			case LineStrip: LineStrip;
			case TriangleList: Triangle;
			case TriangleStrip: TriangleStrip;
		}
	}

	static function address(mode:AddressMode):hxn.gpu.metal.AddressMode {
		return switch (mode) {
			case ClampToEdge: ClampToEdge;
			case Repeat: Repeat;
			case MirrorRepeat: MirrorRepeat;
		}
	}
}
#end
