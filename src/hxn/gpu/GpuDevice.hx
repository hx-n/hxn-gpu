package hxn.gpu;

import hxn.gpu.Descriptors;
import hxn.gpu.backend.Driver;
import haxe.Exception;
import haxe.io.Bytes;
import hxnsl.Layout.LayoutEntry;

typedef OpenOptions = {
	/** Features the device must have. Backends without them are skipped. **/
	final ?required:Features;
	/**
		The backends to try, in order. Overrides `HXN_GPU_BACKEND`,
		`-D hxn_gpu_backend` and the platform's default order, which
		`GpuDevice.defaultBackends()` returns.
	**/
	final ?backends:Array<Backend>;

	/**
		Receives the warning `open` gives when a backend fails to open and a
		later one is used. By default it goes to standard error, which a web
		page shows in its console. Pass `_ -> {}` to drop it.
	**/
	final ?warn:String->Void;
}

/**
	A GPU device on one backend, opened with `GpuDevice.open`. It creates resources and
	pipelines and runs submitted commands in order. Buffer and texture reads and writes
	are ordered with submissions: a write is visible to work submitted after it, and a
	read sees the results of work submitted before it.

	`features` and `limits` say what the device can do. A call that lacks a feature throws
	and names the feature and the backend.

	Add a driver haxelib for each backend to support, such as `-lib hxn-gpu-metal -lib
	hxn-gpu-vulkan`. Only those backends are compiled in, and `open` uses the first one
	that initializes.
**/
class GpuDevice {
	static final openers:Array<{backend:Backend, features:Features, open:() -> Future<Driver>}> = [
		#if hxn_gpu_metal
		{backend: Metal, features: hxn.gpu.backend.MetalDriver.FEATURES, open: hxn.gpu.backend.MetalDriver.open},
		#end
		#if hxn_gpu_d3d12
		{backend: D3D12, features: hxn.gpu.backend.D3D12Driver.FEATURES, open: hxn.gpu.backend.D3D12Driver.open},
		#end
		#if hxn_gpu_vulkan
		{backend: Vulkan, features: hxn.gpu.backend.VulkanDriver.FEATURES, open: hxn.gpu.backend.VulkanDriver.open},
		#end
		#if hxn_gpu_gles
		{backend: Gles, features: hxn.gpu.backend.GlDriver.FEATURES, open: hxn.gpu.backend.GlDriver.open},
		#end
		#if hxn_gpu_webgpu
		{backend: WebGPU, features: hxn.gpu.backend.WebGPUDriver.FEATURES, open: hxn.gpu.backend.WebGPUDriver.open},
		#end
		#if hxn_gpu_webgl2
		{backend: WebGL2, features: hxn.gpu.backend.GlDriver.FEATURES, open: hxn.gpu.backend.GlDriver.open},
		#end
	];


	public final backend:Backend;
	/** The adapter's name, as the driver reports it. **/
	public final adapter:String;
	public final features:Features;
	public final limits:Limits;
	@:allow(hxn.gpu) final driver:Driver;
	var closed = false;

	/** The compiled-in backends. **/
	public static function backends():Array<Backend> {
		return [for (o in openers) o.backend];
	}

	/**
		The compiled-in backends in the order `open` tries them by default.
		Apple platforms prefer Metal, Windows prefers Direct3D 12, other native
		platforms prefer Vulkan, and each falls back to Vulkan and then GLES.
		The browser prefers WebGPU and falls back to WebGL2.

		`HXN_GPU_BACKEND` at run time, or `-D hxn_gpu_backend` at compile time,
		replaces this order with a comma-separated list such as `vulkan,gles`.
		The environment variable wins when both are set.
	**/
	public static function defaultBackends():Array<Backend> {
		var named = Sys.getEnv("HXN_GPU_BACKEND");
		if (named == null || named == "")
			named = haxe.macro.Compiler.getDefine("hxn_gpu_backend");
		if (named != null && named != "" && named != "1")
			return [for (name in named.split(",")) backendNamed(StringTools.trim(name))];
		var compiled = backends();
		var order = [for (b in platformOrder()) if (compiled.indexOf(b) >= 0) b];
		for (b in compiled)
			if (order.indexOf(b) < 0)
				order.push(b);
		return order;
	}

