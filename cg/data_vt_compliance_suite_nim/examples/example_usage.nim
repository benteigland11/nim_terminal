## Example: Using the VT Compliance Suite to verify a terminal.

import vt_compliance_suite_lib

# In a real project, you would import your own terminal and run the cases:
#
# for tc in loadSuite("vectors/core_vt.json"):
#   myTerm.feed(tc.input)
#   assert myTerm.cursor == tc.expect.cursor

let suitePath = "src/vectors/core_vt.json"
let cases = loadSuite(suitePath)
echo "Loaded ", cases.len, " compliance cases."
for tc in cases:
  echo " - ", tc.name
