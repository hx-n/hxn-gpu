package hxn.gpu;

import hxn.gpu.Descriptors.BlendState;

/**
	`Blend` holds the blend states for the common cases, for
	`RenderPipelineDescriptor.blend`. Pipelines without a blend state write
	their color as it is.
**/
class Blend {
	/**
		Blends colors that are not multiplied by their alpha, which is called
		straight alpha: color = source * source alpha + destination * (1 - source alpha).
	**/
	public static final alpha:BlendState = {
		color: {srcFactor: SrcAlpha, dstFactor: OneMinusSrcAlpha, operation: Add},
		alpha: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add}
	};

	/**
		Blends colors that are already multiplied by their alpha, which is
		called premultiplied alpha: color = source + destination * (1 - source alpha).
	**/
	public static final premultiplied:BlendState = {
		color: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add},
		alpha: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add}
	};

	/**
		Adds the color to the target, for light and glow:
		color = source * source alpha + destination.
	**/
	public static final additive:BlendState = {
		color: {srcFactor: SrcAlpha, dstFactor: One, operation: Add},
		alpha: {srcFactor: One, dstFactor: One, operation: Add}
	};
}
