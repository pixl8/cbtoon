#!/bin/bash

cd "$( dirname "$0" )"

box install

exitcode=0

box stop name="cbtoontests" 2>/dev/null || true
box start directory="./tests/" serverConfigFile="./tests/server-cbtoontests.json"
box testbox run verbose=true || exitcode=1
box stop name="cbtoontests"

exit $exitcode
