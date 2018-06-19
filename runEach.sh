#!/bin/bash

# This should be the current working directory, for absolute safety, I hard code this for procceses like this
RUN_HOME=$(pwd)

FAIL=""$RUN_HOME"/failed.txt"
DEBS=""$RUN_HOME"/debs"

rm -f "$FAIL"
rm -rf "$DEBS"
mkdir "$DEBS"

m=0
while ((m < 8)); do
    "$RUN_HOME"/theosSet.sh "$m" &
    m=$((m+1))
done
