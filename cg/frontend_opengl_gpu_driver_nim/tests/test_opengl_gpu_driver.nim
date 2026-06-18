import std/unittest
import ../src/opengl_gpu_driver_lib

suite "opengl gpu driver":

  test "default texture options are configurable data":
    let linear = defaultTextureOptions()
    check linear.minFilter == tfLinear
    check linear.magFilter == tfLinear
    check linear.wrapS == twClampToEdge
    check linear.wrapT == twClampToEdge

    let nearest = defaultTextureOptions(tfNearest)
    check nearest.minFilter == tfNearest
    check nearest.magFilter == tfNearest

  test "triangle driver starts without an allocated buffer":
    let driver = newOpenGlTriangleDriver()
    check driver.gpuBufferId == 0
