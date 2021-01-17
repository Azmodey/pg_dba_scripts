#!/bin/bash

# Show PostgreSQL log file

source ./settings.txt

PG_LOG_LINES=100						# PostgreSQL log lines to show

PG_LOG_FILENAME=`ls -t $PG_LOG_DIR/postgresql-*.log | head -n1`	# newest PostgreSQL log file in log_directory

# show PostgreSQL log
echo -e "PostgreSQL log: $PG_LOG_FILENAME"
tail -f --lines=$PG_LOG_LINES $PG_LOG_FILENAME
