package hxn.gpu;

/**
	`BlendFactor` sets what a blend multiplies the source or the destination
	by, as WebGPU's `GPUBlendFactor` does. "Src" is the color that the
	fragment shader writes, and "Dst" is the color already in the target.
	Every driver takes these values.
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
	/**
		For the color, the smaller of the source alpha and one minus the
		destination alpha. For the alpha, one.
	**/
	var SrcAlphaSaturated = 10;
}
