package hxn.gpu;

/**
	`BlendOperation` sets how a blend combines the weighted source and
	destination, as WebGPU's `GPUBlendOperation` does. `Min` and `Max` ignore
	the factors, so their factors must be `One`. Every driver takes these
	values.
**/
enum abstract BlendOperation(Int) to Int {
	var Add = 0;
	var Subtract = 1;
	var ReverseSubtract = 2;
	var Min = 3;
	var Max = 4;
}
