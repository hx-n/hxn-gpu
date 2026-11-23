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

/** Each color target of a render pipeline has a format and a blend state. **/
typedef ColorTargetState = {
	final format:TextureFormat;
	/** The blend state. Without it, the pipeline writes this target's color as it is. **/
	final ?blend:BlendState;
}

/**
	`DepthState` sets how a render pipeline tests and writes depth. The test
	passes when `compare` holds between the fragment's depth and the depth in
	the target, `Less` by default, and with `write`, true by default, a
	fragment that passes writes its depth.
**/
typedef DepthState = {
	final format:TextureFormat;
	final ?compare:CompareFunction;
	final ?write:Bool;
}

typedef RenderPipelineDescriptor = {
	final shader:ShaderModule;
	final ?vertexEntryPoint:String;
	final ?fragmentEntryPoint:String;
	/** The format of the one texture it renders into. Give `format` or `targets`. **/
	final ?format:TextureFormat;
	/**
		The color targets, one for each output of the fragment shader, in
		order. Give `format` or `targets`.
	**/
	final ?targets:Array<ColorTargetState>;
	/** The depth test and the depth target's format. Without it, the pipeline tests no depth. **/
	final ?depth:DepthState;
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

/**
	Each color attachment of a render pass has the texture it renders into.
	The pass first clears the texture to `clear`, transparent black by
	default, or with `keep` draws over what it holds.
**/
typedef ColorAttachment = {
	final target:Texture;
	final ?clear:Color;
	final ?keep:Bool;
}

/**
	The depth attachment of a render pass is a texture of a depth format. The
	pass first clears it to `clear`, 1 by default, or with `keep` tests
	against what it holds.
**/
typedef DepthAttachment = {
	final target:Texture;
	final ?clear:Float;
	final ?keep:Bool;
}

/** `RenderPassDescriptor` lists the attachments of a render pass. Every attachment has the same size. **/
typedef RenderPassDescriptor = {
	final colors:Array<ColorAttachment>;
	final ?depth:DepthAttachment;
}