	static function warning(message:String):Void {
		Sys.stderr().writeString(message + "\n");
	}

	static function platformOrder():Array<Backend> {
		#if (emscripten || wasm)
		return [WebGPU, WebGL2];
		#else
		var system = #if hxn_gpu_ios "iOS" #else Sys.systemName() #end;
		return switch (system) {
			case "Mac" | "iOS": [Metal, Vulkan, Gles];
			case "Windows": [D3D12, Vulkan, Gles];
			case _: [Vulkan, Gles];
		}
		#end
	}

	static function backendNamed(name:String):Backend {
		for (b in ([Metal, Vulkan, D3D12, Gles, WebGPU, WebGL2] : Array<Backend>))
			if ((b : String) == name.toLowerCase())
				return b;
		throw 'no backend is named $name: the names are metal, vulkan, d3d12, gles, webgpu and webgl2';
	}

	/** The features of `backend`'s devices, without opening one. **/
	public static function featuresOf(backend:Backend):Features {
		var found = Lambda.find(openers, o -> o.backend == backend);
		if (found == null)
			throw '$backend is not compiled in: add -lib hxn-gpu-$backend';
		return found.features;
	}

	/**
		Opens a device on the first backend that has the `options.required`
		features and initializes, trying `options.backends` or, by default,
		`defaultBackends()` in order. If none does, the future fails with the
		reason for each backend.
	**/
	public static function open(?options:OpenOptions):Future<GpuDevice> {
		var required = options != null && options.required != null ? options.required : Features.none;
		var order = options != null && options.backends != null ? options.backends : defaultBackends();
		var candidates = [];
		for (backend in order) {
			var found = Lambda.find(openers, o -> o.backend == backend);
			if (found == null)
				throw '$backend is not compiled in: add -lib hxn-gpu-$backend';
			candidates.push(found);
		}
		if (candidates.length == 0)
			return Future.rejected(new Exception("no GPU backend is compiled in: add a driver haxelib, such as -lib hxn-gpu-webgpu"));
		var warn = options != null && options.warn != null ? options.warn : warning;
		var reasons:Array<String> = [];
		// Backends that failed to open, which a later one replaces.
		var failed:Array<String> = [];
		function attempt(i:Int):Future<GpuDevice> {
			if (i == candidates.length)
				return Future.rejected(new Exception('no GPU backend opened: ${reasons.join("; ")}'));
			var o = candidates[i];
			var missing = o.features.missing(required);
			if (missing.length > 0) {
				reasons.push('${o.backend} lacks ${[for (f in missing) f.toString()].join(", ")}');
				return attempt(i + 1);
			}
			var opened = try o.open() catch (e:Exception) Future.rejected(e);
			return opened.map(driver -> {
				if (failed.length > 0)
					warn('hxn-gpu: using ${o.backend}, since ${failed.join("; ")}');
				new GpuDevice(driver);
			}).recover(e -> {
				reasons.push('${o.backend}: ${e.message}');
				failed.push('${o.backend} failed to open: ${e.message}');
				return attempt(i + 1);
			});
		}
		return attempt(0);
	}

	@:allow(hxn.gpu) function new(driver:Driver) {
		this.driver = driver;
		backend = driver.backend;
		adapter = driver.adapter;
		features = driver.features;
		limits = driver.limits;
	}

	public function createBuffer(descriptor:BufferDescriptor):Buffer {
		live();
		var size = descriptor.size;
		if (size <= 0 || size % 4 != 0)
			throw 'a buffer size is a positive multiple of 4, not $size';
		var contents = descriptor.contents;
		if (contents != null && contents.length > size)
			throw 'the contents are ${contents.length} bytes, more than the buffer\'s $size';
		if (descriptor.usage.has(Storage))
			need(Compute, "a storage buffer");
		var buffer = new Buffer(this, size, descriptor.usage);
		driver.createBuffer(buffer, contents);
		return buffer;
	}

