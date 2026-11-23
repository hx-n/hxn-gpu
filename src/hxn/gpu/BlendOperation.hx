package hxn.gpu;

/**
	How a blend combines the weighted source and destination, as WebGPU's
	`GPUBlendOperation`. `Min` and `Max` ignore the factors, so their factors
	must be `One`. The values are the ones every driver takes.
**/
enum abstract BlendOperation(Int) to Int {
	var Add = 0;
	var Subtract = 1;
	var ReverseSubtract = 2;
	var Min = 3;
	var Max = 4;
}
