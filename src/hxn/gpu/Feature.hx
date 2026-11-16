package hxn.gpu;

/**
	A capability that only some backends support. `GpuDevice.features` lists the features
	a device has, and `GpuDevice.open` skips backends that lack the ones in `required`. A
	call that lacks a feature throws and names the feature and the backend.
**/
enum abstract Feature(Int) to Int {
	/** Compute pipelines and passes. Not on GLES or WebGL2. **/
	var Compute = 1;

	/** Textures that shaders write, created with `TextureUsage.Storage`. **/
	var StorageTextures = 2;

	/** Writing texture contents from the CPU with `GpuDevice.writeTexture`. **/
	var TextureWrites = 4;

	/** `RenderPass.setIndexBuffer` and `drawIndexed`. **/
	var IndexedDraws = 8;

	/**
		Binding part of a buffer in a bind group: a non-zero offset, or a size smaller
		than the rest of the buffer.
	**/
	var BindingOffsets = 16;

	/** A render pipeline reading vertices from more than one buffer. **/
	var MultipleVertexBuffers = 32;

	/** `CommandEncoder.copyBufferToBuffer`. **/
	var BufferCopies = 64;

	/** Vertex buffers that step once per instance, set with `VertexBufferLayout.perInstance`. **/
	var InstanceVertexBuffers = 256;

	/**
		Setting a shader's `@const` values when a pipeline is created. Without it, they
		are fixed at compile time.
	**/
	var PipelineConstants = 128;

	/** Presenting to a window or the web page's canvas through a `GpuSurface`. **/
	var Presentation = 512;

	/** Every feature, in the order `Features.toString` lists them. **/
	public static final all:Array<Feature> = [
		Compute,
		StorageTextures,
		TextureWrites,
		IndexedDraws,
		BindingOffsets,
		MultipleVertexBuffers,
		BufferCopies,
		InstanceVertexBuffers,
		PipelineConstants,
		Presentation
	];

	public function toString():String {
		return switch (cast this : Feature) {
			case Compute: "compute";
			case StorageTextures: "storage textures";
			case TextureWrites: "texture writes";
			case IndexedDraws: "indexed draws";
			case BindingOffsets: "binding offsets";
			case MultipleVertexBuffers: "multiple vertex buffers";
			case BufferCopies: "buffer copies";
			case InstanceVertexBuffers: "instance vertex buffers";
			case Presentation: "presentation";
			case PipelineConstants: "pipeline constants";
		}
	}

	@:op(A | B) static inline function or(a:Feature, b:Feature):Features
		return cast((a : Int) | (b : Int));
}
