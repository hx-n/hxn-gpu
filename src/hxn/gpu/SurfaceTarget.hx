package hxn.gpu;

import haxe.Int64;

/**
	Where a surface presents: a native window, by the platform code and raw
	handles hxn-window's `Window.platform()` and `Window.raw(0..3)` return, or
	the web page's canvas.
**/
enum SurfaceTarget {
	/**
		`platform` is 1 AppKit, 2 Win32, 3 Xlib, 4 Wayland, 5 Android or 6
		UIKit. `handles` are `raw(0)` to `raw(3)`: the window first, and on
		Xlib its visual id and then the `Display*`.
	**/
	Window(platform:Int, handles:Array<Int64>);

	/** The web page's canvas, the element with the id `canvas`. **/
	Canvas;
}
