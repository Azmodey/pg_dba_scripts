#!/bin/bash

# PostgreSQL databases information

source ./settings.txt

# Array of PosgtreSQL servers
declare -a servers_list=("localhost")									# Local server
#declare -a servers_list=("pg_server_1" "pg_server_2" "pg_server_3")	# Servers list, hostnames. Format: "pg_server_1" "pg_server_2" ...


# ------------------------------------------------

# Databases list
datnames=`$PG_BIN/psql -t -c "SELECT p.datname from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;"`


# ------------------------------------------------

for server in "${servers_list[@]}"; do

  echo
  echo -e "${CYANLIGHT}--- [$server] -----------------------------------------------------------------------------------------------------------------------------------------------${NC}"

  # Databases list
  datnames=`$PG_BIN/psql -t -h $server -c "SELECT p.datname from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;"`


  # Title (1st line)
  DATE=`$PG_BIN/psql -t -h $server -c "select TO_CHAR(now(), 'dd.mm.yyyy HH24:MI:SS');" | xargs`
  HOSTIP=`ping -c1 -n $server | head -n1 | sed "s/.*(\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\)).*/\1/g"`
  POSTGRES_VER=`$PG_BIN/psql -t -h $server -c "select version();" | cut -d ' ' -f 3`
  POSTGRES_VER_GLOB=`echo $POSTGRES_VER | awk '{print int($0)}'`	# Round PostgreSQL version (13.1 = 13)
  DB_STATUS=`$PG_BIN/psql -t -h $server -c "select pg_is_in_recovery();"`
  # echo "Status: ["$DB_STATUS"]"

  # Time lag
  if [[ -z "$TIME" ]]; then
     # init
     TIME=`$PG_BIN/psql -t -h $server -c "select now();" | xargs`
  else
     TIME_CURR=`$PG_BIN/psql -t -h $server -c "select now();" | xargs`
     TIME_LAG=`$PG_BIN/psql -t -h $server -c "select TO_CHAR(age('$TIME_CURR', '$TIME'), 'HH24:MI:SS');" | xargs`

     if [[ $TIME_LAG != '00:00:00' && $TIME_LAG != '00:00:01' ]]; then
       LAG=". ${REDLIGHT}Lag: $TIME_LAG${NC}${YELLOW}"
     else
       LAG=""
     fi
  fi

  # Data checksums
  CHECKSUM=`$PG_BIN/psql -t -h $server -c "SHOW data_checksums;" | xargs`
  if [[ $CHECKSUM == "on" ]]; then
    CHECKSUM_STR="${GREENLIGHT}[Data checksums: $CHECKSUM]${NC}"
  else
    CHECKSUM_STR="${REDLIGHT}[Data checksums: $CHECKSUM]${NC}"
  fi

  #
  if [[ $DB_STATUS == " f" ]]; then
    STATUS="${GREENLIGHT}[$server ($HOSTIP) / PostgreSQL $POSTGRES_VER / Master]${YELLOW}"
  else
    STATUS="${PURPLELIGHT}[$server ($HOSTIP) / PostgreSQL $POSTGRES_VER / Replica]${YELLOW}"
  fi

  echo -e "${YELLOW}[Server time: $DATE$LAG] $STATUS $CHECKSUM_STR ${NC}"



  # Database statistics
  echo
  if [[ $POSTGRES_VER_GLOB -ge 9 && $POSTGRES_VER_GLOB -le 11 ]]; then	# >= 9 and <= 11
    echo -e "${GREENLIGHT}Database statistics:${NC}"
    $PG_BIN/psql -h $server -c "select p.datid, p.datname, pg_size_pretty(pg_database_size(p.datname)) as size, p.numbackends as connections, p.xact_commit as commit, p.xact_rollback as rollback, p.blks_read, p.blks_hit, p.temp_files, round(p.temp_bytes/1024/1024) as temp_mb, p.deadlocks, TO_CHAR(p.stats_reset, 'dd.mm.yyyy') as stat_reset from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;" | grep -v ' row)' | grep -v ' rows)'
  fi

  if [[ $POSTGRES_VER_GLOB -ge 12 ]]; then	# >= 12
    echo -e "${GREENLIGHT}Database statistics:${NC}"
    $PG_BIN/psql -h $server -c "select p.datid, p.datname, pg_size_pretty(pg_database_size(p.datname)) as size, p.numbackends as connections, p.xact_commit as commit, p.xact_rollback as rollback, p.blks_read, p.blks_hit, p.temp_files, round(p.temp_bytes/1024/1024) as temp_mb, p.deadlocks, p.checksum_failures as chksum_fail, TO_CHAR(p.checksum_last_failure, 'dd.mm.yyyy HH24:MI:SS') as chksum_f_date, TO_CHAR(p.stats_reset, 'dd.mm.yyyy') as stat_reset from pg_stat_database p, pg_database d where p.datid=d.oid and d.datistemplate = false order by p.datid;" | grep -v ' row)' | grep -v ' rows)'
  fi
  


  # Wait events (1st column) & Lock events (2nd column)
  echo -e "${GREENLIGHT}Wait events:                                                 ${YELLOW}Lock events:${NC}"

  # Wait events
  $PG_BIN/psql -h $server -c "select wait_event_type, wait_event, count(*) as connections from pg_stat_activity where wait_event_type is not null and wait_event_type <> 'Activity' group by wait_event_type, wait_event order by 3 desc;" | grep -v ' row)' | grep -v ' rows)' > pg_database_activity_wait.txt

  # Lock events
  $PG_BIN/psql -h $server -c "select d.datname, l.locktype, l.mode, count(*) from pg_locks l, pg_database d where l.database=d.oid and l.database is not null and l.granted = true group by d.datname, l.locktype, l.mode order by 4 desc;" | grep -v ' row)' | grep -v ' rows)' > pg_database_activity_locks.txt

  paste pg_database_activity_wait.txt pg_database_activity_locks.txt | awk -F'\t' '{printf("%-60s %s\n",$1,$2)}'
  rm pg_database_activity_wait.txt
  rm pg_database_activity_locks.txt



  # Archiving status
  archiving_status=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_archiver;"`
  if [[ ${#archiving_status} >0 ]]; then

    echo -e "${GREENLIGHT}Archiving status:${NC}"

    if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

      if [[ $DB_STATUS == " f" ]]; then
        # master
        $PG_BIN/psql -h $server -c "
        select archived_count as archived_cnt, pg_walfile_name(pg_current_wal_lsn()), last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time,
        ('x'||substring(pg_walfile_name(pg_current_wal_lsn()),9,8))::bit(32)::int*256 +
        ('x'||substring(pg_walfile_name(pg_current_wal_lsn()),17))::bit(32)::int -
        ('x'||substring(last_archived_wal,9,8))::bit(32)::int*256 -
        ('x'||substring(last_archived_wal,17))::bit(32)::int as arc_diff
        --TO_CHAR(stats_reset, 'dd.mm.yyyy') as stats_reset
        from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
      else
        # replica
        $PG_BIN/psql -h $server -c "
        select archived_count, last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time, TO_CHAR(stats_reset, 'dd.mm.yyyy HH24:MI:SS') as stats_reset
        from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
      fi

    fi

    if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
      $PG_BIN/psql -h $server -c "
      select archived_count, last_archived_wal, TO_CHAR(last_archived_time, 'dd.mm.yyyy HH24:MI:SS') as last_archived_time, failed_count, last_failed_wal, TO_CHAR(last_failed_time, 'dd.mm.yyyy HH24:MI:SS') as last_failed_time, TO_CHAR(stats_reset, 'dd.mm.yyyy HH24:MI:SS') as stats_reset
      from pg_stat_archiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # Replication status (Master)
  replication_status=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_replication;"`
  if [[ ${#replication_status} >0 ]]; then

    echo -e "${GREENLIGHT}Replication status (Master):${NC}"

    if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10
      $PG_BIN/psql -h $server -c "
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
      $PG_BIN/psql -h $server -c "
      SELECT r.client_addr AS client_addr, r.usename AS username, r.application_name AS app_name, r.pid, s.slot_name, s.slot_type, r.state, r.sync_state AS MODE
      FROM pg_stat_replication r LEFT JOIN pg_replication_slots s ON (r.pid = s.active_pid);" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # Replication status (Replica)
  if [[ $DB_STATUS != " f" ]]; then

    echo -e "${GREENLIGHT}Replication status (Replica):${NC}"

    if [[ $POSTGRES_VER_GLOB -eq 13 ]]; then	# = 13
      $PG_BIN/psql -h $server -c "
      SELECT sender_host, sender_port, pid, slot_name, status, flushed_lsn, received_tli,
      CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
               ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
          END AS log_delay
      FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

    if [[ $POSTGRES_VER_GLOB -ge 11 && $POSTGRES_VER_GLOB -le 12 ]]; then	# >= 11 and <= 12
      $PG_BIN/psql -h $server -c "
      SELECT sender_host, sender_port, pid, slot_name, status, received_lsn, received_tli,
      CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
               ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
          END AS log_delay
      FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

    if [[ $POSTGRES_VER_GLOB -eq 10 ]]; then	# = 10
      $PG_BIN/psql -h $server -c "
      SELECT pid, slot_name, status, received_lsn, received_tli,
         CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
             ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
        END AS log_delay
      FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

    if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
      $PG_BIN/psql -h $server -c "
      SELECT pid, slot_name, status, received_lsn, received_tli, 
             TO_CHAR(last_msg_send_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_send_time, TO_CHAR(last_msg_receipt_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_receipt_time 
      FROM pg_stat_wal_receiver;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # Logical Replication status (Replica)
  if [[ $POSTGRES_VER_GLOB -gt 9 ]]; then	# > 9

    logical_replication=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_subscription;"`
    if [[ ${#logical_replication} >0 ]]; then
      echo -e "${GREENLIGHT}Logical Replication status (Replica):${NC}"

      $PG_BIN/psql -h $server -c "
      SELECT subid, subname, pid, relid, received_lsn, TO_CHAR(last_msg_send_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_send_time, 
           TO_CHAR(last_msg_receipt_time, 'dd.mm.yyyy HH24:MI:SS') as last_msg_receipt_time, latest_end_lsn, TO_CHAR(latest_end_time, 'dd.mm.yyyy HH24:MI:SS') as latest_end_time, 
           (pg_wal_lsn_diff(received_lsn, latest_end_lsn) / 1024)::int AS subscription_lag 
      FROM pg_stat_subscription;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # ---------------------------------------------------------------------------------------------------------------------------------  
  # (Added)

  # Replication - Publication status. Publishing to logical replication is only allowed from the master server (PostgreSQL 13)
  if [[ $DB_STATUS == " f" ]]; then

    for datname in $datnames ; do

      if [[ $POSTGRES_VER_GLOB -eq 10 ]]; then	# = 10
        publication_status=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_publication;"`
        if [[ ${#publication_status} >0 ]]; then
          echo -e "${GREENLIGHT}Logical Replication - Publications. Dabatabase: ${UNDERLINE}$datname${NC}"
          $PG_BIN/psql --dbname=$datname -h $server -c "select p.oid, p.pubname, a.rolname as pubowner, p.puballtables, p.pubinsert, p.pubupdate, p.pubdelete from pg_publication p, pg_authid a where p.pubowner=a.oid;" | grep -v ' row)' | grep -v ' rows)'
        fi
      fi

      if [[ $POSTGRES_VER_GLOB -ge 11 ]]; then	# >= 11
        publication_status=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_publication;"`
        if [[ ${#publication_status} >0 ]]; then
          echo -e "${GREENLIGHT}Logical Replication - Publications. Dabatabase: ${UNDERLINE}$datname${NC}"
          $PG_BIN/psql --dbname=$datname -h $server -c "select p.oid, p.pubname, a.rolname as pubowner, p.puballtables, p.pubinsert, p.pubupdate, p.pubdelete, p.pubtruncate from pg_publication p, pg_authid a where p.pubowner=a.oid;" | grep -v ' row)' | grep -v ' rows)'
        fi
      fi

    done

  fi


  # Replication - Subscription status
  if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

    subscription_status=`$PG_BIN/psql -t -h $server -c "select * from pg_subscription;"`
    if [[ ${#subscription_status} >0 ]]; then
      echo -e "${GREENLIGHT}Logical Replication - Subscriptions:${NC}"
      $PG_BIN/psql -h $server -c "select p.oid, d.datname as subdatname, p.subname, a.rolname as subowner, p.subenabled, p.subconninfo, p.subslotname, p.subsynccommit, p.subpublications from pg_subscription p, pg_database d, pg_authid a where p.subdbid = d.oid and p.subowner = a.oid;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # ---------------------------------------------------------------------------------------------------------------------------------  
  # (Added)


  if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10

  for datname in $datnames ; do


    # Foreign Data Wrapper - access data stored in external PostgreSQL servers
    foreign_data_wrapper=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_foreign_data_wrapper;"`
    if [[ ${#foreign_data_wrapper} >0 ]]; then
      echo -e "${GREEN}Foreign Data Wrapper. Dabatabase: ${UNDERLINE}$datname${NC}"
      $PG_BIN/psql --dbname=$datname -h $server -c "
      SELECT fdw.oid, fdw.fdwname, fdw.fdwowner, a.rolname as fdwowner_role, fdw.fdwhandler, fdw.fdwvalidator, p1.proname, p2.proname, p1.proowner, p2.proowner, fdw.fdwacl, fdw.fdwoptions 
      FROM pg_foreign_data_wrapper fdw 
      JOIN pg_authid a ON fdw.fdwowner=a.oid
      LEFT JOIN pg_proc p1 ON fdw.fdwhandler = p1.oid
      LEFT JOIN pg_proc p2 ON fdw.fdwvalidator = p2.oid;" | grep -v ' row)' | grep -v ' rows)'
    fi


    # Foreign Servers
    foreign_server=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_foreign_server;"`
    if [[ ${#foreign_server} >0 ]]; then
      echo -e "${GREEN}Foreign Servers. Dabatabase: ${UNDERLINE}$datname${NC}"
      $PG_BIN/psql --dbname=$datname -h $server -c "
      SELECT s.oid, s.srvname, a.rolname as srvowner, s.srvoptions, b.fdwname, s.srvversion, s.srvtype 
      FROM pg_foreign_server s, pg_foreign_data_wrapper b, pg_authid a
      WHERE b.oid=s.srvfdw AND s.srvowner=a.oid;" | grep -v ' row)' | grep -v ' rows)'
    fi


    # Foreign Users mappings
    foreign_users=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_user_mappings;"`
    if [[ ${#foreign_users} >0 ]]; then
      echo -e "${GREEN}Foreign Users mappings. Dabatabase: ${UNDERLINE}$datname${NC}"
      $PG_BIN/psql --dbname=$datname -h $server -c "
      SELECT um.umid, um.srvid, um.srvname, a.rolname as umuser, um.usename, um.umoptions 
      FROM pg_user_mappings um
      LEFT JOIN pg_authid a ON um.umuser = a.oid;" | grep -v ' row)' | grep -v ' rows)'
    fi


    # Foreign tables list:
    foreign_tables=`$PG_BIN/psql -t --dbname=$datname -h $server -c "select * from pg_foreign_table;"`
    if [[ ${#foreign_tables} >0 ]]; then
      echo -e "${GREEN}Foreign tables list. Dabatabase: ${UNDERLINE}$datname${NC}"
      $PG_BIN/psql --dbname=$datname -h $server -c "
      SELECT n.nspname AS Schema,
      c.relname AS Table,
      s.srvname AS Server,
      CASE WHEN ftoptions IS NULL THEN '' ELSE '(' || pg_catalog.array_to_string(ARRAY(SELECT pg_catalog.quote_ident(option_name) || ' ' || pg_catalog.quote_literal(option_value) FROM pg_catalog.pg_options_to_table(ftoptions)), ', ') || ')' END AS FDW_options,
      d.description AS Description
      FROM pg_catalog.pg_foreign_table ft
      INNER JOIN pg_catalog.pg_class c ON c.oid = ft.ftrelid
      INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      INNER JOIN pg_catalog.pg_foreign_server s ON s.oid = ft.ftserver
      LEFT JOIN pg_catalog.pg_description d
      ON d.classoid = c.tableoid AND d.objoid = c.oid AND d.objsubid = 0
      ORDER BY 1, 2;" | grep -v ' row)' | grep -v ' rows)'
    fi


  done # for

  fi


  # ---------------------------------------------------------------------------------------------------------------------------------  
  # (Added)

  # Locks. Wait sessions
  locks_wait_sessions=`$PG_BIN/psql -t -h $server -c "
SELECT (clock_timestamp() - pg_stat_activity.xact_start) AS ts_age, pg_stat_activity.state, (clock_timestamp() - pg_stat_activity.query_start) as query_age, (clock_timestamp() - state_change) as change_age, pg_stat_activity.datname, pg_stat_activity.pid, pg_stat_activity.usename, coalesce(wait_event_type = 'Lock', 'f') waiting, pg_stat_activity.client_addr, pg_stat_activity.client_port, pg_stat_activity.query
FROM pg_stat_activity WHERE
((clock_timestamp() - pg_stat_activity.xact_start > '00:00:00.1'::interval) OR (clock_timestamp() - pg_stat_activity.query_start > '00:00:00.1'::interval and state = 'idle in transaction (aborted)'))
and pg_stat_activity.pid<>pg_backend_pid() ORDER BY coalesce(pg_stat_activity.xact_start, pg_stat_activity.query_start);"`
  if [[ ${#locks_wait_sessions} >0 ]]; then
    echo -e "${YELLOW}Locks. Wait sessions:${NC}"
    $PG_BIN/psql -h $server -c "
    SELECT (clock_timestamp() - pg_stat_activity.xact_start) AS ts_age, pg_stat_activity.state, (clock_timestamp() - pg_stat_activity.query_start) as query_age, (clock_timestamp() - state_change) as change_age, pg_stat_activity.datname, pg_stat_activity.pid, pg_stat_activity.usename, coalesce(wait_event_type = 'Lock', 'f') waiting, pg_stat_activity.client_addr, pg_stat_activity.client_port, pg_stat_activity.query
    FROM pg_stat_activity
    WHERE
    ((clock_timestamp() - pg_stat_activity.xact_start > '00:00:00.1'::interval) OR (clock_timestamp() - pg_stat_activity.query_start > '00:00:00.1'::interval and state = 'idle in transaction (aborted)'))
    and pg_stat_activity.pid<>pg_backend_pid()
    ORDER BY coalesce(pg_stat_activity.xact_start, pg_stat_activity.query_start);" | grep -v ' row)' | grep -v ' rows)'
  fi


  # Locks. Blocking tree
  locks_blocking_tree=`$PG_BIN/psql -t -h $server -c "
WITH RECURSIVE l AS (
  SELECT pid, locktype, granted,
    array_position(ARRAY['AccessShare','RowShare','RowExclusive','ShareUpdateExclusive','Share','ShareRowExclusive','Exclusive','AccessExclusive'], left(mode,-4)) m,
    ROW(locktype,database,relation,page,tuple,virtualxid,transactionid,classid,objid,objsubid) obj FROM pg_locks
), pairs AS (
  SELECT w.pid waiter, l.pid locker, l.obj, l.m
    FROM l w JOIN l ON l.obj IS NOT DISTINCT FROM w.obj AND l.locktype=w.locktype AND NOT l.pid=w.pid AND l.granted
   WHERE NOT w.granted
     AND NOT EXISTS ( SELECT FROM l i WHERE i.pid=l.pid AND i.locktype=l.locktype AND i.obj IS NOT DISTINCT FROM l.obj AND i.m > l.m )
), leads AS (
  SELECT o.locker, 1::int lvl, count(*) q, ARRAY[locker] track, false AS cycle FROM pairs o GROUP BY o.locker
  UNION ALL
  SELECT i.locker, leads.lvl+1, (SELECT count(*) FROM pairs q WHERE q.locker=i.locker), leads.track||i.locker, i.locker=ANY(leads.track)
    FROM pairs i, leads WHERE i.waiter=leads.locker AND NOT cycle
), tree AS (
  SELECT locker pid,locker dad,locker root,CASE WHEN cycle THEN track END dl, NULL::record obj,0 lvl,locker::text path,array_agg(locker) OVER () all_pids FROM leads o
   WHERE (cycle AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=ANY(o.track) AND (i.lvl>o.lvl OR i.q<o.q)))
      OR (NOT cycle AND NOT EXISTS (SELECT FROM pairs WHERE waiter=o.locker) AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=o.locker AND i.lvl<o.lvl))
  UNION ALL
  SELECT w.waiter pid,tree.pid,tree.root,CASE WHEN w.waiter=ANY(tree.dl) THEN tree.dl END,w.obj,tree.lvl+1,tree.path||'.'||w.waiter,all_pids || array_agg(w.waiter) OVER ()
    FROM tree JOIN pairs w ON tree.pid=w.locker AND NOT w.waiter = ANY ( all_pids )
)
SELECT (clock_timestamp() - a.xact_start)::interval(0) AS ts_age,
       (clock_timestamp() - a.state_change)::interval(0) AS change_age,
       a.datname,a.usename,a.client_addr,
       --w.obj wait_on_object,
       tree.pid,replace(a.state, 'idle in transaction', 'idletx') state,
       lvl,(SELECT count(*) FROM tree p WHERE p.path ~ ('^'||tree.path) AND NOT p.path=tree.path) blocked,
       CASE WHEN tree.pid=ANY(tree.dl) THEN '!>' ELSE repeat(' .', lvl) END||' '||trim(left(regexp_replace(a.query, E'\\s+', ' ', 'g'),100)) query
  FROM tree
  LEFT JOIN pairs w ON w.waiter=tree.pid AND w.locker=tree.dad
  JOIN pg_stat_activity a USING (pid)
  JOIN pg_stat_activity r ON r.pid=tree.root
 ORDER BY (now() - r.xact_start), path;"`
  if [[ ${#locks_blocking_tree} >0 ]]; then
    echo -e "${YELLOW}Locks. Blocking tree:${NC}"
    $PG_BIN/psql -h $server -c "
WITH RECURSIVE l AS (
  SELECT pid, locktype, granted,
    array_position(ARRAY['AccessShare','RowShare','RowExclusive','ShareUpdateExclusive','Share','ShareRowExclusive','Exclusive','AccessExclusive'], left(mode,-4)) m,
    ROW(locktype,database,relation,page,tuple,virtualxid,transactionid,classid,objid,objsubid) obj FROM pg_locks
), pairs AS (
  SELECT w.pid waiter, l.pid locker, l.obj, l.m
    FROM l w JOIN l ON l.obj IS NOT DISTINCT FROM w.obj AND l.locktype=w.locktype AND NOT l.pid=w.pid AND l.granted
   WHERE NOT w.granted
     AND NOT EXISTS ( SELECT FROM l i WHERE i.pid=l.pid AND i.locktype=l.locktype AND i.obj IS NOT DISTINCT FROM l.obj AND i.m > l.m )
), leads AS (
  SELECT o.locker, 1::int lvl, count(*) q, ARRAY[locker] track, false AS cycle FROM pairs o GROUP BY o.locker
  UNION ALL
  SELECT i.locker, leads.lvl+1, (SELECT count(*) FROM pairs q WHERE q.locker=i.locker), leads.track||i.locker, i.locker=ANY(leads.track)
    FROM pairs i, leads WHERE i.waiter=leads.locker AND NOT cycle
), tree AS (
  SELECT locker pid,locker dad,locker root,CASE WHEN cycle THEN track END dl, NULL::record obj,0 lvl,locker::text path,array_agg(locker) OVER () all_pids FROM leads o
   WHERE (cycle AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=ANY(o.track) AND (i.lvl>o.lvl OR i.q<o.q)))
      OR (NOT cycle AND NOT EXISTS (SELECT FROM pairs WHERE waiter=o.locker) AND NOT EXISTS (SELECT FROM leads i WHERE i.locker=o.locker AND i.lvl<o.lvl))
  UNION ALL
  SELECT w.waiter pid,tree.pid,tree.root,CASE WHEN w.waiter=ANY(tree.dl) THEN tree.dl END,w.obj,tree.lvl+1,tree.path||'.'||w.waiter,all_pids || array_agg(w.waiter) OVER ()
    FROM tree JOIN pairs w ON tree.pid=w.locker AND NOT w.waiter = ANY ( all_pids )
)
SELECT (clock_timestamp() - a.xact_start)::interval(0) AS ts_age,
       (clock_timestamp() - a.state_change)::interval(0) AS change_age,
       a.datname,a.usename,a.client_addr,
       --w.obj wait_on_object,
       tree.pid,replace(a.state, 'idle in transaction', 'idletx') state,
       lvl,(SELECT count(*) FROM tree p WHERE p.path ~ ('^'||tree.path) AND NOT p.path=tree.path) blocked,
       CASE WHEN tree.pid=ANY(tree.dl) THEN '!>' ELSE repeat(' .', lvl) END||' '||trim(left(regexp_replace(a.query, E'\\s+', ' ', 'g'),100)) query
  FROM tree
  LEFT JOIN pairs w ON w.waiter=tree.pid AND w.locker=tree.dad
  JOIN pg_stat_activity a USING (pid)
  JOIN pg_stat_activity r ON r.pid=tree.root
 ORDER BY (now() - r.xact_start), path;" | grep -v ' row)' | grep -v ' rows)'
  fi
  # Locks. Blocking tree



  # ---------------------------------------------------------------------------------------------------------------------------------  
  # (Added)

  # Long running queries (> 30 minutes)
  long_queries=`$PG_BIN/psql -t -h $server -c "SELECT pid FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '\30 minute\';"`
  if [[ ${#long_queries} >0 ]]; then
    echo -e "${YELLOW}Long running queries (> 30 minutes):${NC}"

    if [[ $POSTGRES_VER_GLOB -ge 10 ]]; then	# >= 10
      $PG_BIN/psql -h $server -c "SELECT datname, pid, TO_CHAR(now() - pg_stat_activity.query_start, 'HH24:MI:SS') AS duration, usename, application_name as app_name, client_addr, wait_event_type as wait_type, wait_event, backend_type, SUBSTRING(query, 1, 38) as query, state FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '\30 minute\';" | grep -v ' row)' | grep -v ' rows)'
    fi

    if [[ $POSTGRES_VER_GLOB -eq 9 ]]; then	# = 9
      $PG_BIN/psql -h $server -c "SELECT datname, pid, TO_CHAR(now() - pg_stat_activity.query_start, 'HH24:MI:SS') AS duration, usename, application_name as app_name, client_addr, wait_event_type as wait_type, wait_event, SUBSTRING(query, 1, 38) as query, state FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '\30 minute\';" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi



  # ---------------------------------------------------------------------------------------------------------------------------------  

  # PostgreSQL system process activity progress

  # PostgreSQL 9.6 and higher
  progress_vacuum=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_progress_vacuum;"`
  if [[ ${#progress_vacuum} >0 ]]; then
    echo -e "${YELLOW}VACUUM progress:${NC}"
    $PG_BIN/psql -h $server -c "select a.query, p.datname, p.phase, p.heap_blks_total, p.heap_blks_scanned, p.heap_blks_vacuumed, p.index_vacuum_count, p.max_dead_tuples, p.num_dead_tuples from pg_stat_progress_vacuum p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
  fi


  # PostgreSQL 12 and higher: pg_stat_progress_analyze, pg_stat_progress_basebackup
  if [[ $POSTGRES_VER_GLOB -ge 12 ]]; then	# >= 12

    progress_create_index=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_progress_create_index;"`
    if [[ ${#progress_create_index} >0 ]]; then
      echo -e "${YELLOW}CREATE INDEX progress:${NC}"
      $PG_BIN/psql -h $server -c "SELECT a.query, p.datname, p.command, p.phase, p.lockers_total, p.lockers_done, p.blocks_total, p.blocks_done, p.tuples_total, p.tuples_done FROM pg_stat_progress_create_index p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    fi

    progress_cluster=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_progress_cluster;"`
    if [[ ${#progress_cluster} >0 ]]; then
    echo -e "${YELLOW}VACUUM FULL or CLUSTER progress:${NC}"
    $PG_BIN/psql -h $server -c "select a.query, p.datname, p.command, p.phase, p.heap_tuples_scanned, p.heap_tuples_written, p.index_rebuild_count from pg_stat_progress_cluster p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    fi

  fi


  # PostgreSQL 13 and higher: pg_stat_progress_analyze, pg_stat_progress_basebackup
  if [[ $POSTGRES_VER_GLOB -ge 13 ]]; then	# >= 13

    progress_analyze=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_progress_analyze;"`
    if [[ ${#progress_analyze} >0 ]]; then
      echo -e "${YELLOW}ANALYZE progress:${NC}"
      $PG_BIN/psql -h $server -c "SELECT a.query, p.datname, p.phase, p.sample_blks_total, p.sample_blks_scanned, p.ext_stats_total, p.ext_stats_computed, p.child_tables_total, p.child_tables_done FROM pg_stat_progress_analyze p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
    fi

    progress_basebackup=`$PG_BIN/psql -t -h $server -c "select * from pg_stat_progress_basebackup;"`
    if [[ ${#progress_basebackup} >0 ]]; then
      echo -e "${YELLOW}PG_BASEBACKUP progress:${NC}"
      $PG_BIN/psql -h $server -c "SELECT a.query, p.pid, p.phase, p.backup_total, p.backup_streamed, p.tablespaces_total, p.tablespaces_streamed FROM pg_stat_progress_basebackup p, pg_stat_activity a WHERE p.pid = a.pid;" | grep -v ' row)' | grep -v ' rows)'
      PG_LOG_LINES=$((PG_LOG_LINES-5))
    fi

  fi


  # ---------------------------------------------------------------------------------------------------------------------------------  


done # Servers cycle