	public function createTexture(descriptor:TextureDescriptor):Texture {
		live();
		var d = descriptor;
		var max = limits.maxTextureDimension2D;
		if (d.width <= 0 || d.height <= 0 || d.width > max || d.height > max)
			throw 'a texture is 1 to $max pixels each way, not ${d.width}x${d.height}';
		if (d.usage.has(Storage))
			need(StorageTextures, "a storage texture");
		var texture = new Texture(this, d.width, d.height, d.format, d.usage);
		driver.createTexture(texture);
		return texture;
	}

	public function createSampler(?descriptor:SamplerDescriptor):Sampler {
		live();
		var filter = descriptor != null && descriptor.filter != null ? descriptor.filter : Filter.Nearest;
		var address = descriptor != null && descriptor.address != null ? descriptor.address : AddressMode.ClampToEdge;
		var sampler = new Sampler(this, filter, address);
		driver.createSampler(sampler);
		return sampler;
	}

	/** A shader from an hxnsl shader class that implements `hxn.gpu.Shader`: `device.createShader(Tinted)`. **/
	public function createShader(source:ShaderSource):ShaderModule {
		live();
		var shader = new ShaderModule(this, source);
		driver.createShader(shader);
		return shader;
	}

	public function createComputePipeline(descriptor:ComputePipelineDescriptor):ComputePipeline {
		live();
		need(Compute, "a compute pipeline");
		var constants = constantsOf(descriptor.constants);
		var entry = descriptor.shader.entryPoint(descriptor.entryPoint, "compute");
		var pipeline = new ComputePipeline(this, descriptor.shader, entry, constants);
		driver.createComputePipeline(pipeline);
		return pipeline;
	}

	public function createRenderPipeline(descriptor:RenderPipelineDescriptor):RenderPipeline {
		live();
		var d = descriptor;
		var buffers = d.vertexBuffers != null ? d.vertexBuffers : [];
		if (buffers.length > 1)
			need(MultipleVertexBuffers, "a pipeline with more than one vertex buffer");
		if (Lambda.exists(buffers, b -> b.perInstance == true))
			need(InstanceVertexBuffers, "a vertex buffer read per instance");
		if (buffers.length > limits.maxVertexBuffers)
			throw 'a pipeline has at most ${limits.maxVertexBuffers} vertex buffers';
		var shader = d.shader;
		var pipeline = new RenderPipeline(this, shader, shader.entryPoint(d.vertexEntryPoint, "vertex"), shader.entryPoint(d.fragmentEntryPoint, "fragment"),
			d.format, d.topology != null ? d.topology : TriangleList, buffers, constantsOf(d.constants));
		driver.createRenderPipeline(pipeline);
		return pipeline;
	}

	/**
		Creates bind group `group` for `pipeline`'s shader. It needs an entry for every
		binding the shader's `LAYOUT` lists in that group.
	**/
	public function createBindGroup(descriptor:BindGroupDescriptor):BindGroup {
		live();
		var pipeline = descriptor.pipeline;
		var group = descriptor.group;
		var layout:Array<LayoutEntry> = [];
		for (entry in descriptor.entries) {
			var expected = pipeline.layoutEntry(group, entry.binding);
			check(entry, expected);
			layout.push(expected);
		}
		var shaderLayout = pipeline.shader.code.layout;
		if (group < shaderLayout.length)
			for (expected in shaderLayout[group])
				if (!Lambda.exists(descriptor.entries, e -> e.binding == expected.binding))
					throw 'bind group $group has no entry for binding ${expected.binding}';
		var bindGroup = new BindGroup(this, pipeline.shader, group, descriptor.entries, layout);
		driver.createBindGroup(bindGroup);
		return bindGroup;
	}

	public function createCommandEncoder():CommandEncoder {
		live();
		return new CommandEncoder(this);
	}

	/** Runs the commands `encoder` recorded, after previously submitted work. **/
	public function submit(encoder:CommandEncoder):Void {
		live();
		driver.submit(encoder.finish());
	}

