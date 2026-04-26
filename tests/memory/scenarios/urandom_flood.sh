#!/usr/bin/env bash
# Hex-dump random bytes — high-throughput VT byte stream.
head -c 50M /dev/urandom | xxd | head -n 200000
