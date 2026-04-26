## Byte-size helpers for pixel-backed resources.

type
  PixelFormat* = enum
    pfR8,
    pfRg8,
    pfRgb8,
    pfRgba8,
    pfRgba16F,
    pfRgba32F

func bytesPerPixel*(format: PixelFormat): int =
  case format
  of pfR8: 1
  of pfRg8: 2
  of pfRgb8: 3
  of pfRgba8: 4
  of pfRgba16F: 8
  of pfRgba32F: 16

func pixelBytes*(width, height, bytesPerPixel: int; mipLevels: int = 1): int64 =
  ## Estimate storage for a 2D pixel resource. Mips are summed down to 1x1.
  if width <= 0 or height <= 0 or bytesPerPixel <= 0 or mipLevels <= 0:
    return 0

  var w = width
  var h = height
  for _ in 0 ..< mipLevels:
    result += int64(w) * int64(h) * int64(bytesPerPixel)
    if w == 1 and h == 1:
      break
    w = max(1, w div 2)
    h = max(1, h div 2)

func textureBytes*(width, height: int; format: PixelFormat = pfRgba8;
                   mipLevels: int = 1): int64 =
  pixelBytes(width, height, bytesPerPixel(format), mipLevels)

func rgba8Bytes*(width, height: int; mipLevels: int = 1): int64 =
  textureBytes(width, height, pfRgba8, mipLevels)
