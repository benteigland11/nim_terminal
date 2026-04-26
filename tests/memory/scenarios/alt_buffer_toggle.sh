#!/usr/bin/env bash
# Repeatedly enter and leave the alternate screen buffer (vim/htop pattern).
while :; do
  printf '\e[?1049h'
  printf 'alt screen content %s\n' "$(date +%s%N)"
  printf '\e[?1049l'
  printf 'normal screen %s\n' "$(date +%s%N)"
done
