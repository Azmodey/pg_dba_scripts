#!/bin/bash

# PostgreSQL status

source ./settings.txt

echo "PostgreSQL processes:"
ps -afH --forest -u postgres | grep -v sshd | grep -v bash | grep -v 'su - postgres' | grep -v 'ps -afH' | grep -v '/usr/bin/mc' | grep -v '\_ mc' | grep -v '/sbin/agetty'
echo

echo "PostgreSQL network connection:"
netstat -tulnp | grep "PID\|postgres\|postmaster"
echo

echo "PostgreSQL status:"
$PG_BIN/pg_ctl -D $PG_DATA status
echo

echo "PostgreSQL replication service (sender). Works on Master server:"
ps -aef | grep -v grep | grep "PID\|sender"
echo

echo "PGDATA: $PGDATA"
echo

echo "PostgreSQL replication service (receiver). Works on Replica server:"
ps -aef | grep -v grep | grep "PID\|receiver"
echo

echo "PostgreSQL logical replication service (worker). Works on Replica server:"
ps -aef | grep -v grep | grep "PID\|logical replication worker"
