package hxn.gpu.backend;

import hxn.Future;

class Settled {
	/** Runs `work` now and returns its result, or its exception as a failure. **/
	public static function attempt<T>(work:() -> T):Future<T> {
		return try Future.resolved(work()) catch (e:haxe.Exception) Future.rejected(e);
	}
}
