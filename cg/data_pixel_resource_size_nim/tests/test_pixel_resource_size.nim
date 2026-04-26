import std/unittest
import ../src/pixel_resource_size_lib

suite "Pixel Resource Size":
  test "rgba8 texture byte count":
    check rgba8Bytes(2, 3) == 24
    check textureBytes(2, 3, pfRgba8) == 24

  test "different formats use expected bytes per pixel":
    check bytesPerPixel(pfR8) == 1
    check bytesPerPixel(pfRg8) == 2
    check bytesPerPixel(pfRgb8) == 3
    check bytesPerPixel(pfRgba16F) == 8
    check bytesPerPixel(pfRgba32F) == 16

  test "mip chain is summed down to one pixel":
    check rgba8Bytes(4, 4, mipLevels = 3) == 84

  test "invalid dimensions produce zero bytes":
    check rgba8Bytes(0, 4) == 0
    check pixelBytes(4, 4, 0) == 0
