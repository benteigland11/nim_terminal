## Example usage of Workspace Chrome.

import workspace_chrome_lib

let bounds = WorkspaceRect(x: 0, y: 32, w: 1280, h: 720)
let regions = threeColumnRegions(bounds, catalogWidth = 240, inspectorWidth = 320, minCenterWidth = 480)
doAssert regions.catalog.w == 240
doAssert regions.inspector.w == 320
doAssert regions.center.w == 720
