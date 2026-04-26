#!/usr/bin/env bash
# Hammer the SGR (color/attr) path — exercises screen_buffer attribute storage.
while :; do
  printf '\e[%d;%d;%d;%d;%dm%s\e[0m\n' $((RANDOM%8+30)) $((RANDOM%8+40)) 1 4 7 'colored line'
done
