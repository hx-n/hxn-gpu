package hxn.gpu;

#if hxnsl
/**
	An hxnsl shader for hxn-gpu. It carries the shader language of each
	compiled-in backend: WGSL for WebGPU, MSL for Metal, SPIR-V for Vulkan,
	HLSL for Direct3D 12 and GLSL ES for GLES and WebGL2, each with its
	slots, plus the `LAYOUT` every backend binds by.
**/
interface Shader extends hxnsl.Shader
	#if hxn_gpu_webgpu extends hxn.gpu.webgpu.Shader #end
	#if hxn_gpu_metal extends hxn.gpu.metal.Shader #end
	#if hxn_gpu_vulkan extends hxn.gpu.vulkan.Shader #end
	#if hxn_gpu_d3d12 extends hxn.gpu.d3d12.Shader #end
	#if hxn_gpu_gles extends hxn.gpu.gles.Shader #end
	#if hxn_gpu_webgl2 extends hxn.gpu.webgl2.Shader #end
{}
#end
