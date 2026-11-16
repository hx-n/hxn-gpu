package hxn.gpu;

/** The driver a device runs on. **/
enum abstract Backend(String) to String {
	var Metal = "metal";
	var Vulkan = "vulkan";
	var D3D12 = "d3d12";
	var Gles = "gles";
	var WebGPU = "webgpu";
	var WebGL2 = "webgl2";
}
