package hxn.gpu;

import haxe.Int64;

/** A window with hxn-window's surface handles, such as `hxn.window.Window`. **/
typedef NativeWindow = {
	function platform():Int;
	function raw(which:Int):Int64;
}

class SurfaceTargets {
	/** The surface target of `window`, an hxn-window window. **/
	public static function ofWindow(window:NativeWindow):SurfaceTarget {
		return Window(window.platform(), [for (i in 0...4) window.raw(i)]);
	}
}
