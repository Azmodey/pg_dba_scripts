#!/bin/bash

# PostgreSQL stop

source ./settings.txt

read -p "Stop PostgreSQL (Y/N)? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    $PG_BIN/pg_ctl -D $PG_DATA stop
fi
