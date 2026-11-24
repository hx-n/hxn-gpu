package hxn.gpu.backend;

import hxn.gpu.Command;

/**
	Records the submission that uses each buffer of a list of steps, so a
	write to a buffer waits only for the work that reads it.
**/
class Uses {
	/** Sets `use` on every buffer that `steps` bind or copy. **/
	public static function mark(steps:Array<Step>, use:Any):Void {
		for (step in steps)
			switch (step) {
				case ComputeStep(list) | RenderStep(_, list):
					for (command in list)
						switch (command) {
							case SetVertexBuffer(_, buffer, _) | SetIndexBuffer(buffer, _):
								buffer.use = use;
							case SetBindGroup(_, group):
								for (entry in group.entries)
									if (entry.buffer != null)
										entry.buffer.use = use;
							case _:
						}
				case CopyStep(source, _, destination, _, _):
					source.use = use;
					destination.use = use;
			}
	}
}
