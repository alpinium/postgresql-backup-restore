# postgresql-backup-restore

Set of scripts to back up and restore PostgreSQL databases, with optional splitting of the schema and the data into separate files, and optional backing up of the globals (roles, tablespaces). The backups are compressed with zstd. The scripts are prepared to be run in a Docker container, which can be scheduled to run automatically with cron.

### docker-compose.yaml
```
services:
  backup:
    restart: unless-stopped
    image: alpiniumtech/postgresql-backup-restore:18-trixie
    oom_score_adj: 1000
    container_name: backup
    environment:
      CRON_JOB_DATABASE_A_DELETE_BACKUPS: "00 03 * * * /data/backup_database_a; /usr/local/bin/delete_old_backups.sh --retention-days 30"
      CRON_JOB_DATABASE_A_DELETE_LOGS: "05 03 * * * /data/backup_database_a; && /usr/local/bin/delete_old_logs.sh --retention-days 30"
      CRON_JOB_DATABASE_A_GLOBALS: "10 03 * * * cd /data/backup_database_a; PGPASSWORD=${DATABASE_A_DB_PASSWORD} /usr/local/bin/backup.sh --host database_a --username ${DATABASE_A_DB_USER} --globals"
      CRON_JOB_DATABASE_A_DATABASES: "15 03 * * * cd /data/backup_database_a; PGPASSWORD=${DATABASE_A_DB_PASSWORD} /usr/local/bin/backup.sh --host database_a --username ${DATABASE_A_DB_USER}"
      CRON_JOB_DATABASE_B_DELETE_BACKUPS: "00 04 * * * cd /data/backup_database_b; /usr/local/bin/delete_old_backups.sh --retention-days 30"
      CRON_JOB_DATABASE_B_DELETE_LOGS: "05 04 * * * cd /data/backup_database_b; /usr/local/bin/delete_old_logs.sh --retention-days 30"
      CRON_JOB_DATABASE_B_GLOBALS: "10 04 * * * cd /data/backup_database_b; PGPASSWORD=${DATABASE_B_DB_PASSWORD} /usr/local/bin/backup.sh --host database_b --username ${DATABASE_B_DB_USER} --globals"
      CRON_JOB_DATABASE_B_DATABASES: "15 04 * * * cd /data/backup_database_b; PGPASSWORD=${DATABASE_B_DB_PASSWORD} /usr/local/bin/backup.sh --host database_b --username ${DATABASE_B_DB_USER}"
    volumes:
      - ./backups/database_a:/data/backup_database_a:rw
      - ./backups/database_b:/data/backup_database_b:rw
```

### backup.sh
```
Backs up the databases, one after another, to separate plain SQL files
compressed with zstd, in the current directory (time is in UTC):
  <database>_YYYYMMDDTHHMMSS.sql.zst
  <database>_scheme_YYYYMMDDTHHMMSS.sql.zst + <database>_data_YYYYMMDDTHHMMSS.sql.zst (--split)
  __globals_YYYYMMDDTHHMMSS.sql.zst (--globals)

Usage: ./backup.sh -h hostname [-p port] [-U username] [-d dbname] [--split] [--globals]
  -h, --host hostname      server host (required)
  -p, --port port          server port (default: 5432)
  -U, --username username  user name (default: postgres)
  -d, --dbname dbname      name of the database to back up (default: all databases)
  --split                  back up the schema and the data of each database to separate files
  --globals                back up only the globals (roles, tablespaces), nothing else
  The password is taken by libpq from PGPASSWORD (or ~/.pgpass).
```

### restore.sh
```
Restores a backup created by backup.sh:
  <database>_YYYYMMDDTHHMMSS.sql.zst          the database
  <database>_scheme_YYYYMMDDTHHMMSS.sql.zst   the database (--split), given as the first --file,
  <database>_data_YYYYMMDDTHHMMSS.sql.zst     together with its data, given as the second --file
  __globals_YYYYMMDDTHHMMSS.sql.zst           the globals (roles, tablespaces)

The kind of the backup is recognized from the file name. The backup files are tested first.
When the database given by --dbname already exists, it is dropped (with its connections terminated),
after the user confirms it by typing "yes". After the restore, VACUUM ANALYZE is run on the database.
The output is also written to restore_YYYYMMDDTHHMMSS.log in the current directory (time is in UTC).

Usage: ./restore.sh -h hostname [-p port] [-U username] [-d dbname] -f backup_file [-f data_file]
  -h, --host hostname      server host (required)
  -p, --port port          server port (default: 5432)
  -U, --username username  user name (default: postgres)
  -d, --dbname dbname      name of the restored database (required; must be omitted for the globals)
  -f, --file backup_file   backup file to restore (required); for a split backup given twice,
                           first the _scheme_ file, then the _data_ file
  The password is taken by libpq from PGPASSWORD (or ~/.pgpass).
```

### delete_old_backups.sh
```
Deletes the backups created by backup.sh in the current directory whose timestamp
in the file name (UTC) is older than the given number of days:
  <database>_YYYYMMDDTHHMMSS.sql.zst
  <database>_scheme_YYYYMMDDTHHMMSS.sql.zst
  <database>_data_YYYYMMDDTHHMMSS.sql.zst
  __globals_YYYYMMDDTHHMMSS.sql.zst (globals)
Files whose name does not match these patterns are left untouched.

Usage: ./delete_old_backups.sh [--retention-days days] [--dbname dbname]
  --retention-days days    keep backups younger than this many days (default: 30)
  --dbname dbname          delete only the backups of this database
                           (default: the backups of all databases and the globals)
```

### delete_old_logs.sh
```
Deletes the backup and restore logs (backup_YYYYMMDDTHHMMSS.log, restore_YYYYMMDDTHHMMSS.log) in the current directory
whose timestamp in the file name (UTC) is older than the given number of days.
Files whose name does not match this pattern are left untouched.

Usage: ./delete_old_logs.sh [--retention-days days]
  --retention-days days    keep logs younger than this many days (default: 30)
```
