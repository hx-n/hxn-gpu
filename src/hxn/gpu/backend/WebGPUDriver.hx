package hxn.gpu.backend;

#if hxn_gpu_webgpu
import hxn.gpu.Command;
import hxn.gpu.Limits.DefaultLimits;
import hxn.gpu.webgpu.Adapter as NativeAdapter;
import hxn.gpu.webgpu.BindGroupEntries;
import hxn.gpu.webgpu.BindGroupLayouts;
import hxn.gpu.webgpu.Buffer as NativeBuffer;
import hxn.gpu.webgpu.BufferUsage as NativeBufferUsage;
import hxn.gpu.webgpu.ComputePass as NativeComputePass;
import hxn.gpu.webgpu.Device as NativeDevice;
import hxn.gpu.webgpu.Instance;
import hxn.gpu.webgpu.PipelineLayout;
import hxn.gpu.webgpu.RenderPass as NativeRenderPass;
import hxn.gpu.webgpu.ShaderModule as NativeModule;
import hxn.gpu.webgpu.Surface as NativeSurface;
import hxn.gpu.webgpu.Texture as NativeTexture;
import hxn.gpu.webgpu.TextureUsage as NativeTextureUsage;
import haxe.io.Bytes;

/** A WebGPU shader: its module and the layouts of its bind groups. **/
private class Program {
	public final module:NativeModule;
	public final groups:BindGroupLayouts;
	public final layout:PipelineLayout;

	public function new(module:NativeModule, groups:BindGroupLayouts, layout:PipelineLayout) {
		this.module = module;
		this.groups = groups;
		this.layout = layout;
	}

	public function close():Void {
		layout.close();
		groups.close();
		module.close();
	}
}

/** The WebGPU backend, over hxn-gpu-webgpu. **/
class WebGPUDriver implements Driver {
	public static final FEATURES:Features = [
		Compute, StorageTextures, TextureWrites, BindingOffsets, MultipleVertexBuffers, InstanceVertexBuffers, BufferCopies, PipelineConstants, Presentation
	];

	public final backend:Backend = WebGPU;
	public final adapter:String;
	public final features:Features = FEATURES;
	public final limits:Limits = DefaultLimits.webgpu;

	final instance:Instance;
	final gpuAdapter:NativeAdapter;
	final device:NativeDevice;

	function new(instance:Instance, gpuAdapter:NativeAdapter, device:NativeDevice) {
		this.instance = instance;
		this.gpuAdapter = gpuAdapter;
		this.device = device;
		adapter = gpuAdapter.info();
	}

	public static function open(surface:Null<SurfaceTarget>):Future<Driver> {
		var instance = Instance.create();
		var opened = instance.requestAdapter()
			.flatMap(adapter -> adapter.requestDevice().map(device -> (new WebGPUDriver(instance, adapter, device) : Driver)));
		// The canvas goes to the backend that opens, once it has, so a failed one leaves it to the next.
		return switch (surface) {
			case Canvas: opened.flatMap(driver -> instance.claimCanvas().map(_ -> driver));
			case _: opened;
		}
	}

	public function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void {
		var usage = NativeBufferUsage.CopySrc | NativeBufferUsage.CopyDst;
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
			device.writeBuffer(native, 0, contents);
		buffer.native = native;
	}

	public function createTexture(texture:Texture):Void {
		// Depth textures are drawn into and sampled, never copied.
		var usage = texture.format.isDepth() ? 0 : NativeTextureUsage.CopySrc | NativeTextureUsage.CopyDst;
		if (texture.usage.has(Sampled))
			usage |= NativeTextureUsage.TextureBinding;
		if (texture.usage.has(Storage))
			usage |= NativeTextureUsage.StorageBinding;
		if (texture.usage.has(RenderTarget))
			usage |= NativeTextureUsage.RenderAttachment;
		texture.native = device.createTexture(texture.width, texture.height, format(texture.format), usage);
	}

	public function createSampler(sampler:Sampler):Void {
		sampler.native = device.createSampler(sampler.filter == Linear ? hxn.gpu.webgpu.Filter.Linear : hxn.gpu.webgpu.Filter.Nearest, address(sampler.address));
	}

	public function createShader(shader:ShaderModule):Void {
		var wgsl = shader.code.wgsl;
		if (wgsl == null)
			throw '${shader.code.name} has no WGSL: implement hxn.gpu.Shader';
		var module = device.createShaderModule(wgsl);
		var groups = hxn.gpu.webgpu.Shaders.bindGroupLayouts(device, shader.code.layout);
		shader.native = new Program(module, groups, device.createPipelineLayout(groups));
	}

