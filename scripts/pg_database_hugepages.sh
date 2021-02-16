#!/bin/bash

# Get Number of Required HugePages
# https://www.percona.com/blog/2018/08/29/tune-linux-kernel-parameters-for-postgresql-optimization/

echo "-----------------------------------"
echo "Free and used memory in the system:"
free -hw
echo

echo "-----------------------------------"
echo "Transparent Huge Pages (THP):"
echo " On: [always] madvise never"
echo "Off: always madvise [never]"
echo
echo "Status:"
cat /sys/kernel/mm/transparent_hugepage/enabled
echo
echo "Tip: disable it"
echo

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
