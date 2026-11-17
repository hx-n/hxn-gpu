# hxn-gpu

[![Native](https://github.com/hx-n/hxn-gpu/actions/workflows/native.yml/badge.svg)](https://github.com/hx-n/hxn-gpu/actions/workflows/native.yml)
[![Browser](https://github.com/hx-n/hxn-gpu/actions/workflows/browser.yml/badge.svg)](https://github.com/hx-n/hxn-gpu/actions/workflows/browser.yml)

One GPU API for Haxe on Metal, Vulkan, Direct3D 12, OpenGL ES, WebGPU and
WebGL2. It follows WebGPU: `GpuDevice`, buffers, textures, samplers, bind
groups, compute and render pipelines, and command encoders. Shaders are
[hxnsl](https://github.com/hx-n/hxnsl) shaders, translated for every backend
at compile time.

hxn-gpu is written in Haxe. It runs on the hxn GPU drivers, one per
backend, and works on HashLink, Ash and hxcpp, natively and in the browser.

## Drivers

Add a driver haxelib for each backend to support. Only those backends are
compiled in.

| Backend | Driver | Platforms |
|---|---|---|
| Metal | [hxn-gpu-metal](https://github.com/hx-n/hxn-gpu-metal) | macOS, iOS |
| Direct3D 12 | [hxn-gpu-d3d12](https://github.com/hx-n/hxn-gpu-d3d12) | Windows |
| Vulkan | [hxn-gpu-vulkan](https://github.com/hx-n/hxn-gpu-vulkan) | Linux, Android, Windows, macOS through MoltenVK |
| OpenGL ES 3.0 | [hxn-gpu-gles](https://github.com/hx-n/hxn-gpu-gles) | Linux, Android, and macOS and Windows through ANGLE |
| WebGPU | [hxn-gpu-webgpu](https://github.com/hx-n/hxn-gpu-webgpu) | Browsers, on hxcpp and Ash compiled to wasm |
| WebGL2 | [hxn-gpu-webgl2](https://github.com/hx-n/hxn-gpu-webgl2) | Browsers, on hxcpp and Ash compiled to wasm |

```
haxelib install hxn-gpu
haxelib install hxn-gpu-metal
haxelib install hxn-gpu-gles
haxe -lib hxn-gpu -lib hxn-gpu-metal -lib hxn-gpu-gles -main Main -hl main.hl
```

GLES and WebGL2 share one implementation, so a program can't be compiled with both.

## Opening a device

`GpuDevice.open()` tries the compiled-in backends in the platform's order and
returns the first that initializes:

| Platform | Order |
|---|---|
| macOS, iOS | Metal, Vulkan, GLES |
| Windows | Direct3D 12, Vulkan, GLES |
| Other native platforms | Vulkan, GLES |
| Browser | WebGPU, WebGL2 |

To change the order, pass `backends` to `open`, set `HXN_GPU_BACKEND` when
the program runs, or compile with `-D hxn_gpu_backend`. Each takes a list, such
as `vulkan,gles`. When a backend fails to open and a later one is used, `open`
prints a warning to standard error, which a web page shows in its console. A
browser without WebGPU therefore falls back to WebGL2 and says why.

```haxe
import hxn.gpu.*;

class Main {
	static function main() {
		GpuDevice.open({required: [Compute]}).then(device -> {
			trace('${device.backend} on ${device.adapter}: ${device.features}');
		}, e -> trace('no GPU: ${e.message}'));
	}
}
```

## Features and limits

A device reports `features` and `limits`, and `open` skips backends without
the features in `required`. A call that lacks a feature throws and names the
feature and the backend.

| Feature | Metal | Direct3D 12 | Vulkan | GLES | WebGPU | WebGL2 |
|---|---|---|---|---|---|---|
| `Compute` | yes | yes | yes | | yes | |
| `StorageTextures` | yes | | yes | | yes | |
| `TextureWrites` | yes | yes | | yes | yes | yes |
| `IndexedDraws` | | | | yes | | yes |
| `BindingOffsets` | yes | | yes | | yes | |
| `MultipleVertexBuffers` | yes | yes | yes | yes | | yes |
| `InstanceVertexBuffers` | yes | | yes | yes | | yes |
| `BufferCopies` | | | | | yes | |
| `PipelineConstants` | | | | | yes | |
| `Presentation` | yes | yes | yes | yes | yes | yes |

A blank cell is a feature the driver doesn't expose yet, not one the platform
lacks. `limits` are the minimums every device of the backend guarantees:
WebGPU's default limits, or OpenGL ES 3.0's on GLES and WebGL2.

## Presenting

A `GpuSurface` presents frames to a window, from
[hxn-window](https://github.com/hx-n/hxn-window), or to the web page's canvas.
Pass the window or `Canvas` to `GpuDevice.open` as `surface`: GLES and WebGL2
make their context for it, and in a browser the backend that opens claims the
page's canvas. Then configure the surface, and each frame render into its
current texture and present it:

```haxe
import hxn.gpu.*;

var target = SurfaceTargets.ofWindow(window);        // or Canvas in a browser
GpuDevice.open({surface: target}).then(device -> {
	var surface = device.createSurface(target);
	surface.configure(width, height);                // again when the window is resized
	function frame() {
		var texture = surface.currentTexture();
		var encoder = device.createCommandEncoder();
		var pass = encoder.beginRenderPass(texture, {r: 0, g: 0, b: 0, a: 1});
		// ... draws ...
		pass.end();
		device.submit(encoder);
		surface.present();
	}
	frame();
});
```

| Backend | Presents to |
|---|---|
| Metal | AppKit and UIKit windows |
| Direct3D 12 | Win32 windows |
| Vulkan | AppKit and UIKit windows through MoltenVK, Win32, Xlib, Wayland and Android windows |
| GLES | Xlib, Wayland, Win32 and AppKit windows through ANGLE, and Android windows |
| WebGPU, WebGL2 | The web page's canvas |

`surface.preferredFormat()` is the format a render pipeline for the surface
uses, and `configure` takes it by default. A window on a high-density display
can have frames larger in pixels than the size configured: read the size from
the texture. Frames on Metal can't be read back; the other backends'
`readTexture` reads a frame before it is presented.

## Shaders

A shader class implements `hxn.gpu.Shader`. It then carries the language of
each compiled-in backend, and `device.createShader` takes the class itself:

```haxe
class Tinted implements hxn.gpu.Shader {
	static var SRC = {
		@input var input : { position : Vec2 };
		var output : { position : Vec4, color : Vec4 };
		@param var tint : Vec4;

		function vertex() {
			output.position = vec4(input.position, 0, 1);
		}

		function fragment() {
			output.color = tint;
		}
	};
}
```

```haxe
var shader = device.createShader(Tinted);
var pipeline = device.createRenderPipeline({
	shader: shader,
	format: Rgba8Unorm,
	topology: TriangleStrip,
	vertexBuffers: [{stride: 8, attributes: [{location: Tinted.INPUT_position, format: Float32x2, offset: 0}]}]
});
var uniforms = device.createBuffer({size: Tinted.PARAMS_SIZE, usage: Uniform, contents: params});
var group = device.createBindGroup({pipeline: pipeline, group: Tinted.PARAMS_GROUP, entries: [{binding: Tinted.PARAMS_BINDING, buffer: uniforms}]});
```

A bind group is created for a pipeline's shader, and its entries follow the
shader's `LAYOUT`.

## Commands and results

A `CommandEncoder` records compute passes, render passes and buffer copies;
`device.submit` runs them in order. Synchronization is implicit, as in WebGPU.
On Vulkan and Direct3D 12, one tracker turns each change in how a resource is
used into the barrier or state transition it needs.

`writeBuffer` and `writeTexture` take effect before the work submitted after
them. `readBuffer` and `readTexture` return an `hxn.Future` of the contents
once the work submitted before has run, and `completed()` settles when that
work is done:

```haxe
var encoder = device.createCommandEncoder();
var pass = encoder.beginRenderPass(target, {r: 0, g: 0, b: 0, a: 1});
pass.setPipeline(pipeline);
pass.setBindGroup(Tinted.PARAMS_GROUP, group);
pass.setVertexBuffer(0, positions);
pass.draw(4);
pass.end();
device.submit(encoder);
device.readTexture(target).then(pixels -> trace(pixels.get(0)));
```

In a threaded browser build, `await` works (under Ash, from 0.1.21): the
browser drivers run in a Worker of their own. Without threads, deliver results
with `then`: `await` blocks the thread the browser settles them on.

## Limitations

- One queue, and resources tracked whole: a buffer or a texture's only mip level.
- On GLES and WebGL2, `readTexture` reads back only RGBA8, and rows rendered
  into a texture come back bottom first.
- Direct3D 12 copies whole buffers, so `writeBuffer` on part of a storage buffer
  reads the rest back first.

## Building from source

The check renders, computes, samples a texture and reads a buffer back on each
backend the machine has, and prints the same lines everywhere. A step whose
feature a device lacks prints that it was skipped. The present example draws
three frames to an hxn-window window on every platform, using its physical
pixel size and resize events, and reads the last back where the backend can.
`SurfaceTargets.ofWindow` maps browser windows to the canvas target; the window
keeps DOM input and sizing while the GPU driver owns rendering.

```
haxe -lib hxn-gpu -lib hxn-gpu-metal -lib hxnsl -cp examples/check -main Main -hl out/main.hl
ash out/main.hl
haxe -lib hxn-gpu -lib hxn-gpu-metal -lib hxn-window -lib hxnsl -cp examples/present -main Main -hl out/present.hl
ash out/present.hl
```

`HXN_GPU_BACKEND` selects the backend. CI runs both on each backend under
Ash and hxcpp, natively on real windows and in headless Chrome on the canvas.

## Agent skill

[`skills/hxn-gpu/SKILL.md`](skills/hxn-gpu/SKILL.md) describes hxn-gpu for
coding agents. The haxelib includes it.

## License

Licensed under Apache-2.0. See [LICENSE](LICENSE).
