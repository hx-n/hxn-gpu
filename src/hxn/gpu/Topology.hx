package hxn.gpu;

/** How a render pipeline assembles vertices into primitives. **/
enum abstract Topology(Int) {
	var PointList;
	var LineList;
	var LineStrip;
	var TriangleList;
	var TriangleStrip;
}
