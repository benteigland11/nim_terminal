## Example usage of Link Detector.

import link_detector_lib

let text = "Please visit https://github.com for details, or http://localhost:8080."
let links = detectLinks(text)

for link in links:
  echo "Found ", link.kind, ": ", link.text, " at [", link.startIdx, "..", link.endIdx, ")"

echo "Example complete."