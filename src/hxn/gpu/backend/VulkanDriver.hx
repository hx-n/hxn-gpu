package hxn.gpu.backend;

#if hxn_gpu_vulkan
import hxn.gpu.Command;
import hxn.gpu.Limits.DefaultLimits;
import hxn.gpu.backend.Tracker;
import hxn.gpu.vulkan.Access as VkAccess;
import hxn.gpu.vulkan.BindPoint;
import hxn.gpu.vulkan.Buffer as NativeBuffer;
import hxn.gpu.vulkan.BufferUsage as NativeBufferUsage;
import hxn.gpu.vulkan.CommandBuffer;
import hxn.gpu.vulkan.Device as NativeDevice;
import hxn.gpu.vulkan.Image;
import hxn.gpu.vulkan.ImageUsage;
import hxn.gpu.vulkan.Instance;
import hxn.gpu.vulkan.Layout;
import hxn.gpu.vulkan.PipelineLayout;
import hxn.gpu.vulkan.SetLayouts;
import hxn.gpu.vulkan.ShaderModule as NativeModule;
import hxn.gpu.vulkan.Stage;
import haxe.io.Bytes;

/** A Vulkan shader: its module and the layouts of its descriptor sets. **/
private class Program {
	public final module:NativeModule;
	public final sets:SetLayouts;
	public final layout:PipelineLayout;

	public function new(module:NativeModule, sets:SetLayouts, layout:PipelineLayout) {
		this.module = module;
		this.sets = sets;
		this.layout = layout;
	}

	public function close():Void {
		layout.close();
		sets.close();
		module.close();
	}
}

/** A window's surface, and the swapchain made for it when it is configured. **/
private class VulkanSurface {
	public final surface:hxn.gpu.vulkan.Surface;
	public var swapchain:Null<hxn.gpu.vulkan.Swapchain>;
	public var format:Null<TextureFormat>;
	public var vsync = true;

	public function new(surface:hxn.gpu.vulkan.Surface) {
		this.surface = surface;
	}

	public function close():Void {
		if (swapchain != null)
			swapchain.close();
		surface.close();
	}
}

/**
	The Vulkan backend, over hxn-gpu-vulkan. The tracker turns each change in a resource's
	use into a pipeline barrier, including image layout transitions.
**/
class VulkanDriver implements Driver {
	public static final FEATURES:Features = [Compute, StorageTextures, TextureWrites, BindingOffsets, MultipleVertexBuffers, InstanceVertexBuffers, Presentation];

	public final backend:Backend = Vulkan;
	public final adapter:String;
	public final features:Features = FEATURES;
	public final limits:Limits = DefaultLimits.webgpu;

	final instance:Instance;
	final device:NativeDevice;
	final tracker = new Tracker();
	var lastDone:Future<hxn.Unit> = Future.resolved(hxn.Unit.Nothing);

	function new(instance:Instance, device:NativeDevice, adapter:String) {
		this.instance = instance;
		this.device = device;
		this.adapter = adapter;
	}

	public static function open(surface:Null<SurfaceTarget>):Future<Driver> {
		return Settled.attempt(() -> {
			var instance = Instance.create("hxn-gpu");
			// Prefer a hardware GPU; otherwise take the first device, which may be a
			// software renderer.
			var names = instance.adapterNames();
			if (names.length == 0) {
				instance.close();
				throw "Vulkan found no device";
			}
			var chosen = 0;
			for (i in 0...names.length)
				if (names[i].indexOf("llvmpipe") < 0) {
					chosen = i;
					break;
				}
			(new VulkanDriver(instance, instance.createDevice(chosen), names[chosen]) : Driver);
		});
	}

	public function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void {
		var usage = NativeBufferUsage.TransferSrc | NativeBufferUsage.TransferDst;
		if (buffer.usage.has(Vertex))
			usage |= NativeBufferUsage.Vertex;
		if (buffer.usage.has(Index))
			usage |= NativeBufferUsage.Index;
		if (buffer.usage.has(Uniform))
			usage |= NativeBufferUsage.Uniform;
		if (buffer.usage.has(Storage))
			usage |= NativeBufferUsage.Storage;
		var native = contents != null && contents.length == buffer.size ? device.createBufferWith(contents, usage) : device.createBuffer(buffer.size, usage);
		if (contents != null && contents.length < buffer.size)
			native.write(0, contents);
		buffer.native = native;
	}