	public function createComputePipeline(pipeline:ComputePipeline):Void {
		var program = programOf(pipeline.shader);
		pipeline.native = device.createComputePipeline(program.module, pipeline.entryPoint.name, program.layout, constants(pipeline));
	}

	public function createRenderPipeline(pipeline:RenderPipeline):Void {
		var program = programOf(pipeline.shader);
		var buffers = [
			for (b in pipeline.vertexBuffers)
				({stride: b.stride, perInstance: b.perInstance == true} : hxn.gpu.webgpu.VertexBuffer)
		];
		var attributes = [
			for (i in 0...pipeline.vertexBuffers.length)
				for (a in pipeline.vertexBuffers[i].attributes)
					({location: a.location, format: vertexFormat(a.format), offset: a.offset, buffer: i} : hxn.gpu.webgpu.VertexAttribute)
		];
		var targets:Array<hxn.gpu.webgpu.ColorTarget> = [
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
				} : hxn.gpu.webgpu.ColorTarget);
			}
		];
		var depth = pipeline.depth;
		pipeline.native = device.createRenderPipelineWith(program.module, pipeline.vertex.name, pipeline.fragment.name, program.layout, targets,
			depth != null, depth != null ? format(depth.format) : Depth32Float, @:privateAccess pipeline.depthCompare(), @:privateAccess pipeline.depthWrite(),
			topology(pipeline.topology), buffers, attributes, constants(pipeline));
	}

	public function createBindGroup(group:BindGroup):Void {
		var entries = BindGroupEntries.create();
		for (entry in group.entries) {
			if (entry.buffer != null)
				entries.buffer(entry.binding, cast entry.buffer.native, entry.offset != null ? entry.offset : 0, entry.size != null ? entry.size : -1);
			else if (entry.texture != null)
				entries.texture(entry.binding, cast entry.texture.native);
			else
				entries.sampler(entry.binding, cast entry.sampler.native);
		}
		group.native = device.createBindGroup(programOf(group.shader).groups, group.group, entries);
		entries.close();
	}

	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		device.writeBuffer(cast buffer.native, offset, bytes);
	}

	public function writeTexture(texture:Texture, region:hxn.gpu.Descriptors.TextureRegion, bytes:Bytes, bytesPerRow:Int):Void {
		device.writeTextureRegion(cast texture.native, region.x, region.y, region.width, region.height, bytes, bytesPerRow);
	}

	public function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes> {
		var staging = device.createBuffer(size, NativeBufferUsage.MapRead | NativeBufferUsage.CopyDst);
		var encoder = device.createCommandEncoder();
		encoder.copyBufferToBuffer(cast buffer.native, offset, staging, 0, size);
		device.submit(encoder);
		encoder.close();
		return (staging.read(0, size)).map(bytes -> {
			staging.close();
			bytes;
		});
	}

	public function readTexture(texture:Texture):Future<Bytes> {
		var row = texture.width * texture.format.bytesPerPixel();
		// WebGPU requires the rows of a texture copy to be 256-byte aligned.
		var pitch = Std.int((row + 255) / 256) * 256;
		var staging = device.createBuffer(pitch * texture.height, NativeBufferUsage.MapRead | NativeBufferUsage.CopyDst);
		var encoder = device.createCommandEncoder();
		encoder.copyTextureToBuffer(cast texture.native, staging, pitch);
		device.submit(encoder);
		encoder.close();
		return (staging.read(0, pitch * texture.height)).map(padded -> {
			staging.close();
			var pixels = Bytes.alloc(row * texture.height);
			for (y in 0...texture.height)
				pixels.blit(y * row, padded, y * pitch, row);
			pixels;
		});
	}

	public function submit(steps:Array<Step>):Void {
		var encoder = device.createCommandEncoder();
		var passes:Array<{function close():Void;}> = [];
		for (step in steps)
			switch (step) {
				case ComputeStep(commands):
					var pass = encoder.beginComputePass();
					for (command in commands)
						switch (command) {
							case SetComputePipeline(p):
								pass.setPipeline(cast p.native);
							case SetBindGroup(index, group):
								pass.setBindGroup(index, cast group.native);
							case Dispatch(x, y, z):
								pass.dispatch(x, y, z);
							case _:
						}
					pass.end();
					passes.push(pass);
				case RenderStep(targets, commands):
					var attachments = hxn.gpu.webgpu.RenderTargets.create();
					for (c in targets.colors)
						if (c.clear == null)
							attachments.color(cast c.target.native, true, 0, 0, 0, 0);
						else
							attachments.color(cast c.target.native, false, c.clear.r, c.clear.g, c.clear.b, c.clear.a);
					var depth = targets.depth;
					if (depth != null)
						attachments.depth(cast depth.target.native, depth.clear == null, depth.clear == null ? 1 : depth.clear);
					var pass = encoder.beginRenderPassWith(attachments);
					attachments.close();
					for (command in commands)
						switch (command) {
							case SetRenderPipeline(p):
								pass.setPipeline(cast p.native);
							case SetBindGroup(index, group):
								pass.setBindGroup(index, cast group.native);
							case SetVertexBuffer(slot, buffer, offset):
								pass.setVertexBuffer(slot, cast buffer.native, offset);
							case SetViewport(x, y, width, height):
								pass.setViewport(x, y, width, height);
							case SetScissor(x, y, width, height):
								pass.setScissorRect(x, y, width, height);
							case Draw(vertices, instances, first):
								pass.draw(vertices, instances, first, 0);
							case _:
						}
					pass.end();
					passes.push(pass);
				case CopyStep(source, sourceOffset, destination, destinationOffset, size):
					encoder.copyBufferToBuffer(cast source.native, sourceOffset, cast destination.native, destinationOffset, size);
			}
		device.submit(encoder);
		for (pass in passes)
			pass.close();
		encoder.close();
	}

	public function createSurface(surface:GpuSurface):Void {
		switch (surface.target) {
			case Canvas:
				surface.native = instance.createCanvasSurface();
			case Window(_, _):
				throw "WebGPU presents to the web page's canvas, not a window";
		}
	}

	public function surfaceFormat(surface:GpuSurface):TextureFormat {
		var preferred = (cast surface.native : NativeSurface).preferredFormat(gpuAdapter);
		return preferred == hxn.gpu.webgpu.Format.Rgba8Unorm ? Rgba8Unorm : Bgra8Unorm;
	}

	public function configureSurface(surface:GpuSurface):Void {
		var usage = NativeTextureUsage.RenderAttachment | NativeTextureUsage.CopySrc;
		(cast surface.native : NativeSurface).configure(device, format(surface.format), usage, surface.width, surface.height);
	}

	public function surfaceTexture(surface:GpuSurface):Texture {
		var frame = new Texture(surface.device, surface.width, surface.height, surface.format, RenderTarget);
		frame.native = (cast surface.native : NativeSurface).currentTexture();
		return frame;
	}

	public function present(surface:GpuSurface, frame:Texture):Void {
		(cast surface.native : NativeSurface).present();
		frame.close();
	}

	public function completed():Future<hxn.Unit> {
		return (device.completed());
	}

	public function close():Void {
		device.close();
		gpuAdapter.close();
		instance.close();
	}

	static function constants(pipeline:Pipeline):Array<hxn.gpu.webgpu.Constant> {
		return [for (c in pipeline.constants) ({key: c.key, value: c.value} : hxn.gpu.webgpu.Constant)];
	}

	static function programOf(shader:ShaderModule):Program {
		return cast shader.native;
	}

	static function format(format:TextureFormat):hxn.gpu.webgpu.Format {
		return switch (format) {
			case R8Unorm: R8Unorm;
			case Rgba8Unorm: Rgba8Unorm;
			case Rgba8UnormSrgb: Rgba8UnormSrgb;
			case Bgra8Unorm: Bgra8Unorm;
			case Bgra8UnormSrgb: Bgra8UnormSrgb;
			case R32Float: R32Float;
			case Rgba16Float: Rgba16Float;
			case Rgba32Float: Rgba32Float;
			case Depth32Float: Depth32Float;
		}
	}

	static function vertexFormat(format:VertexFormat):hxn.gpu.webgpu.VertexFormat {
		return switch (format) {
			case Float32: Float32;
			case Float32x2: Float32x2;
			case Float32x3: Float32x3;
			case Float32x4: Float32x4;
			case Uint32: Uint32;
			case Sint32: Sint32;
		}
	}

	static function topology(topology:Topology):hxn.gpu.webgpu.Topology {
		return switch (topology) {
			case PointList: PointList;
			case LineList: LineList;
			case LineStrip: LineStrip;
			case TriangleList: TriangleList;
			case TriangleStrip: TriangleStrip;
		}
	}

	static function address(mode:AddressMode):hxn.gpu.webgpu.AddressMode {
		return switch (mode) {
			case ClampToEdge: ClampToEdge;
			case Repeat: Repeat;
			case MirrorRepeat: MirrorRepeat;
		}
	}
}
#end
