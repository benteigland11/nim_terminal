## Host wiring helpers for the overlay popup stack.

import ../cg/frontend_overlay_stack_nim/src/overlay_stack_lib as overlay_lib

func overlayContentBounds*(headerHeight, winWidth, winHeight: int): overlay_lib.OverlayRect =
  overlay_lib.OverlayRect(
    x: 0,
    y: headerHeight,
    w: winWidth,
    h: max(0, winHeight - headerHeight),
  )

func catalogInspectButtonRect*(
  catalog: overlay_lib.OverlayRect;
  footerHeight: int;
  cellWidth, cellHeight: int;
  pad: int;
): overlay_lib.OverlayRect =
  const label = "Inspect"
  if catalog.w <= 0 or catalog.h <= 0 or footerHeight <= 0:
    overlay_lib.OverlayRect()
  else:
    let btnW = overlay_lib.buttonPixelWidth(cellWidth, label, 10)
    let btnH = cellHeight + 8
    overlay_lib.OverlayRect(
      x: catalog.x + pad,
      y: catalog.y + catalog.h - footerHeight + max(0, (footerHeight - btnH) div 2),
      w: btnW,
      h: btnH,
    )
