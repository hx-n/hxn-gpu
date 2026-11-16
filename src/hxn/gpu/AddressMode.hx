package hxn.gpu;

/** What a sampler reads outside a texture's edges. **/
enum abstract AddressMode(Int) {
	var ClampToEdge;
	var Repeat;
	var MirrorRepeat;
}
