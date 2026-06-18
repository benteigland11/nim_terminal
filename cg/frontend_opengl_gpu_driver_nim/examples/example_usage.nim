import opengl_gpu_driver_lib

let options = defaultTextureOptions(tfNearest)
doAssert options.minFilter == tfNearest
doAssert options.magFilter == tfNearest
doAssert options.wrapS == twClampToEdge

let driver = newOpenGlTriangleDriver()
doAssert driver.gpuBufferId == 0
