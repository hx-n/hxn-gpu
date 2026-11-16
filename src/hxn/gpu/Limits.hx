package hxn.gpu;

/**
	Size and count limits for a device. Each backend reports the minimum its devices
	guarantee: WebGPU's default limits on WebGPU, Metal, Vulkan and Direct3D 12, and the
	OpenGL ES 3.0 minimums on GLES and WebGL2.
**/
typedef Limits = {
	final maxTextureDimension2D:Int;
	final maxBindGroups:Int;
	final maxUniformBufferBindingSize:Int;
	final maxStorageBufferBindingSize:Int;
	final maxVertexBuffers:Int;
	final maxVertexAttributes:Int;
	final maxComputeWorkgroupSizeX:Int;
	final maxComputeWorkgroupSizeY:Int;
	final maxComputeWorkgroupSizeZ:Int;
	final maxComputeInvocationsPerWorkgroup:Int;
}

class DefaultLimits {
	/** WebGPU's default limits. **/
	public static final webgpu:Limits = {
		maxTextureDimension2D: 8192,
		maxBindGroups: 4,
		maxUniformBufferBindingSize: 65536,
		maxStorageBufferBindingSize: 134217728,
		maxVertexBuffers: 8,
		maxVertexAttributes: 16,
		maxComputeWorkgroupSizeX: 256,
		maxComputeWorkgroupSizeY: 256,
		maxComputeWorkgroupSizeZ: 64,
		maxComputeInvocationsPerWorkgroup: 256
	};

	/** The minimums OpenGL ES 3.0 guarantees. It has no compute, so the compute limits are 0. **/
	public static final gles:Limits = {
		maxTextureDimension2D: 2048,
		maxBindGroups: 4,
		maxUniformBufferBindingSize: 16384,
		maxStorageBufferBindingSize: 0,
		maxVertexBuffers: 8,
		maxVertexAttributes: 16,
		maxComputeWorkgroupSizeX: 0,
		maxComputeWorkgroupSizeY: 0,
		maxComputeWorkgroupSizeZ: 0,
		maxComputeInvocationsPerWorkgroup: 0
	};
}