	public function createTexture(texture:Texture):Void {
		var usage = ImageUsage.TransferSrc | ImageUsage.TransferDst;
		if (texture.usage.has(Sampled))
			usage |= ImageUsage.Sampled;
		if (texture.usage.has(Storage))
			usage |= ImageUsage.Storage;
		if (texture.usage.has(RenderTarget))
			usage |= texture.format.isDepth() ? ImageUsage.DepthAttachment : ImageUsage.ColorAttachment;
		texture.native = device.createImage({
			width: texture.width,
			height: texture.height,
			format: format(texture.format),
			usage: usage
		});
	}

	public function createSampler(sampler:Sampler):Void {
		var filter = sampler.filter == Linear ? hxn.gpu.vulkan.Filter.Linear : hxn.gpu.vulkan.Filter.Nearest;
		sampler.native = device.createSampler(filter, filter, address(sampler.address));
	}

	public function createShader(shader:ShaderModule):Void {
		var code = shader.code;
		if (code.spirv == null)
			throw '${code.name} has no SPIR-V: implement hxn.gpu.Shader';
		var sets = hxn.gpu.vulkan.Shaders.setLayouts(device, code.layout);
		shader.native = new Program(device.createShaderModule(code.spirv()), sets, device.createPipelineLayout(sets));
	}

	public function createComputePipeline(pipeline:ComputePipeline):Void {
		var program = programOf(pipeline.shader);
		pipeline.native = device.createComputePipeline(program.module, pipeline.entryPoint.name, program.layout);
	}

