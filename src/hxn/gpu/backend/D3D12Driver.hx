package hxn.gpu.backend;

#if hxn_gpu_d3d12
import hxn.gpu.Command;
import hxn.gpu.Limits.DefaultLimits;
import hxn.gpu.backend.Tracker;
import hxn.gpu.d3d12.Buffer as NativeBuffer;
import hxn.gpu.d3d12.CommandList;
import hxn.gpu.d3d12.DescriptorHeap;
import hxn.gpu.d3d12.Device as NativeDevice;
import hxn.gpu.d3d12.Factory;
import hxn.gpu.d3d12.Heap;
import hxn.gpu.d3d12.HeapKind;
import hxn.gpu.d3d12.ParameterKind;
import hxn.gpu.d3d12.PipelineState;
import hxn.gpu.d3d12.RootLayout;
import hxn.gpu.d3d12.RootSignature;
import hxn.gpu.d3d12.State;
import hxn.gpu.d3d12.Swapchain;
import hxn.gpu.d3d12.Texture as NativeTexture;
import haxe.io.Bytes;

/**
	A buffer and whether it is in an upload heap. Upload-heap buffers are CPU-writable and
	never change state.
**/
private class Memory {
	public final buffer:NativeBuffer;
	public final upload:Bool;

	public function new(buffer:NativeBuffer, upload:Bool) {
		this.buffer = buffer;
		this.upload = upload;
	}

	public function close():Void
		buffer.close();
}

/** A sampler: its descriptor in the device's sampler heap. **/
private class SamplerSlot {
	public final index:Int;

	public function new(index:Int) {
		this.index = index;
	}

	public function close():Void {}
}

/** A shader's root layout, root signature and bytecode per entry point. **/
private class Program {
	public final layout:RootLayout;
	public final signature:RootSignature;
	public final bytecode = new Map<String, Bytes>();

	public function new(layout:RootLayout, signature:RootSignature) {
		this.layout = layout;
		this.signature = signature;
	}

	public function close():Void
		signature.close();
}

/** A window's swap chain, made when the surface is configured and remade on a resize. **/
private class Chain {
	public var swapchain:Null<Swapchain>;

	public function new() {}

	public function close():Void
		if (swapchain != null)
			swapchain.close();
}

/** A bind group's first descriptor in the resource heap, and its sampler index array. **/
private class Group {
	public final textures:Int;
	public final samplerIndices:Null<NativeBuffer>;

	public function new(textures:Int, samplerIndices:Null<NativeBuffer>) {
		this.textures = textures;
		this.samplerIndices = samplerIndices;
	}

	public function close():Void
		if (samplerIndices != null)
			samplerIndices.close();
}

/**
	The Direct3D 12 backend, over hxn-gpu-d3d12. The tracker turns each change in a
	resource's use into a state transition, and back-to-back shader writes into a UAV
	barrier. Uniform and vertex buffers live in upload heaps the CPU writes directly;
	storage buffers live in the default heap and are written through staging buffers.
**/
class D3D12Driver implements Driver {
	public static final FEATURES:Features = [Compute, TextureWrites, MultipleVertexBuffers, InstanceVertexBuffers, Presentation];

	/** The buffers of a window's swap chain. **/
	static inline final SWAP_BUFFERS = 2;

	/**
		Size of the device's shader-visible resource heap, which all bind groups' textures
		share.
	**/
	static inline final RESOURCE_DESCRIPTORS = 4096;

	public final backend:Backend = D3D12;
	public final adapter:String;
	public final features:Features = FEATURES;
	public final limits:Limits = DefaultLimits.webgpu;

	final factory:Factory;
	final device:NativeDevice;
	final tracker = new Tracker();
	final resources:DescriptorHeap;
	final samplers:DescriptorHeap;
	var nextResource = 0;
	var nextSampler = 0;
	var lastDone:Future<hxn.Unit> = Future.resolved(hxn.Unit.Nothing);

