#!/bin/bash

# Get Number of Required HugePages

echo "-----------------------------------"
echo "Current Huge pages:"
echo
grep Huge /proc/meminfo
echo
echo "-----------------------------------"
echo "Number of Required HugePages:"
echo

pid=`head -1 $PGDATA/postmaster.pid`
echo "Pid:            $pid"

peak=`grep ^VmPeak /proc/$pid/status | awk '{ print $2 }'`
echo "VmPeak:            $peak kB"

hps=`grep ^Hugepagesize /proc/meminfo | awk '{ print $2 }'`
echo "Hugepagesize:   $hps kB"

hp=$((peak/hps))
echo Set Huge Pages:     $hp

echo
echo "-----------------------------------"
