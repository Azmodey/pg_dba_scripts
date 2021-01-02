#!/bin/bash

# Refresh pg_database_activity.sh script

i=0
while [ i==0 ]
do
  ./pg_database_activity.sh > pg_database_activity.txt
  clear
  cat ./pg_database_activity.txt
  sleep 5
done
