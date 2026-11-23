package hxn.gpu.backend;

import hxn.gpu.Command.Step;
import haxe.io.Bytes;

/**
	The interface each backend implements. `GpuDevice` validates every call before passing
	it on. Each `create` method sets the resource's `native`. Calls arrive in program
	order, and the backend preserves that order on the GPU: a write or read happens after
	the work submitted before it.
**/
interface Driver {
	final backend:Backend;
	final adapter:String;
	final features:Features;
	final limits:Limits;
	function createBuffer(buffer:Buffer, contents:Null<Bytes>):Void;
	function createTexture(texture:Texture):Void;
	function createSampler(sampler:Sampler):Void;
	function createShader(shader:ShaderModule):Void;
	function createComputePipeline(pipeline:ComputePipeline):Void;
	function createRenderPipeline(pipeline:RenderPipeline):Void;
	function createBindGroup(group:BindGroup):Void;
	function writeBuffer(buffer:Buffer, offset:Int, bytes:Bytes):Void;
	/**
		Writes `region` of `texture`. `bytes` holds its rows top first, `bytesPerRow` apart,
		each `region.width * bytesPerPixel` long.
	**/
	function writeTexture(texture:Texture, region:hxn.gpu.Descriptors.TextureRegion, bytes:Bytes, bytesPerRow:Int):Void;
	function readBuffer(buffer:Buffer, offset:Int, size:Int):Future<Bytes>;
	/** The rows top first, each `width * bytesPerPixel` long. **/
	function readTexture(texture:Texture):Future<Bytes>;
	function submit(steps:Array<Step>):Void;
	function createSurface(surface:GpuSurface):Void;
	function surfaceFormat(surface:GpuSurface):TextureFormat;
	/** Sizes the surface's frames from its `width`, `height`, `format` and `vsync`. **/
	function configureSurface(surface:GpuSurface):Void;
	/** The texture of the surface's next frame, with `RenderTarget` usage. **/
	function surfaceTexture(surface:GpuSurface):Texture;
	/** Shows `frame`, after the work submitted before. **/
	function present(surface:GpuSurface, frame:Texture):Void;
	function completed():Future<hxn.Unit>;
	function close():Void;
}
