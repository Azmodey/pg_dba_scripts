#!/bin/bash

# PostgreSQL start

source ./settings.txt

read -p "Start PostgreSQL (Y/N)? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    $PG_BIN/pg_ctl -D $PG_DATA start
fi
