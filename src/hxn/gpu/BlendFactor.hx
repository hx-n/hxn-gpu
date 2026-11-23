package hxn.gpu;

/**
	What a blend multiplies the source or the destination by, as WebGPU's
	`GPUBlendFactor`. "Src" is the color the fragment shader writes, and "Dst"
	the color already in the target. The values are the ones every driver
	takes.
**/
enum abstract BlendFactor(Int) to Int {
	var Zero = 0;
	var One = 1;
	var Src = 2;
	var OneMinusSrc = 3;
	var SrcAlpha = 4;
	var OneMinusSrcAlpha = 5;
	var Dst = 6;
	var OneMinusDst = 7;
	var DstAlpha = 8;
	var OneMinusDstAlpha = 9;
	/** The smaller of the source alpha and one minus the destination alpha, for color; one for alpha. **/
	var SrcAlphaSaturated = 10;
}
