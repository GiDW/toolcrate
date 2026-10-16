#!/bin/sh
# Poppler is a set of tools, not one: the first argument names the one to run.
if [ "$#" -eq 0 ]; then
  echo "usage: <tool> [args]; tools: $(cd /usr/bin && ls pdf* | tr '\n' ' ')" >&2
  exit 2
fi
exec "$@"