	function new(factory:Factory, device:NativeDevice, adapter:String) {
		this.factory = factory;
		this.device = device;
		this.adapter = adapter;
		resources = device.createDescriptorHeap(HeapKind.Resources, RESOURCE_DESCRIPTORS);
		samplers = device.createDescriptorHeap(HeapKind.Samplers, RootLayout.SAMPLER_HEAP_SIZE);
	}

	public static function open(surface:Null<SurfaceTarget>):Future<Driver> {
		return Settled.attempt(() -> {
			var factory = Factory.create();
			// Prefer a hardware adapter; fall back to WARP.
			var names = factory.adapterNames();
			var chosen = names.length - 1;
			for (i in 0...names.length)
				if (!factory.isSoftware(i)) {
					chosen = i;
					break;
				}
			var device = try factory.createDevice(chosen) catch (e:haxe.Exception) {
				factory.close();
				throw e;
			}
			(new D3D12Driver(factory, device, names[chosen]) : Driver);
		});
	}

	public function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void {
		if (!buffer.usage.has(Storage)) {
			var native = device.createBuffer(buffer.size, Heap.Upload, State.GenericRead, false);
			if (contents != null)
				native.write(0, contents);
			buffer.native = new Memory(native, true);
			return;
		}
		buffer.native = new Memory(device.createBuffer(buffer.size, Heap.Default, State.Common, true), false);
		if (contents != null)
			writeBuffer(buffer, 0, contents);
	}

	public function createTexture(texture:Texture):Void {
		var usage = 0;
		if (texture.usage.has(RenderTarget))
			usage |= texture.format.isDepth() ? hxn.gpu.d3d12.TextureUsage.DepthStencil : hxn.gpu.d3d12.TextureUsage.RenderTarget;
		texture.native = device.createTexture({
			width: texture.width,
			height: texture.height,
			format: format(texture.format),
			usage: usage
		});
	}

	public function createSampler(sampler:Sampler):Void {
		if (nextSampler == RootLayout.SAMPLER_HEAP_SIZE)
			throw 'Direct3D 12 holds ${RootLayout.SAMPLER_HEAP_SIZE} samplers';
		var index = nextSampler++;
		samplers.writeSampler(index, sampler.filter == Linear ? hxn.gpu.d3d12.Filter.Linear : hxn.gpu.d3d12.Filter.Nearest, address(sampler.address));
		sampler.native = new SamplerSlot(index);
	}

	public function createShader(shader:ShaderModule):Void {
		var code = shader.code;
		if (code.hlsl == null)
			throw '${code.name} has no HLSL: implement hxn.gpu.Shader';
		var layout = new RootLayout(code.hlslSlots, code.layout);
		shader.native = new Program(layout, device.createRootSignature(layout.parameters));
	}

	public function createComputePipeline(pipeline:ComputePipeline):Void {
		var program = programOf(pipeline.shader);
		pipeline.native = device.createComputePipeline(bytecode(pipeline.shader, pipeline.entryPoint.name, "compute"), program.signature);
	}

	public function createRenderPipeline(pipeline:RenderPipeline):Void {
		var program = programOf(pipeline.shader);
		var attributes:Array<hxn.gpu.d3d12.VertexAttribute> = [];
		for (slot in 0...pipeline.vertexBuffers.length)
			for (a in pipeline.vertexBuffers[slot].attributes)
				attributes.push({
					location: a.location,
					slot: slot,
					format: vertexFormat(a.format),
					offset: a.offset,
					perInstance: pipeline.vertexBuffers[slot].perInstance == true
				});
		var targets:Array<hxn.gpu.d3d12.ColorTarget> = [
			for (i in 0...pipeline.targets.length) {
				var b = @:privateAccess pipeline.blendCodes(i);
				({
					format: format(pipeline.targets[i].format),
					enabled: b[0] == 1,
					colorOperation: b[1],
					colorSource: b[2],
					colorDestination: b[3],
					alphaOperation: b[4],
					alphaSource: b[5],
					alphaDestination: b[6]
				} : hxn.gpu.d3d12.ColorTarget);
			}
		];
		var depth = pipeline.depth;
		pipeline.native = device.createGraphicsPipelineWith(bytecode(pipeline.shader, pipeline.vertex.name, "vertex"),
			bytecode(pipeline.shader, pipeline.fragment.name, "fragment"), program.signature, targets, depth != null,
			depth != null ? format(depth.format) : D32Float, @:privateAccess pipeline.depthCompare(), @:privateAccess pipeline.depthWrite(),
			topology(pipeline.topology), attributes);
	}

