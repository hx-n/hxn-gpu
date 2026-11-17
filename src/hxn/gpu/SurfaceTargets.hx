package hxn.gpu;

import haxe.Int64;

/** A window with hxn-window's surface handles, such as `hxn.window.Window`. **/
typedef NativeWindow = {
	function platform():Int;
	function raw(which:Int):Int64;
}

class SurfaceTargets {
	/** The surface target of `window`, including a browser canvas window. **/
	public static function ofWindow(window:NativeWindow):SurfaceTarget {
		return switch window.platform() {
			case 7 | 8: Canvas;
			case platform: Window(platform, [for (i in 0...4) window.raw(i)]);
		}
	}
}
