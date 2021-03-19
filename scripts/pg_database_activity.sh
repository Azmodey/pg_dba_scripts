#!/bin/bash

# Show PostgreSQL database activity, connections memory consumption and more

source ./settings.txt

# Settings
PG_LOG_LINES=15							# Number of PostgreSQL log lines to display. 0 - disable output

PG_LOG_FILENAME=`ls -t $PG_LOG_DIR/postgresql-*.log | head -n1`	# newest PostgreSQL log file in log_directory


# ------------------------------------------------

# System
PLATFORM=`awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"'`	# Red Hat Enterprise Linux Server / CentOS Linux / Debian GNU/Linux / Ubuntu

# Title (1st line)
DATE=$(date '+%d.%m.%Y %H:%M:%S')
HOST=`hostname --short`
HOSTIP=`hostname -I | xargs`
UPTIME=`uptime`
UPTIME=${UPTIME#*load average: }

if [[ $PLATFORM == "Red Hat Enterprise Linux Server" || $PLATFORM == "CentOS Linux" ]]; then
  IOSTAT_AWAIT=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 11`
  IOSTAT_UTIL=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 15`
fi
if [[ $PLATFORM == "Debian GNU/Linux" ]]; then
  IOSTAT_R_AWAIT=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 11 | sed 's/,/./g'`
  IOSTAT_W_AWAIT=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 12 | sed 's/,/./g'`
  IOSTAT_UTIL=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 17 | sed 's/,/./g'`

  IOSTAT_AWAIT=`awk "BEGIN {print ($IOSTAT_R_AWAIT+$IOSTAT_W_AWAIT)/2}"`
fi
if [[ $PLATFORM == "Ubuntu" ]]; then
  IOSTAT_R_AWAIT=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 7 | sed 's/,/./g'`
  IOSTAT_W_AWAIT=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 13 | sed 's/,/./g'`
  IOSTAT_UTIL=`iostat -d -x -g ALL | grep ALL | tr -s " " | cut -d " " -f 22 | sed 's/,/./g'`

  IOSTAT_AWAIT=`awk "BEGIN {print ($IOSTAT_R_AWAIT+$IOSTAT_W_AWAIT)/2}"`
fi

POSTGRES_VER=`$PG_BIN/psql -t -c "select version();" | cut -d ' ' -f 3`
POSTGRES_VER_GLOB=`echo $POSTGRES_VER | awk '{print int($0)}'`	# Round PostgreSQL version (13.1 = 13)
DB_STATUS=`$PG_BIN/psql -t -c "select pg_is_in_recovery();"`
# echo "Status: ["$DB_STATUS"]"

if [[ $DB_STATUS == " f" ]]; then
  STATUS="${GREENLIGHT}[$HOST ($HOSTIP) / PostgreSQL $POSTGRES_VER / Master]${YELLOW}"
else
  STATUS="${PURPLELIGHT}[$HOST ($HOSTIP) / PostgreSQL $POSTGRES_VER / Replica]${YELLOW}"
fi


# ------------------------------------------------

if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

  # Backend Processes (Client connections)
  pid_clients=`$PG_BIN/psql -t -c "SELECT pid FROM pg_stat_activity where backend_type='client backend' and pid<>pg_backend_pid();"`

  total_clients_mem=0
  total_clients_count=0

  for pids in $pid_clients ; do
        mem=`ps -q $pids -eo rss | sed 1d`
        total_clients_mem=$((total_clients_mem+mem))
        ((total_clients_count++))
  done

  total_clients_mem_mb=$((total_clients_mem/1024))


  # Background Processes (Server connections)
  pid_server=`$PG_BIN/psql -t -c "SELECT pid FROM pg_stat_activity where backend_type<>'client backend' and pid<>pg_backend_pid();"`

  echo "PID| Database| Username| Application name| Client address| Backend type| Wait event type| Wait event| Memory (KB)| CPU% " > pg_database_activity_tmp.txt

  total_server_mem=0
  total_server_count=0

  for pids in $pid_server ; do
        mem=`ps -q $pids -eo rss | sed 1d`
        cpu=`ps -q $pids -eo pcpu | sed 1d`
        
        pid_client_info=`$PG_BIN/psql -t -c "SELECT datname as database, usename as username, application_name, client_addr, backend_type, wait_event_type, wait_event FROM pg_stat_activity where pid=$pids;"`
        echo "$pids|$pid_client_info|$mem| $cpu" >> pg_database_activity_tmp.txt

        total_server_mem=$((total_server_mem+mem))
        ((total_server_count++))
  done

  total_server_mem_mb=$((total_server_mem/1024))

fi


# ------------------------------------------------


# Title (1st line)
echo -e "${YELLOW}[$DATE] $STATUS [CPU load (1/5/15 min): $UPTIME] [Disk load: util $IOSTAT_UTIL %, await $IOSTAT_AWAIT ms] ${NC}"



# Title (2nd line). Disk usage & free
DIR_DATA_FREE=`df -h $PG_DATA | sed 1d | grep -v used | awk '{ print $4 "\t" }' | tr -d '\t'`	# free disk space for PG_DATA
DIR_ARC_FREE=`df -h $PG_ARC | sed 1d | grep -v used | awk '{ print $4 "\t" }' | tr -d '\t'`	# free disk space for PG_ARC
DIR_BASE_SIZE=`du -sh $PG_DATA/base | awk '{print $1}'`		# Base folder size

if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10
  DIR_WAL_SIZE=`du -sh $PG_DATA/pg_wal | awk '{print $1}'`	# WAL folder size
  WAL_STR="pg_wal $DIR_WAL_SIZE"
else
  DIR_WAL_SIZE=`du -sh $PG_DATA/pg_xlog | awk '{print $1}'`	# WAL folder size (PostgreSQL 9.6)
  WAL_STR="pg_xlog $DIR_WAL_SIZE"
fi

DIR_ARC_SIZE=`du -sh $PG_ARC | awk '{print $1}'`		# Archive logs folder size
SWAP_USED=`free | grep Swap | awk '{ print $3 "\t" }' | tr -d '\t'`

echo -e "${GREENLIGHT}Disk${NC}   | ${GREENLIGHT}PGDATA${NC} ${UNDERLINE}$PG_DATA${NC} / base $DIR_BASE_SIZE / $WAL_STR / ${CYANLIGHT}disk free $DIR_DATA_FREE${NC} | ${GREENLIGHT}Archive logs${NC} ${UNDERLINE}$PG_ARC${NC} / size $DIR_ARC_SIZE / ${CYANLIGHT}disk free $DIR_ARC_FREE ${NC}| ${GREENLIGHT}Swap used:${NC} ${CYANLIGHT}$SWAP_USED${NC}"



# Title (3rd line). Connections & memory totals
if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10
  total_mem=0
  total_mem=$((total_server_mem+total_clients_mem))
  total_mem_mb=$((total_mem/1024))
  total_count=0
  total_count=$((total_clients_count+total_server_count))
  echo -e "${GREENLIGHT}Memory${NC} | PostgreSQL processes ($total_count) memory consumption: $total_mem_mb MB | ${YELLOW}Backend processes ($total_clients_count) $total_clients_mem_mb MB${NC} | ${YELLOW}Background processes ($total_server_count) $total_server_mem_mb MB${NC}"
fi

echo



# ------------------------------------------------

# Background Processes (Server connections)
if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

  echo -e "${GREENLIGHT}Background processes ($total_server_count) memory consumption: $total_server_mem_mb MB${NC}"
  echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"

  if [[ $PLATFORM == "Red Hat Enterprise Linux Server" || $PLATFORM == "CentOS Linux"  ]]; then
    sort -t '|' -k9 -n pg_database_activity_tmp.txt | column -t -s '|' -o ' |'	# sort file by memory column, then show like table
  fi

  if [[ $PLATFORM == "Debian GNU/Linux" || $PLATFORM == "Ubuntu" ]]; then
    sort -t '|' -k9 -n pg_database_activity_tmp.txt | column -t -s '|'	# sort file by memory column
  fi

  echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------"
  echo
  rm pg_database_activity_tmp.txt

fi



# Database statistics
if [[ $POSTGRES_VER_GLOB -ge 9 && $POSTGRES_VER_GLOB -le 11 ]]; then	# >= 9 and <= 11
  echo -e "${GREENLIGHT}Database statistics:${NC}"
  $PG_BIN/psql -c "select p.datid, p.datname, pg_size_pretty(pg_database_size(p.datname)) as size, p.numbackends as connections, p.xact_commit as commit, p.xact_rollback as rollback, p.blks_read, p.blks_hit, p.temp_files, round(p.temp_bytes/1024/1024) as temp_mb, p.deadlocks, TO_CHAR(p.stats_reset, 'dd.mm.yyyy') as stat_reset from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;" | grep -v ' row)' | grep -v ' rows)'
fi

if [[ $POSTGRES_VER_GLOB -ge 12 ]]; then	# >= 12
  echo -e "${GREENLIGHT}Database statistics:${NC}"
  $PG_BIN/psql -c "select p.datid, p.datname, pg_size_pretty(pg_database_size(p.datname)) as size, p.numbackends as connections, p.xact_commit as commit, p.xact_rollback as rollback, p.blks_read, p.blks_hit, p.temp_files, round(p.temp_bytes/1024/1024) as temp_mb, p.deadlocks, p.checksum_failures as chksum_fail, TO_CHAR(p.checksum_last_failure, 'dd.mm.yyyy HH24:MI:SS') as chksum_f_date, TO_CHAR(p.stats_reset, 'dd.mm.yyyy') as stat_reset from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;" | grep -v ' row)' | grep -v ' rows)'
fi



# Wait events (1st column) & Lock events (2nd column)
echo -e "${GREENLIGHT}Wait events:                                                 ${YELLOW}Lock events:${NC}"

# Wait events
$PG_BIN/psql -c "select wait_event_type, wait_event, count(*) as connections from pg_stat_activity where wait_event_type is not null and wait_event_type <> 'Activity' group by wait_event_type, wait_event order by 3 desc;" | grep -v ' row)' | grep -v ' rows)' > pg_database_activity_wait.txt

# Lock events
$PG_BIN/psql -c "select d.datname, l.locktype, l.mode, count(*) from pg_locks l, pg_database d where l.database=d.oid and l.database is not null and l.granted = true group by d.datname, l.locktype, l.mode order by 4 desc;" | grep -v ' row)' | grep -v ' rows)' > pg_database_activity_locks.txt

paste pg_database_activity_wait.txt pg_database_activity_locks.txt | awk -F'\t' '{printf("%-60s %s\n",$1,$2)}'
rm pg_database_activity_wait.txt
rm pg_database_activity_locks.txt



# Archiving status
archiving_status=`$PG_BIN/psql -t -c "select * from pg_stat_archiver;"`
if [[ ${#archiving_status} >0 ]]; then

  echo -e "${GREENLIGHT}Archiving status:${NC}"

  if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

    if [[ $DB_STATUS == " f" ]]; then
      # master
      $PG_BIN/psql -c "
      select archived_count as archived_cnt, pg_walfile_name(pg_current_wal_lsn()), last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time,
      ('x'||substring(pg_walfile_name(pg_current_wal_lsn()),9,8))::bit(32)::int*256 +
      ('x'||substring(pg_walfile_name(pg_current_wal_lsn()),17))::bit(32)::int -
      ('x'||substring(last_archived_wal,9,8))::bit(32)::int*256 -
      ('x'||substring(last_archived_wal,17))::bit(32)::int as arc_diff
      --TO_CHAR(stats_reset, 'dd.mm.yyyy') as stats_reset
      from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
    else
      # replica
      $PG_BIN/psql -c "
      select archived_count, last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time, TO_CHAR(stats_reset, 'dd.mm.yyyy HH24:MI:SS') as stats_reset
      from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi

  if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
    $PG_BIN/psql -c "
    select archived_count, last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time, TO_CHAR(stats_reset, 'dd.mm.yyyy HH24:MI:SS') as stats_reset
    from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
  fi

  PG_LOG_LINES=$((PG_LOG_LINES-5))

fi



# Replication status (Master)
replication_status=`$PG_BIN/psql -t -c "select * from pg_stat_replication;"`
if [[ ${#replication_status} >0 ]]; then

  echo -e "${GREENLIGHT}Replication status (Master):${NC}"

  if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10
    $PG_BIN/psql -c "
    SELECT r.client_addr AS client_addr, r.usename AS username, r.application_name AS app_name, r.pid, s.slot_name, s.slot_type, r.state, r.sync_state AS MODE,
         (pg_wal_lsn_diff(pg_current_wal_lsn(), r.sent_lsn) / 1024)::int AS send_lag,   -- sending_lag (network problems)
         (pg_wal_lsn_diff(r.sent_lsn, r.flush_lsn) / 1024)::int AS receive_lag,            -- receiving_lag
         (pg_wal_lsn_diff(r.sent_lsn, r.write_lsn) / 1024)::int AS WRITE,                    -- disks problems
         (pg_wal_lsn_diff(r.write_lsn, r.flush_lsn) / 1024)::int AS FLUSH,                   -- disks problems
         (pg_wal_lsn_diff(r.flush_lsn, r.replay_lsn) / 1024)::int AS replay_lag,          -- replaying_lag (disks/CPU problems)
         (pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn))::int / 1024 AS total_lag
    FROM pg_stat_replication r LEFT JOIN pg_replication_slots s ON (r.pid = s.active_pid);" | grep -v ' row)' | grep -v ' rows)'
  fi

  if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
    $PG_BIN/psql -c "
    SELECT r.client_addr AS client_addr, r.usename AS username, r.application_name AS app_name, r.pid, s.slot_name, s.slot_type, r.state, r.sync_state AS MODE
    FROM pg_stat_replication r LEFT JOIN pg_replication_slots s ON (r.pid = s.active_pid);" | grep -v ' row)' | grep -v ' rows)'
  fi

  PG_LOG_LINES=$((PG_LOG_LINES-5))

fi



# Replication status (Replica)
if [[ $DB_STATUS != " f" ]]; then

  echo -e "${GREENLIGHT}Replication status (Replica):${NC}"

  if [[ $POSTGRES_VER_GLOB -eq 13 ]]; then	# = 13
    $PG_BIN/psql -c "
    SELECT sender_host, sender_port, pid, slot_name, status, flushed_lsn, received_tli,
	CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
             ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
        END AS log_delay
    FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
  fi

  if [[ $POSTGRES_VER_GLOB -ge 11 && $POSTGRES_VER_GLOB -le 12 ]]; then	# >= 11 and <= 12
    $PG_BIN/psql -c "
    SELECT sender_host, sender_port, pid, slot_name, status, received_lsn, received_tli,
	CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
             ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
        END AS log_delay
    FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
  fi

  if [[ $POSTGRES_VER_GLOB -eq 10 ]]; then	# = 10
    $PG_BIN/psql -c "
    SELECT pid, slot_name, status, received_lsn, received_tli,
	CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
             ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
        END AS log_delay
    FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
  fi

  if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
    $PG_BIN/psql -c "
    SELECT pid, slot_name, status, received_lsn, received_tli, 
           TO_CHAR(last_msg_send_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_send_time, TO_CHAR(last_msg_receipt_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_receipt_time 
    FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
  fi

  PG_LOG_LINES=$((PG_LOG_LINES-5))

fi



# Logical Replication status (Replica)
if [[ $POSTGRES_VER_GLOB -gt 9 ]]; then	# > 9

  logical_replication=`$PG_BIN/psql -t -c "select * from pg_stat_subscription;"`
  if [[ ${#logical_replication} >0 ]]; then

    echo -e "${GREENLIGHT}Logical Replication status (Replica):${NC}"

    $PG_BIN/psql -c "
    SELECT subid, subname, pid, relid, received_lsn, TO_CHAR(last_msg_send_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_send_time, 
           TO_CHAR(last_msg_receipt_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_receipt_time, latest_end_lsn, TO_CHAR(latest_end_time, 'dd.mm.yyyy HH24:MI:SS') as latest_end_time, 
           (pg_wal_lsn_diff(received_lsn, latest_end_lsn) / 1024)::int AS subscription_lag 
    FROM pg_stat_subscription;" | grep -v ' row)' | grep -v ' rows)'

    PG_LOG_LINES=$((PG_LOG_LINES-5))

  fi

fi



# PostgreSQL system process activity progress

# PostgreSQL 9.6 and higher
progress_vacuum=`$PG_BIN/psql -t -c "select * from pg_stat_progress_vacuum;"`
if [[ ${#progress_vacuum} >0 ]]; then
  echo -e "${YELLOW}VACUUM progress:${NC}"
  $PG_BIN/psql -c "select a.query, p.datname, p.phase, p.heap_blks_total, p.heap_blks_scanned, p.heap_blks_vacuumed, p.index_vacuum_count, p.max_dead_tuples, p.num_dead_tuples from pg_stat_progress_vacuum p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
  PG_LOG_LINES=$((PG_LOG_LINES-5))
fi


# PostgreSQL 12 and higher: pg_stat_progress_analyze, pg_stat_progress_basebackup
if [[ $POSTGRES_VER_GLOB -ge 12 ]]; then	# >= 12

  progress_create_index=`$PG_BIN/psql -t -c "select * from pg_stat_progress_create_index;"`
  if [[ ${#progress_create_index} >0 ]]; then
    echo -e "${YELLOW}CREATE INDEX progress:${NC}"
    $PG_BIN/psql -c "SELECT a.query, p.datname, p.command, p.phase, p.lockers_total, p.lockers_done, p.blocks_total, p.blocks_done, p.tuples_total, p.tuples_done FROM pg_stat_progress_create_index p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    PG_LOG_LINES=$((PG_LOG_LINES-5))
  fi

  progress_cluster=`$PG_BIN/psql -t -c "select * from pg_stat_progress_cluster;"`
  if [[ ${#progress_cluster} >0 ]]; then
    echo -e "${YELLOW}VACUUM FULL or CLUSTER progress:${NC}"
    $PG_BIN/psql -c "select a.query, p.datname, p.command, p.phase, p.heap_tuples_scanned, p.heap_tuples_written, p.index_rebuild_count from pg_stat_progress_cluster p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    PG_LOG_LINES=$((PG_LOG_LINES-5))
  fi

fi


# PostgreSQL 13 and higher: pg_stat_progress_analyze, pg_stat_progress_basebackup
if [[ $POSTGRES_VER_GLOB -ge 13 ]]; then	# >= 13

  progress_analyze=`$PG_BIN/psql -t -c "select * from pg_stat_progress_analyze;"`
  if [[ ${#progress_analyze} >0 ]]; then
    echo -e "${YELLOW}ANALYZE progress:${NC}"
    $PG_BIN/psql -c "SELECT a.query, p.datname, p.phase, p.sample_blks_total, p.sample_blks_scanned, p.ext_stats_total, p.ext_stats_computed, p.child_tables_total, p.child_tables_done FROM pg_stat_progress_analyze p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    PG_LOG_LINES=$((PG_LOG_LINES-5))
  fi

  progress_basebackup=`$PG_BIN/psql -t -c "select * from pg_stat_progress_basebackup;"`
  if [[ ${#progress_basebackup} >0 ]]; then
    echo -e "${YELLOW}PG_BASEBACKUP progress:${NC}"
    $PG_BIN/psql -c "SELECT a.query, p.pid, p.phase, p.backup_total, p.backup_streamed, p.tablespaces_total, p.tablespaces_streamed FROM pg_stat_progress_basebackup p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    PG_LOG_LINES=$((PG_LOG_LINES-5))
  fi

fi



# show PostgreSQL log
if [[ $PG_LOG_LINES -gt 0 ]]; then

  echo -e "${GREENLIGHT}PostgreSQL log: $PG_LOG_FILENAME${NC}"
  tail --lines=$PG_LOG_LINES $PG_LOG_FILENAME

fi
