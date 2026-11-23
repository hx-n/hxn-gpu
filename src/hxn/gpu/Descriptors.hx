package hxn.gpu;

import haxe.io.Bytes;

typedef BufferDescriptor = {
	final size:Int;
	final usage:BufferUsage;
	/** Initial contents, at most `size` bytes. **/
	final ?contents:Bytes;
}

typedef TextureDescriptor = {
	final width:Int;
	final height:Int;
	final format:TextureFormat;
	final usage:TextureUsage;
}

/** `TextureRegion` is a rectangle of a texture, in pixels from the texture's top-left corner. **/
typedef TextureRegion = {
	final x:Int;
	final y:Int;
	final width:Int;
	final height:Int;
}

typedef SamplerDescriptor = {
	/** Nearest by default. **/
	final ?filter:Filter;
	/** ClampToEdge by default. **/
	final ?address:AddressMode;
}

typedef ComputePipelineDescriptor = {
	final shader:ShaderModule;
	/** The compute entry point to use when the shader has more than one. **/
	final ?entryPoint:String;
	/** Values of the shader's `@const`s; needs `PipelineConstants`. **/
	final ?constants:Array<{key:String, value:Float}>;
}

typedef VertexAttribute = {
	/** The shader's input location: hxnsl's `INPUT_<name>`. **/
	final location:Int;
	final format:VertexFormat;
	final offset:Int;
}

typedef VertexBufferLayout = {
	final stride:Int;
	/** Step through the buffer once per instance instead of once per vertex. **/
	final ?perInstance:Bool;
	final attributes:Array<VertexAttribute>;
}

/**
	Each blend state has two components, one for the color and one for the
	alpha. Each component sets how the color or the alpha that a pipeline
	draws combines with the one already in the target. Fields that are left
	out take WebGPU's defaults: the operation `Add`, the source factor `One`
	and the destination factor `Zero`.
**/
typedef BlendComponent = {
	final ?operation:BlendOperation;
	final ?srcFactor:BlendFactor;
	final ?dstFactor:BlendFactor;
}

/**
	`BlendState` sets how a pipeline blends into its color target, as WebGPU's
	`GPUBlendState` does.
**/
typedef BlendState = {
	final color:BlendComponent;
	final alpha:BlendComponent;
}

typedef RenderPipelineDescriptor = {
	final shader:ShaderModule;
	final ?vertexEntryPoint:String;
	final ?fragmentEntryPoint:String;
	/** The format of the textures it renders into. **/
	final format:TextureFormat;
	/** TriangleList by default. **/
	final ?topology:Topology;
	/** Vertex buffer layouts by slot. More than one needs `MultipleVertexBuffers`. **/
	final ?vertexBuffers:Array<VertexBufferLayout>;
	final ?constants:Array<{key:String, value:Float}>;
	/**
		The blend state, such as `Blend.alpha`. Without it, the pipeline writes
		its color as it is.
	**/
	final ?blend:BlendState;
}

typedef BindGroupEntry = {
	/** The binding in the group, as the shader's `LAYOUT` numbers it. **/
	final binding:Int;
	final ?buffer:Buffer;
	/** Byte offset into `buffer`. A non-zero offset needs `BindingOffsets`. **/
	final ?offset:Int;
	/** Bytes to bind, by default the rest of the buffer. A smaller size needs `BindingOffsets`. **/
	final ?size:Int;
	final ?texture:Texture;
	final ?sampler:Sampler;
}

typedef BindGroupDescriptor = {
	/** A pipeline made from the shader this group is for. **/
	final pipeline:Pipeline;
	final group:Int;
	final entries:Array<BindGroupEntry>;
}

typedef Color = {
	final r:Float;
	final g:Float;
	final b:Float;
	final a:Float;
}
