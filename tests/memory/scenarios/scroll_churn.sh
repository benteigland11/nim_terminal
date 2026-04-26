#!/usr/bin/env bash
# Continuous line emission — exercises scrollback growth + damage tracking.
for i in $(seq 1 100000); do
  echo "line $i $(date +%s%N)"
done