	/** Writes `bytes` into `buffer` at `offset`. Work submitted after this call sees the write. **/
	public function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void {
		live();
		if (offset % 4 != 0 || bytes.length % 4 != 0)
			throw "writeBuffer's offset and length are multiples of 4";
		if (offset < 0 || offset + bytes.length > buffer.size)
			throw 'writing ${bytes.length} bytes at $offset goes past the end of a ${buffer.size}-byte buffer';
		driver.writeBuffer(buffer, offset, bytes);
	}

	/**
		Writes all of `texture` from `bytes`, rows top first, each `width *
		format.bytesPerPixel()` bytes long. Needs `TextureWrites`.
	**/
	public function writeTexture(texture:Texture, bytes:Bytes):Void {
		live();
		need(TextureWrites, "writeTexture");
		var length = texture.width * texture.height * texture.format.bytesPerPixel();
		if (bytes.length != length)
			throw 'a ${texture.width}x${texture.height} ${texture.format} texture takes $length bytes, not ${bytes.length}';
		driver.writeTexture(texture, bytes);
	}

	/**
		Reads `size` bytes of `buffer` from `offset`, by default the rest of the buffer,
		after previously submitted work has run.
	**/
	public function readBuffer(buffer:Buffer, ?offset:Int = 0, ?size:Int):Future<Bytes> {
		live();
		var length = size != null ? size : buffer.size - offset;
		if (offset % 4 != 0 || length % 4 != 0)
			throw "readBuffer's offset and size are multiples of 4";
		if (offset < 0 || length < 0 || offset + length > buffer.size)
			throw 'reading $length bytes at $offset goes past the end of a ${buffer.size}-byte buffer';
		return driver.readBuffer(buffer, offset, length);
	}

	/**
		Reads every pixel of `texture` after previously submitted work has run. Rows come
		top first, each `width * format.bytesPerPixel()` bytes long.
	**/
	public function readTexture(texture:Texture):Future<Bytes> {
		live();
		return driver.readTexture(texture);
	}

	/** Settles when all work submitted before this call has finished. **/
	public function completed():Future<hxn.Unit> {
		live();
		return driver.completed();
	}

	/** Releases the device. Close what was made from it first. **/
	public function close():Void {
		if (closed)
			return;
		closed = true;
		driver.close();
	}

	/** Throws unless the device has `feature`. `what` names the call that needs it. **/
	@:allow(hxn.gpu) function need(feature:Feature, what:String):Void {
		if (!features.has(feature))
			throw '$what needs the $feature feature, which $backend does not have';
	}

	function live():Void
		if (closed)
			throw "the device is closed";

	function constantsOf(constants:Null<Array<{key:String, value:Float}>>):Array<{key:String, value:Float}> {
		if (constants == null || constants.length == 0)
			return [];
		need(PipelineConstants, "pipeline constants");
		return constants;
	}

	function check(entry:BindGroupEntry, expected:LayoutEntry):Void {
		var at = 'binding ${entry.binding}';
		switch (expected.type) {
			case "uniform" | "storage" | "read-only-storage":
				var buffer = entry.buffer;
				if (buffer == null)
					throw '$at is a ${expected.type} buffer';
				var usage:BufferUsage = expected.type == "uniform" ? Uniform : Storage;
				if (!buffer.usage.has(usage))
					throw '$at needs a buffer with BufferUsage.${expected.type == "uniform" ? "Uniform" : "Storage"}';
				var offset = entry.offset != null ? entry.offset : 0;
				if (offset != 0 || (entry.size != null && entry.size != buffer.size - offset))
					need(BindingOffsets, 'part of a buffer at $at');
				if (offset < 0 || offset >= buffer.size || (entry.size != null && offset + entry.size > buffer.size))
					throw '$at goes past the end of its buffer';
			case "texture" | "storage-texture":
				var texture = entry.texture;
				if (texture == null)
					throw '$at is a ${expected.type}';
				var usage:TextureUsage = expected.type == "texture" ? Sampled : Storage;
				if (!texture.usage.has(usage))
					throw '$at needs a texture with TextureUsage.${expected.type == "texture" ? "Sampled" : "Storage"}';
			case "sampler" | "comparison-sampler":
				if (entry.sampler == null)
					throw '$at is a sampler';
			case other:
				throw '$at has binding type $other, which hxn-gpu does not bind';
		}
	}
}