	public function createRenderPipeline(pipeline:RenderPipeline):Void {
		var program = programOf(pipeline.shader);
		var bindings:Array<hxn.gpu.vulkan.VertexBinding> = [];
		var attributes:Array<hxn.gpu.vulkan.VertexAttribute> = [];
		for (slot in 0...pipeline.vertexBuffers.length) {
			var buffer = pipeline.vertexBuffers[slot];
			bindings.push({binding: slot, stride: buffer.stride, perInstance: buffer.perInstance == true});
			for (a in buffer.attributes)
				attributes.push({
					location: a.location,
					binding: slot,
					format: vertexFormat(a.format),
					offset: a.offset
				});
		}
		var targets:Array<hxn.gpu.vulkan.ColorTarget> = [
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
				} : hxn.gpu.vulkan.ColorTarget);
			}
		];
		var depth = pipeline.depth;
		pipeline.native = device.createGraphicsPipelineWith(program.module, pipeline.vertex.name, program.module, pipeline.fragment.name, program.layout,
			targets, depth != null, depth != null ? format(depth.format) : D32Float, @:privateAccess pipeline.depthCompare(),
			@:privateAccess pipeline.depthWrite(), topology(pipeline.topology), bindings, attributes);
	}

	public function createBindGroup(group:BindGroup):Void {
		var set = device.createDescriptorSet(programOf(group.shader).sets, group.group);
		for (i in 0...group.entries.length) {
			var entry = group.entries[i];
			if (entry.buffer != null) {
				var offset = entry.offset != null ? entry.offset : 0;
				set.writeBuffer(entry.binding, cast entry.buffer.native, offset, entry.size != null ? entry.size : entry.buffer.size - offset);
			} else if (entry.texture != null)
				set.writeImage(entry.binding, cast entry.texture.native, group.layout[i].type == "texture" ? Layout.ShaderReadOnly : Layout.General);
			else
				set.writeSampler(entry.binding, cast entry.sampler.native);
		}
		group.native = set;
	}

	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		// Only the work that uses the buffer must finish before the CPU writes it.
		var use:Null<Future<hxn.Unit>> = buffer.use;
		if (use != null && !use.isReady())
			use.await();
		(cast buffer.native : NativeBuffer).write(offset, bytes);
	}

	// Copies the bytes through a staging buffer in a submission of their own, so the
	// write takes effect before the work submitted after it.
	public function writeTexture(texture:Texture, region:hxn.gpu.Descriptors.TextureRegion, bytes:Bytes, bytesPerRow:Int):Void {
		var pixel = texture.format.bytesPerPixel();
		var row = region.width * pixel;
		var data = bytes;
		var rowLength = Std.int(bytesPerRow / pixel);
		if (bytesPerRow % pixel != 0) {
			data = Bytes.alloc(row * region.height);
			for (y in 0...region.height)
				data.blit(y * row, bytes, y * bytesPerRow, row);
			rowLength = region.width;
		}
		var size = rowLength * pixel * (region.height - 1) + row;
		var staging = device.createBufferWith(data.sub(0, size), NativeBufferUsage.TransferSrc);
		var commands = device.createCommandBuffer();
		barrier(commands, texture, CopyDst, 0);
		commands.copyBufferToImage(staging, cast texture.native, region.x, region.y, region.width, region.height, rowLength);
		run(commands).then(_ -> staging.close(), _ -> staging.close());
	}

	public function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes> {
		var native:NativeBuffer = cast buffer.native;
		// Each submission ends with its writes made visible to the host.
		return lastDone.map(_ -> native.read(offset, size));
	}

	public function readTexture(texture:Texture):Future<Bytes> {
		var size = texture.width * texture.height * texture.format.bytesPerPixel();
		var staging = device.createBuffer(size, NativeBufferUsage.TransferDst);
		var commands = device.createCommandBuffer();
		barrier(commands, texture, CopySrc, 0);
		commands.copyImageToBuffer(cast texture.native, staging);
		commands.bufferBarrier(staging, Stage.Transfer, VkAccess.TransferWrite, Stage.Host, VkAccess.HostRead);
		return run(commands).map(_ -> {
			var pixels = staging.read(0, size);
			staging.close();
			pixels;
		});
	}

	public function submit(steps:Array<Step>):Void {
		var commands = device.createCommandBuffer();
		for (step in steps)
			switch (step) {
				case ComputeStep(list):
					compute(commands, list);
				case RenderStep(targets, list):
					render(commands, targets, list);
				case CopyStep(_, _, _, _, _):
					throw "Vulkan has no buffer copies";
			}
		Uses.mark(steps, run(commands));
	}

	public function completed():Future<hxn.Unit> {
		return lastDone;
	}

	public function createSurface(surface:GpuSurface):Void {
		switch (surface.target) {
			case Window(platform, handles):
				surface.native = new VulkanSurface(instance.createSurface(platform, handles[0], handles[1], handles[2], handles[3]));
			case Canvas:
				throw "Vulkan has no web page canvas";
		}
	}

	public function surfaceFormat(surface:GpuSurface):TextureFormat {
		return switch device.surfaceFormat((cast surface.native : VulkanSurface).surface) {
			case Rgba8Unorm: Rgba8Unorm;
			case _: Bgra8Unorm;
		}
	}

	public function configureSurface(surface:GpuSurface):Void {
		var native:VulkanSurface = cast surface.native;
		if (native.swapchain != null && native.format == surface.format && native.vsync == surface.vsync) {
			native.swapchain.resize(surface.width, surface.height);
			return;
		}
		idle();
		if (native.swapchain != null)
			native.swapchain.close();
		native.swapchain = device.createSwapchain(native.surface, surface.width, surface.height, format(surface.format), surface.vsync);
		native.format = surface.format;
		native.vsync = surface.vsync;
	}

	public function surfaceTexture(surface:GpuSurface):Texture {
		var swapchain = (cast surface.native : VulkanSurface).swapchain;
		var image = swapchain.acquire();
		var frame = new Texture(surface.device, swapchain.width(), swapchain.height(), surface.format, RenderTarget);
		frame.native = image;
		return frame;
	}

	public function present(surface:GpuSurface, frame:Texture):Void {
		var commands = device.createCommandBuffer();
		barrier(commands, frame, Present, 0);
		run(commands);
		var swapchain = (cast surface.native : VulkanSurface).swapchain;
		// The window changed size: the next frame needs a swapchain made for it.
		if (!swapchain.present())
			swapchain.resize(surface.width, surface.height);
		tracker.forget(frame.id);
		frame.close();
	}

	public function close():Void {
		idle();
		device.close();
		instance.close();
	}

	// Submits `commands` with a final barrier that makes all writes visible to the host.
	// The future settles when they complete.
	function run(commands:CommandBuffer):Future<hxn.Unit> {
		commands.memoryBarrier(Stage.AllCommands, VkAccess.MemoryWrite, Stage.Host, VkAccess.HostRead);
		var done = (device.submit(commands));
		lastDone = done;
		done.then(_ -> commands.close(), _ -> commands.close());
		return done;
	}

	// Blocks until submitted work finishes, so the CPU can write memory the GPU is using.
	function idle():Void {
		if (!lastDone.isReady())
			lastDone.await();
	}

	function compute(commands:CommandBuffer, list:Array<Command>):Void {
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
						Tracker.groupUses(group, (resource, access) -> barrier(commands, resource, access, Tracker.COMPUTE));
					commands.bindPipeline(BindPoint.Compute, cast pipeline.native);
					for (index => group in groups)
						commands.bindDescriptorSet(BindPoint.Compute, programOf(pipeline.shader).layout, index, cast group.native);
					commands.dispatch(x, y, z);
				case _:
			}
	}

	function render(commands:CommandBuffer, targets:hxn.gpu.Command.PassTargets, list:Array<Command>):Void {
		// Barriers can't be recorded inside dynamic rendering, so every transition the
		// pass needs is recorded before it begins.
		for (c in targets.colors)
			barrier(commands, c.target, RenderTarget, Tracker.GRAPHICS);
		if (targets.depth != null)
			barrier(commands, targets.depth.target, DepthTarget, Tracker.GRAPHICS);
		var groups = new Map<Int, BindGroup>();
		for (command in list)
			switch (command) {
				case SetBindGroup(index, group):
					groups.set(index, group);
				case SetVertexBuffer(_, buffer, _):
					barrier(commands, buffer, Vertex, Tracker.GRAPHICS);
				case Draw(_, _, _):
					for (group in groups)
						Tracker.groupUses(group, (resource, access) -> barrier(commands, resource, access, Tracker.GRAPHICS));
				case _:
			}
		var attachments = hxn.gpu.vulkan.Attachments.create();
		for (c in targets.colors)
			if (c.clear == null)
				attachments.color(cast c.target.native, hxn.gpu.vulkan.LoadOp.Load, 0, 0, 0, 0);
			else
				attachments.color(cast c.target.native, hxn.gpu.vulkan.LoadOp.Clear, c.clear.r, c.clear.g, c.clear.b, c.clear.a);
		var depth = targets.depth;
		if (depth != null)
			attachments.depth(cast depth.target.native, depth.clear == null ? hxn.gpu.vulkan.LoadOp.Load : hxn.gpu.vulkan.LoadOp.Clear,
				depth.clear == null ? 1 : depth.clear);
		commands.beginRenderingWith(attachments);
		attachments.close();
		var pipeline:Null<RenderPipeline> = null;
		groups.clear();
		for (command in list)
			switch (command) {
				case SetRenderPipeline(p):
					pipeline = p;
					commands.bindPipeline(BindPoint.Graphics, cast p.native);
				case SetBindGroup(index, group):
					groups.set(index, group);
				case SetVertexBuffer(slot, buffer, offset):
					commands.bindVertexBuffer(slot, cast buffer.native, offset);
				case SetViewport(x, y, width, height):
					commands.setViewport(x, y, width, height);
				case SetScissor(x, y, width, height):
					commands.setScissor(x, y, width, height);
				case Draw(vertices, instances, first):
					for (index => group in groups)
						commands.bindDescriptorSet(BindPoint.Graphics, programOf(pipeline.shader).layout, index, cast group.native);
					commands.draw(vertices, instances, first);
				case _:
			}
		commands.endRendering();
	}

	/** Records the barrier `resource` needs before it is used for `access` in `stages`, if it needs one. **/
	function barrier(commands:CommandBuffer, resource:Resource, access:Access, stages:Int):Void {
		var t = tracker.use(resource.id, access, stages);
		if (t == null)
			return;
		var before = t.before;
		var after = t.after;
		if (Std.isOfType(resource, Texture)) {
			var from = layoutOf(before.access);
			var to = layoutOf(after.access);
			if (from == to && !before.access.writes() && !after.access.writes())
				return;
			commands.imageBarrier(cast resource.native, stagesOf(before), accessOf(before.access), from, stagesOf(after), accessOf(after.access), to);
		} else {
			// Host writes are visible to a submission without a barrier; two reads need none.
			if (before.access == Untouched || (!before.access.writes() && !after.access.writes()))
				return;
			commands.bufferBarrier(cast resource.native, stagesOf(before), accessOf(before.access), stagesOf(after), accessOf(after.access));
		}
	}

	static function stagesOf(use:Use):Int {
		return switch (use.access) {
			case Untouched: Stage.TopOfPipe;
			case CopySrc | CopyDst: Stage.Transfer;
			case Vertex | Index: Stage.VertexInput;
			case RenderTarget: Stage.ColorAttachmentOutput;
			case DepthTarget: Stage.EarlyFragmentTests | Stage.LateFragmentTests;
			case Present: Stage.BottomOfPipe;
			case Uniform | StorageRead | StorageWrite | Sampled:
				var bits = 0;
				if (use.stages & Tracker.COMPUTE != 0)
					bits |= Stage.ComputeShader;
				if (use.stages & Tracker.GRAPHICS != 0)
					bits |= Stage.VertexShader | Stage.FragmentShader;
				bits;
		}
	}

	static function accessOf(access:Access):Int {
		return switch (access) {
			case Untouched: 0;
			case CopySrc: VkAccess.TransferRead;
			case CopyDst: VkAccess.TransferWrite;
			case Vertex: VkAccess.VertexAttributeRead;
			case Index: VkAccess.IndexRead;
			case Uniform: VkAccess.UniformRead;
			case StorageRead | Sampled: VkAccess.ShaderRead;
			case StorageWrite: VkAccess.ShaderRead | VkAccess.ShaderWrite;
			case RenderTarget: VkAccess.ColorAttachmentRead | VkAccess.ColorAttachmentWrite;
			case DepthTarget: VkAccess.DepthAttachmentRead | VkAccess.DepthAttachmentWrite;
			case Present: 0;
		}
	}

	static function layoutOf(access:Access):Layout {
		return switch (access) {
			case Untouched: Layout.Undefined;
			case CopySrc: Layout.TransferSrc;
			case CopyDst: Layout.TransferDst;
			case Sampled: Layout.ShaderReadOnly;
			case RenderTarget: Layout.ColorAttachment;
			case DepthTarget: Layout.DepthAttachment;
			case Present: Layout.Present;
			case _: Layout.General;
		}
	}

	static function programOf(shader:ShaderModule):Program {
		return cast shader.native;
	}

	static function format(format:TextureFormat):hxn.gpu.vulkan.Format {
		return switch (format) {
			case R8Unorm: R8Unorm;
			case Rgba8Unorm: Rgba8Unorm;
			case Rgba8UnormSrgb: Rgba8Srgb;
			case Bgra8Unorm: Bgra8Unorm;
			case Bgra8UnormSrgb: Bgra8Srgb;
			case R32Float: R32Float;
			case Rgba16Float: Rgba16Float;
			case Rgba32Float: Rgba32Float;
			case Depth32Float: D32Float;
		}
	}

	static function vertexFormat(format:VertexFormat):hxn.gpu.vulkan.Format {
		return switch (format) {
			case Float32: R32Float;
			case Float32x2: Rg32Float;
			case Float32x3: Rgb32Float;
			case Float32x4: Rgba32Float;
			case Uint32: R32Uint;
			case Sint32: R32Sint;
			case Unorm8x4: Rgba8Unorm;
		}
	}

	static function topology(topology:Topology):hxn.gpu.vulkan.Topology {
		return switch (topology) {
			case PointList: PointList;
			case LineList: LineList;
			case LineStrip: LineStrip;
			case TriangleList: TriangleList;
			case TriangleStrip: TriangleStrip;
		}
	}

	static function address(mode:AddressMode):hxn.gpu.vulkan.AddressMode {
		return switch (mode) {
			case ClampToEdge: ClampToEdge;
			case Repeat: Repeat;
			case MirrorRepeat: MirroredRepeat;
		}
	}
}
#end
