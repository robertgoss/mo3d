from algorithm import parallelize, vectorize
from complex import ComplexSIMD, ComplexFloat64
from math import iota

# from memory.unsafe import LegacyPointer, DTypePointer
from memory import UnsafePointer
from sys import simdwidthof
from tensor import Tensor
from testing import assert_equal
from time import now, sleep

from mo3d.window.SDL import (
    SDL_INIT_VIDEO,
    SDL_PIXELFORMAT_RGBA8888,
    SDL_QUIT,
    SDL_TEXTUREACCESS_TARGET,
    SDL_WINDOWPOS_CENTERED,
    SDL_WINDOW_SHOWN,
    SDL,
    Event,
)
from mo3d.math.vec4 import Vec4

alias fps = 120
alias width = 256
alias height = 192
alias channels = Vec4[DType.float32].size

alias float_type = DType.float32
alias simd_width = 2 * simdwidthof[float_type]()


fn kernel_SIMD[
    simd_width: Int
](c: ComplexSIMD[float_type, simd_width]) -> SIMD[
    float_type, channels * simd_width
]:
    var cx = c.re
    var cy = c.im
    var r = cx / width
    var g = cy / height
    var b = cx / width
    var a = cy / height

    # Should be r1, g1, b1, a1, r2, g2, b2, a2, ...
    # Rebind is required to help the type checker understand the interleaving shape (4 * simd_width == 2 * 2 * simd_width)
    return rebind[SIMD[float_type, channels * simd_width]](
        (r.interleave(b)).interleave(g.interleave(a))
    )


fn main() raises:
    print("Hello, mo3d!")
    print("SIMD width:", simd_width)

    var t = Tensor[float_type](height, width, channels)
    print("Tensor shape:", t.shape())


    @parameter
    fn worker(row: Int):
        @parameter
        fn compute[simd_width: Int](col: Int):
            var cx = (col + iota[float_type, simd_width]())
            var cy = row
            var c = ComplexSIMD[float_type, simd_width](cx, cy)

            t.store[channels * simd_width](
                row * (width * channels) + col * channels,
                kernel_SIMD[simd_width](c),
            )

        vectorize[compute, simd_width](width)

    var sdl = SDL()
    var res_code = sdl.Init(SDL_INIT_VIDEO)
    if res_code != 0:
        print("Failed to initialize SDL")
        return

    var window = sdl.CreateWindow(
        UnsafePointer(StringRef("mo3d").data),
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        width,
        height,
        SDL_WINDOW_SHOWN,
    )

    var renderer = sdl.CreateRenderer(window, -1, 0)

    var display_texture = sdl.CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET,
        width,
        height,
    )

    fn redraw(sdl: SDL, t: Tensor[float_type]) raises:
        var target_code = sdl.SetRenderTarget(renderer, display_texture)
        if target_code != 0:
            print("Failed to set render target")
            return

        # Clear the renderer first
        _ = sdl.RenderClear(renderer)

        for y in range(height):
            for x in range(width):
                var r = (t[y, x, 0] * 255).cast[DType.uint8]()
                var g = (t[y, x, 1] * 255).cast[DType.uint8]()
                var b = (t[y, x, 2] * 255).cast[DType.uint8]()
                var a = (t[y, x, 3] * 255).cast[DType.uint8]()

                _ = sdl.SetRenderDrawColor(renderer, r, g, b, a)
                var draw_code = sdl.RenderDrawPoint(renderer, x, y)
                if draw_code != 0:
                    print("Failed to draw point at (", x, ", ", y, ")")
                    return

        _ = sdl.SetRenderTarget(renderer, 0)
        _ = sdl.RenderCopy(renderer, display_texture, 0, 0)
        _ = sdl.RenderPresent(renderer)

    var event = Event()
    var running: Bool = True

    var last_time = now()
    var alpha = 0.1
    var average_compute_time = 0.0
    var average_redraw_time = 0.0

    while True:
        if not running:
            break

        last_time = now()
        while sdl.PollEvent(UnsafePointer[Event].address_of(event)) != 0:
            if event.type == SDL_QUIT:
                running = False
            # recompute tensor on event (number of work items, number of workers)
            parallelize[worker](height, height)
        average_compute_time = (1.0 - alpha) * average_compute_time + alpha * (
            now() - last_time
        )

        last_time = now()
        redraw(sdl, t)
        average_redraw_time = (1.0 - alpha) * average_redraw_time + alpha * (
            now() - last_time
        )

        _ = sdl.Delay((Float32(1000) / Float32(fps)).cast[DType.int32]())

    sdl.DestroyWindow(window)
    sdl.Quit()

    print(
        "Average compute time: "
        + str(average_compute_time / (1024 * 1024))
        + " ms"
    )
    print(
        "Average redraw time: "
        + str(average_redraw_time / (1024 * 1024))
        + " ms"
    )
    print("Goodbye, mo3d!")
