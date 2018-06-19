#!/bin/bash

# This should be the current working directory, for absolute safety, I hard code this for procceses like this
RUN_HOME=$(pwd)

SAND=""$RUN_HOME"/Sandbox"$1""
FAIL=""$RUN_HOME"/failed.txt"
DEBS=""$RUN_HOME"/debs"


for m in $(ls "$SAND"); do
    SAM="$SAND"/"$m"
    make -C "$SAM" package > /dev/null 2> "$SAM"/errs.txt
    test -d "$SAM"/packages && mv "$SAM"/packages/* "$DEBS" || echo "$m" >> "$FAIL"
done
