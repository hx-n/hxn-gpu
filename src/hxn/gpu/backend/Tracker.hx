package hxn.gpu.backend;

/** How a command uses a buffer or texture. **/
enum abstract Access(Int) to Int {
	/** Not used since creation. **/
	var Untouched = 0;
	var CopySrc;
	var CopyDst;
	var Vertex;
	var Index;
	var Uniform;
	var StorageRead;
	/** Read and written by a shader: a storage buffer or a storage texture. **/
	var StorageWrite;
	var Sampled;
	var RenderTarget;
	/** Handed to the window system to be shown. **/
	var Present;

	public function writes():Bool {
		return switch (cast this : Access) {
			case CopyDst | StorageWrite | RenderTarget: true;
			case _: false;
		}
	}
}

/** An access, and the stages it happens in: `Tracker.COMPUTE`, `Tracker.GRAPHICS` or both. **/
typedef Use = {
	final access:Access;
	final stages:Int;
}

typedef Transition = {
	final before:Use;
	final after:Use;
}

/**
	Tracks the last use of each buffer and texture on a device, and reports the transition
	its next use needs. The Vulkan backend turns a transition into a pipeline barrier and
	the Direct3D 12 backend into a resource barrier. Each backend decides which
	transitions need one: Vulkan skips read-to-read transitions on buffers, while Direct3D
	12 changes state whenever the state differs.
**/
class Tracker {
	public static inline final COMPUTE = 1;
	public static inline final GRAPHICS = 2;

	static final untouched:Use = {access: Untouched, stages: 0};

	final uses = new Map<Int, Use>();

	public function new() {}

	public function current(id:Int):Use {
		var use = uses.get(id);
		return use != null ? use : untouched;
	}

	/**
		Records that resource `id` is used for `access` in `stages`, and
		returns the transition from its last use, or null when it is already
		being read that way.
	**/
	public function use(id:Int, access:Access, stages:Int):Null<Transition> {
		var before = current(id);
		if (before.access == access && !access.writes() && before.stages | stages == before.stages)
			return null;
		// Reads of the same kind accumulate their stages, so a later write waits for all of them.
		var widened = before.access == access && !access.writes() ? before.stages | stages : stages;
		var after:Use = {access: access, stages: widened};
		uses.set(id, after);
		return {before: before, after: after};
	}

	public function forget(id:Int):Void
		uses.remove(id);

	/** Calls `visit` with each buffer and texture `group` binds, and how the shader uses it. **/
	public static function groupUses(group:BindGroup, visit:(resource:Resource, access:Access) -> Void):Void {
		for (i in 0...group.entries.length) {
			var entry = group.entries[i];
			switch (group.layout[i].type) {
				case "uniform":
					visit(entry.buffer, Uniform);
				case "storage":
					visit(entry.buffer, StorageWrite);
				case "read-only-storage":
					visit(entry.buffer, StorageRead);
				case "texture":
					visit(entry.texture, Sampled);
				case "storage-texture":
					visit(entry.texture, StorageWrite);
				case _:
			}
		}
	}
}
