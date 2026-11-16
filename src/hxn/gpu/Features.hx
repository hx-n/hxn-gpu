package hxn.gpu;

/** A set of features. **/
abstract Features(Int) from Feature {
	public static final none:Features = cast 0;

	public inline function has(feature:Feature):Bool
		return this & (feature : Int) != 0;

	/** The features of `required` this set lacks. **/
	public function missing(required:Features):Array<Feature> {
		return [for (f in Feature.all) if (required.has(f) && !has(f)) f];
	}

	public function toArray():Array<Feature> {
		return [for (f in Feature.all) if (has(f)) f];
	}

	@:op(A | B) static inline function or(a:Features, b:Features):Features
		return cast((cast a : Int) | (cast b : Int));

	@:from static function ofArray(features:Array<Feature>):Features {
		var bits = 0;
		for (f in features)
			bits |= (f : Int);
		return cast bits;
	}

	public function toString():String {
		var names = [for (f in toArray()) f.toString()];
		return names.length == 0 ? "none" : names.join(", ");
	}
}
