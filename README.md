## pg_dba_scripts - PostgreSQL DBA scripts

A collection of scripts for PostgreSQL database administrator (DBA). Tested on PostgreSQL 12-13 under CentOS 7.

- [scripts/pg_database_activity.sh](#pg_database_activity). PostgreSQL monitoring script, all information is displayed on one page. Displays PostgreSQL version and status (Master / Replica), hostname and IP address, CPU and Disks load. It also displays memory consumption by PostgreSQL processes, statistics on databases, waits and locks, archive and replication statuses. When activities occur in PostgreSQL, the progress of operations is displayed: vacuum, vacuum full or cluster, index creation, analyze, pg_basebackup. At the end, the last entries of the PostgreSQL log file are displayed. For ease of perception, information is displayed in color.
- [scripts/pg_database_activity_refresh.sh](#). Fast refresh of the **pg_database_activity.sh** script every 5 seconds.
- [scripts/pg_database_hugepages.sh](#pg_database_hugepages). Shows current usage of HugePages and recommended settings for PostgreSQL.
- [scripts/pg_database_logs.sh](#pg_database_logs). Shows the PostgreSQL log file with auto-update. The log file is selected automatically.
- [pg_database_reload_conf.sh](#pg_database_reload_conf). Reloads PostgreSQL configuration files (postgresql.conf, postgresql.auto.conf, pg_hba.conf, pg_ident.conf), displays records related to changes from the log file. If the changed parameter requires a restart, its characteristics are displayed. Operation confirmation is required.
- [scripts/pg_database_start.sh](#pg_database_start). Start PostgreSQL, confirmation is required.
- [scripts/pg_database_stop.sh](#pg_database_stop). Stop PostgreSQL, confirmation is required.
- [scripts/pg_database_status.sh](#pg_database_status). PostgreSQL status. Additionally, PostgreSQL processes and replication services are displayed.
- [scripts/settings.txt](#Setup). General settings for all scripts. Required before starting work.


## Installation

Copy the scripts to a separate postgres user directory (for example **~scripts/**) and grant the necessary execution rights:
```
$ chmod 600 *.sh
```


## Setup

Modify file **settings.txt**. Uncomment and correct the entries for your current PostgreSQL version.
```
# PostgreSQL 12
#PG_BIN=/usr/pgsql-12/bin			# Executables directory
#PG_DATA=/var/lib/pgsql/12/data			# Main data directory
#PG_ARC=/var/lib/pgsql/12/archive		# Archive logs directory
#PG_LOG_DIR=/var/lib/pgsql/12/data/log		# Directory for log files

# PostgreSQL 13
#PG_BIN=/usr/pgsql-13/bin			# Executables directory
#PG_DATA=/var/lib/pgsql/13/data			# Main data directory
#PG_ARC=/var/lib/pgsql/13/archive		# Archive logs directory
#PG_LOG_DIR=/var/lib/pgsql/13/data/log		# Directory for log files
```

---
### pg_database_activity

PostgreSQL monitoring script, all information is displayed on one page. Displays PostgreSQL version and status (Master / Replica), hostname and IP address, CPU and Disks load. It also displays memory consumption by PostgreSQL processes, statistics on databases, waits and locks, archive and replication statuses. When activities occur in PostgreSQL, the progress of operations is displayed: vacuum, vacuum full or cluster, index creation, analyze, pg_basebackup. At the end, the last entries of the PostgreSQL log file are displayed. For ease of perception, information is displayed in color.

**Setup:**

Change the value of the PG_LOG_LINES parameter in the script, which is responsible for displaying the number of last lines of the PosgtreSQL log file.
```
PG_LOG_LINES=15		# PostgreSQL log lines to show. 0 - disable output
```


---
### pg_database_hugepages

Shows current usage of HugePages and recommended settings for PostgreSQL.


---
### pg_database_logs

Shows the PosgreSQL log file with auto-update. The log file is selected automatically.


---
### pg_database_reload_conf

Reloads PostgreSQL configuration files (postgresql.conf, postgresql.auto.conf, pg_hba.conf, pg_ident.conf), displays records related to changes from the log file. If the changed parameter requires a restart, its characteristics are displayed. Operation confirmation is required.


---
### pg_database_start

Start PostgreSQL, confirmation is required.


---
### pg_database_stop

Stop PostgreSQL, confirmation is required.


---
### pg_database_status

PostgreSQL status. Additionally, PostgreSQL processes and replication services are displayed.

