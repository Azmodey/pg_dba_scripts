#!/bin/bash

# PostgreSQL reload configuration

source ./settings.txt

PG_LOG_LINES=500						# PostgreSQL log lines to grep

PG_LOG_FILENAME=`ls -t $PG_LOG_DIR/postgresql-*.log | head -n1`	# newest PostgreSQL log file in log_directory


read -p "Reload PostgreSQL configuration (Y/N)? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    $PG_BIN/pg_ctl reload -D $PG_DATA

    echo
    echo -e "PostgreSQL log: $PG_LOG_FILENAME"
    sleep 1

    # show PostgreSQL log
    tail --lines=$PG_LOG_LINES $PG_LOG_FILENAME | grep 'reloading\|parameter\|configuration'

    # show Pending restart parameters
    pending_restart=`$PG_BIN/psql -t -c "SELECT * FROM pg_settings WHERE pending_restart;"`
    if [[ ${#pending_restart} >0 ]]; then
      echo
      echo "Pending restart parameters:"
      $PG_BIN/psql -x -c "SELECT * FROM pg_settings WHERE pending_restart;"
    fi

fi
