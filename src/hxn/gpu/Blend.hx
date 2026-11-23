package hxn.gpu;

import hxn.gpu.Descriptors.BlendState;

/**
	Blend states for the common cases, for `RenderPipelineDescriptor.blend`.
	Pipelines without a blend state write their color as it is.
**/
class Blend {
	/**
		Straight alpha, for colors that are not multiplied by their alpha:
		color = source * source alpha + destination * (1 - source alpha).
	**/
	public static final alpha:BlendState = {
		color: {srcFactor: SrcAlpha, dstFactor: OneMinusSrcAlpha, operation: Add},
		alpha: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add}
	};

	/**
		Premultiplied alpha, for colors already multiplied by their alpha:
		color = source + destination * (1 - source alpha).
	**/
	public static final premultiplied:BlendState = {
		color: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add},
		alpha: {srcFactor: One, dstFactor: OneMinusSrcAlpha, operation: Add}
	};

	/** Additive, for light and glow: color = source * source alpha + destination. **/
	public static final additive:BlendState = {
		color: {srcFactor: SrcAlpha, dstFactor: One, operation: Add},
		alpha: {srcFactor: One, dstFactor: One, operation: Add}
	};
}
