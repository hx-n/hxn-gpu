package hxn.gpu;

/**
	`CompareFunction` sets when a depth test passes: it compares a fragment's
	depth with the depth already in the target, as WebGPU's
	`GPUCompareFunction` does. Every driver takes these values.
**/
enum abstract CompareFunction(Int) to Int {
	var Never = 0;
	var Less = 1;
	var Equal = 2;
	var LessEqual = 3;
	var Greater = 4;
	var NotEqual = 5;
	var GreaterEqual = 6;
	var Always = 7;
}
