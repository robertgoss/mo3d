from algorithm import parallelize, vectorize
from complex import ComplexSIMD, ComplexFloat64
from math import iota
from tensor import Tensor

from mo3d.SDL import (
    SDL,
    SDL_INIT_VIDEO,
    SDL_WINDOWPOS_CENTERED,
    SDL_WINDOW_SHOWN,
    SDL_PIXELFORMAT_RGBA8888,
    SDL_TEXTUREACCESS_TARGET,
    Event,
    SDL_QUIT,
)
from mo3d.numeric import NumericFloat32
from mo3d.math import Vec3

alias fps = 120
alias width = 256
alias height = 256
alias channels = 2

alias float_type = DType.float32
alias simd_width = 2 * simdwidthof[float_type]()


fn kernal_SIMD[
    simd_width: Int
](c: ComplexSIMD[float_type, simd_width]) -> SIMD[
    float_type, channels * simd_width
]:
    var cx = c.re
    var cy = c.im
    var res_x = cx / width
    var res_y = cy / height
    return res_x.interleave(res_y)


fn main() raises:
    print("Hello, mo3d!")
    print("SIMD width:", simd_width)

    var t = Tensor[float_type](height, width, channels)

    @parameter
    fn worker(row: Int):
        @parameter
        fn compute[simd_width: Int](col: Int):
            var cx = (col + iota[float_type, simd_width]())
            var cy = row
            var c = ComplexSIMD[float_type, simd_width](cx, cy)

            t.store[channels * simd_width](
                row * (width * channels) + col * channels,
                kernal_SIMD[simd_width](c),
            )

        vectorize[compute, simd_width](width)

    var sdl = SDL()
    var res_code = sdl.Init(SDL_INIT_VIDEO)
    if res_code != 0:
        print("Failed to initialize SDL")
        return

    var window = sdl.CreateWindow(
        DTypePointer(StringRef("mo3d").data),
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

        for y in range(height):
            for x in range(width):
                var r = (t[y, x, 0] * 255).cast[DType.uint8]()
                var g = (t[y, x, 1] * 255).cast[DType.uint8]()
                var b = 0
                _ = sdl.SetRenderDrawColor(renderer, r, g, b, 255)
                var draw_code = sdl.RenderDrawPoint(renderer, y, x)
                if draw_code != 0:
                    print("Failed to draw point")
                    return

        _ = sdl.SetRenderTarget(renderer, 0)
        _ = sdl.RenderCopy(renderer, display_texture, 0, 0)
        _ = sdl.RenderPresent(renderer)

    var event = Event()
    var running: Bool = True
    while True:
        if not running:
            break

        while sdl.PollEvent(Pointer[Event].address_of(event)) != 0:
            if event.type == SDL_QUIT:
                running = False
            # recompute tensor on event (number of work items, number of workers)
            parallelize[worker](height, height)

        redraw(sdl, t)
        _ = sdl.Delay(Int32((1000 / fps)))

    sdl.DestroyWindow(window)
    sdl.Quit()

    print("Goodbye, mo3d!")