	public function createBindGroup(group:BindGroup):Void {
		var layout = programOf(group.shader).layout;
		var textures = -1;
		var indices = new Map<Int, Int>();
		for (i in 0...group.entries.length) {
			var entry = group.entries[i];
			if (entry.texture != null) {
				if (textures < 0) {
					var count = layout.textureCount(group.group);
					if (nextResource + count > RESOURCE_DESCRIPTORS)
						throw 'Direct3D 12 holds $RESOURCE_DESCRIPTORS texture descriptors';
					textures = nextResource;
					nextResource += count;
				}
				resources.writeTexture(textures + layout.textureOffset(group.group, entry.binding), cast entry.texture.native);
			} else if (entry.sampler != null)
				indices.set(entry.binding, (cast entry.sampler.native : SamplerSlot).index);
		}
		var array = indices.keys().hasNext() ? device.createBufferWith(RootLayout.samplerIndexArray(indices)) : null;
		group.native = new Group(textures, array);
	}

	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		var memory = memoryOf(buffer);
		if (memory.upload) {
			idle();
			memory.buffer.write(offset, bytes);
			return;
		}
		// copyBuffer copies whole buffers, so a partial write reads the current contents
		// back and merges into them.
		var whole = bytes;
		if (offset != 0 || bytes.length != buffer.size) {
			whole = readBuffer(buffer, 0, buffer.size).await();
			whole.blit(offset, bytes, 0, bytes.length);
		}
		var staging = device.createBufferWith(whole);
		var commands = device.createCommandList();
		transition(commands, buffer, CopyDst, 0);
		commands.copyBuffer(memory.buffer, staging);
		run(commands).then(_ -> staging.close(), _ -> staging.close());
	}

	// Direct3D 12 copies texture rows that are 256 bytes apart, so the staging buffer
	// holds the rows at that pitch.
	public function writeTexture(texture:Texture, region:hxn.gpu.Descriptors.TextureRegion, bytes:Bytes, bytesPerRow:Int):Void {
		var native:NativeTexture = cast texture.native;
		var row = region.width * texture.format.bytesPerPixel();
		var pitch = Std.int((row + 255) / 256) * 256;
		var padded = Bytes.alloc(pitch * region.height);
		for (y in 0...region.height)
			padded.blit(y * pitch, bytes, y * bytesPerRow, row);
		var staging = device.createBufferWith(padded);
		var commands = device.createCommandList();
		transition(commands, texture, CopyDst, 0);
		commands.copyBufferToTextureRegion(native, staging, region.x, region.y, region.width, region.height);
		run(commands).then(_ -> staging.close(), _ -> staging.close());
	}

	public function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes> {
		// The CPU reads only readback heaps, so every buffer is copied into one; an
		// upload heap buffer can be copied from in the one state it keeps.
		var memory = memoryOf(buffer);
		var readback = device.createBuffer(buffer.size, Heap.Readback, 0, false);
		var commands = device.createCommandList();
		transition(commands, buffer, CopySrc, 0);
		commands.copyBuffer(readback, memory.buffer);
		return run(commands).map(_ -> {
			var bytes = readback.read(offset, size);
			readback.close();
			bytes;
		});
	}

	public function readTexture(texture:Texture):Future<Bytes> {
		var native:NativeTexture = cast texture.native;
		var row = texture.width * texture.format.bytesPerPixel();
		var pitch = native.copyPitch();
		var readback = device.createBuffer(pitch * texture.height, Heap.Readback, 0, false);
		var commands = device.createCommandList();
		transition(commands, texture, CopySrc, 0);
		commands.copyTextureToBuffer(native, readback);
		return run(commands).map(_ -> {
			var padded = readback.read(0, pitch * texture.height);
			readback.close();
			var pixels = Bytes.alloc(row * texture.height);
			for (y in 0...texture.height)
				pixels.blit(y * row, padded, y * pitch, row);
			pixels;
		});
	}

	public function submit(steps:Array<Step>):Void {
		var commands = device.createCommandList();
		commands.setDescriptorHeaps(resources, samplers);
		for (step in steps)
			switch (step) {
				case ComputeStep(list):
					compute(commands, list);
				case RenderStep(targets, list):
					render(commands, targets, list);
				case CopyStep(_, _, _, _, _):
					throw "Direct3D 12 has no buffer copies in hxn-gpu";
			}
		run(commands);
	}

	public function completed():Future<hxn.Unit> {
		return lastDone;
	}

	public function createSurface(surface:GpuSurface):Void {
		switch (surface.target) {
			case Window(2, _):
				surface.native = new Chain();
			case Window(platform, _):
				throw 'Direct3D 12 presents to Win32 windows, not platform $platform';
			case Canvas:
				throw "Direct3D 12 has no web page canvas";
		}
	}

	public function surfaceFormat(surface:GpuSurface):TextureFormat
		return Bgra8Unorm;

	public function configureSurface(surface:GpuSurface):Void {
		var chain:Chain = cast surface.native;
		// The swap chain's buffers may still be drawn into or shown.
		idle();
		if (chain.swapchain != null)
			chain.swapchain.close();
		var window = switch (surface.target) {
			case Window(_, handles): handles[0];
			case Canvas: throw "Direct3D 12 has no web page canvas";
		}
		chain.swapchain = factory.createSwapchain(device, window, surface.width, surface.height, format(surface.format), SWAP_BUFFERS);
	}

	public function surfaceTexture(surface:GpuSurface):Texture {
		var swapchain = (cast surface.native : Chain).swapchain;
		var frame = new Texture(surface.device, surface.width, surface.height, surface.format, RenderTarget);
		frame.native = swapchain.buffer(swapchain.currentIndex());
		return frame;
	}

	public function present(surface:GpuSurface, frame:Texture):Void {
		var commands = device.createCommandList();
		transition(commands, frame, Present, 0);
		run(commands);
		(cast surface.native : Chain).swapchain.present(surface.vsync ? 1 : 0);
		tracker.forget(frame.id);
		frame.close();
	}

	public function close():Void {
		idle();
		samplers.close();
		resources.close();
		device.close();
		factory.close();
	}

	// Executes `commands` after earlier work. The future settles when they complete.
	function run(commands:CommandList):Future<hxn.Unit> {
		var done = (device.execute(commands));
		lastDone = done;
		done.then(_ -> commands.close(), _ -> commands.close());
		return done;
	}

	// Blocks until executed work finishes, so the CPU can write memory the GPU is using.
	function idle():Void {
		if (!lastDone.isReady())
			lastDone.await();
	}

	function compute(commands:CommandList, list:Array<Command>):Void {
		var pipeline:Null<ComputePipeline> = null;
		var groups = new Map<Int, BindGroup>();
		for (command in list)
			switch (command) {
				case SetComputePipeline(p):
					pipeline = p;
				case SetBindGroup(index, group):
					groups.set(index, group);
				case Dispatch(x, y, z):
					for (group in groups)
						Tracker.groupUses(group, (resource, access) -> transition(commands, resource, access, Tracker.COMPUTE));
					var program = programOf(pipeline.shader);
					commands.setComputeRootSignature(program.signature);
					commands.setPipelineState(cast pipeline.native);
					bindGroups(program, groups, (index, kind, buffer) -> commands.setComputeRootBuffer(index, kind, buffer),
						(index, heap, offset) -> commands.setComputeRootTable(index, heap, offset));
					commands.dispatch(x, y, z);
				case _:
			}
	}

	function render(commands:CommandList, targets:hxn.gpu.Command.PassTargets, list:Array<Command>):Void {
		for (c in targets.colors)
			transition(commands, c.target, RenderTarget, Tracker.GRAPHICS);
		if (targets.depth != null)
			transition(commands, targets.depth.target, DepthTarget, Tracker.GRAPHICS);
		var groups = new Map<Int, BindGroup>();
		for (command in list)
			switch (command) {
				case SetBindGroup(index, group):
					groups.set(index, group);
				case Draw(_, _, _):
					for (group in groups)
						Tracker.groupUses(group, (resource, access) -> transition(commands, resource, access, Tracker.GRAPHICS));
				case _:
			}
		var attachments = hxn.gpu.d3d12.RenderTargets.create();
		for (c in targets.colors)
			if (c.clear == null)
				attachments.color(cast c.target.native, true, 0, 0, 0, 0);
			else
				attachments.color(cast c.target.native, false, c.clear.r, c.clear.g, c.clear.b, c.clear.a);
		var depth = targets.depth;
		if (depth != null)
			attachments.depth(cast depth.target.native, depth.clear == null, depth.clear == null ? 1 : depth.clear);
		commands.setRenderTargets(attachments);
		attachments.close();
		var pipeline:Null<RenderPipeline> = null;
		groups.clear();
		for (command in list)
			switch (command) {
				case SetRenderPipeline(p):
					pipeline = p;
					commands.setGraphicsRootSignature(programOf(p.shader).signature);
					commands.setPipelineState(cast p.native);
					commands.setTopology(topology(p.topology));
				case SetBindGroup(index, group):
					groups.set(index, group);
				case SetVertexBuffer(slot, buffer, offset):
					commands.setVertexBuffer(slot, memoryOf(buffer).buffer, pipeline.vertexBuffers[slot].stride, offset);
				case SetViewport(x, y, width, height):
					commands.setViewport(x, y, width, height);
				case SetScissor(x, y, width, height):
					commands.setScissor(x, y, width, height);
				case Draw(vertices, instances, first):
					bindGroups(programOf(pipeline.shader), groups, (index, kind, buffer) -> commands.setGraphicsRootBuffer(index, kind, buffer),
						(index, heap, offset) -> commands.setGraphicsRootTable(index, heap, offset));
					commands.draw(vertices, instances, first);
				case _:
			}
	}

	/** Sets the root parameters of every group in `groups`, through `setBuffer` and `setTable`. **/
	function bindGroups(program:Program, groups:Map<Int, BindGroup>, setBuffer:(Int, ParameterKind, NativeBuffer) -> Void,
			setTable:(Int, DescriptorHeap, Int) -> Void):Void {
		var layout = program.layout;
		var sampled = false;
		for (g => group in groups) {
			var native:Group = cast group.native;
			for (i in 0...group.entries.length) {
				var entry = group.entries[i];
				switch (group.layout[i].type) {
					case "uniform":
						setBuffer(layout.buffer(g, entry.binding), ParameterKind.ConstantBuffer, memoryOf(entry.buffer).buffer);
					case "storage":
						setBuffer(layout.buffer(g, entry.binding), ParameterKind.UnorderedAccess, memoryOf(entry.buffer).buffer);
					case "read-only-storage":
						setBuffer(layout.buffer(g, entry.binding), ParameterKind.ShaderResource, memoryOf(entry.buffer).buffer);
					case _:
				}
			}
			if (native.textures >= 0)
				setTable(layout.textureTable(g), resources, native.textures);
			if (native.samplerIndices != null) {
				setBuffer(layout.samplerIndices(g), ParameterKind.ShaderResource, native.samplerIndices);
				sampled = true;
			}
		}
		if (sampled) {
			setTable(layout.samplerHeap, samplers, 0);
			setTable(layout.comparisonSamplerHeap, samplers, 0);
		}
	}

	/** Records the transition `resource` needs before it is used for `access` in `stages`. **/
	function transition(commands:CommandList, resource:Resource, access:Access, stages:Int):Void {
		var buffer = Std.isOfType(resource, Buffer);
		// Upload-heap buffers keep their initial state.
		if (buffer && (cast resource.native : Memory).upload)
			return;
		var t = tracker.use(resource.id, access, stages);
		if (t == null)
			return;
		var before = stateOf(t.before);
		var after = stateOf(t.after);
		if (before == after) {
			if (buffer && t.before.access == StorageWrite)
				commands.uavBarrier((cast resource.native : Memory).buffer);
			return;
		}
		if (buffer)
			commands.transitionBuffer((cast resource.native : Memory).buffer, before, after);
		else
			commands.transitionTexture(cast resource.native, before, after);
	}

	static function stateOf(use:Use):Int {
		return switch (use.access) {
			case Untouched: State.Common;
			case CopySrc: State.CopySource;
			case CopyDst: State.CopyDest;
			case Vertex | Uniform: State.VertexAndConstantBuffer;
			case Index: State.IndexBuffer;
			case StorageWrite: State.UnorderedAccess;
			case RenderTarget: State.RenderTarget;
			case DepthTarget: State.DepthWrite;
			case Present: State.Common;
			case StorageRead | Sampled:
				use.stages & Tracker.GRAPHICS != 0 ? State.NonPixelShaderResource | State.PixelShaderResource : State.NonPixelShaderResource;
		}
	}

	function bytecode(shader:ShaderModule, entry:String, stage:String):Bytes {
		var program = programOf(shader);
		var found = program.bytecode.get(entry);
		if (found == null) {
			var code = shader.code;
			found = hxn.gpu.d3d12.Shaders.bytecode(device, code.dxil != null ? code.dxil(entry) : null, code.hlsl, entry, stage);
			program.bytecode.set(entry, found);
		}
		return found;
	}

	static function memoryOf(buffer:Buffer):Memory {
		return cast buffer.native;
	}

	static function programOf(shader:ShaderModule):Program {
		return cast shader.native;
	}

	static function format(format:TextureFormat):hxn.gpu.d3d12.Format {
		return switch (format) {
			case R8Unorm: R8Unorm;
			case Rgba8Unorm: Rgba8Unorm;
			case Rgba8UnormSrgb: Rgba8UnormSrgb;
			case Bgra8Unorm: Bgra8Unorm;
			case Bgra8UnormSrgb: Bgra8UnormSrgb;
			case R32Float: R32Float;
			case Rgba16Float: Rgba16Float;
			case Rgba32Float: Rgba32Float;
			case Depth32Float: D32Float;
		}
	}

	static function vertexFormat(format:VertexFormat):hxn.gpu.d3d12.Format {
		return switch (format) {
			case Float32: R32Float;
			case Float32x2: Rg32Float;
			case Float32x3: Rgb32Float;
			case Float32x4: Rgba32Float;
			case Uint32: R32Uint;
			case Sint32: R32Sint;
		}
	}

	static function topology(topology:Topology):hxn.gpu.d3d12.Topology {
		return switch (topology) {
			case PointList: PointList;
			case LineList: LineList;
			case LineStrip: LineStrip;
			case TriangleList: TriangleList;
			case TriangleStrip: TriangleStrip;
		}
	}

	static function address(mode:AddressMode):hxn.gpu.d3d12.AddressMode {
		return switch (mode) {
			case ClampToEdge: Clamp;
			case Repeat: Wrap;
			case MirrorRepeat: Mirror;
		}
	}
}
#end
