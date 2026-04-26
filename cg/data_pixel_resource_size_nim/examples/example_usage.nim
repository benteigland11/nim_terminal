## Example usage of Pixel Resource Size.

import pixel_resource_size_lib

let iconBytes = rgba8Bytes(64, 64)
let atlasBytes = textureBytes(1024, 1024, pfRgba8, mipLevels = 1)

doAssert iconBytes == 16_384
doAssert atlasBytes == 4_194_304
