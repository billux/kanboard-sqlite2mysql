#!/usr/bin/env bash

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly ARGS="$@"

usage()
{
	cat <<- EOF
	usage: $PROGNAME <Kanboard instance physical path> [ <PostgreSQL DB name> -h <PostgreSQL DB host> -u <PostgreSQL DB user> -p ] [ --help ]

	 -p, --password		PostgreSQL database password. If password is not given it's asked from the tty.
	 -h, --host		PostgreSQL database host
	 -u, --user		PostgreSQL database user for login
	 -o, --output		Path to the output SQL dump compatible with PostgreSQL
	 -v, --verbose		Enable more verbosity
	 -H, --help		Display this help
	 -V, --version		Display the Kanboard SQLite2PostgreSQL version

	Example:
	 $PROGNAME /usr/local/share/www/kanboard -o db-postgresql.sql
	 $PROGNAME /usr/local/share/www/kanboard kanboard -u root --password root
	EOF
}

version()
{
	cat <<- EOF
	Kanboard SQLite2PostgreSQL 0.0.1
	Migrate your SQLite Kanboard database to PostgreSQL in one go! By Romain
    Forked from SQLite2MySQL where all major work have been done by Olivier.
	EOF
}

cmdline()
{
  KANBOARD_PATH=
  DB_HOSTNAME=
  DB_USERNAME=
  DB_PASSWORD=
  DB_NAME=
  OUTPUT_FILE=db-postgresql.sql
  IS_VERBOSE=0
  if [ "$#" -lt "1" ]; then
    echo 'error: missing arguments'
    usage
    exit -1
  fi
  while [ "$1" != "" ]; do
  case $1 in
    -o | --output )
      shift
      OUTPUT_FILE=$1
      shift
      ;;
    -h | --host )
      shift
      DB_HOSTNAME=$1
      shift
      ;;
    -u | --user )
      shift
      DB_USERNAME=$1
      shift
      ;;
    -p )
      shift
      echo 'Enter password: '
      read DB_PASSWORD
      ;;
    --password )
      shift
      DB_PASSWORD=$1
      shift
      ;;
    -v | --verbose )
      shift
      IS_VERBOSE=1
      ;;
    -H | --help )
      usage
      exit 0
      ;;
    -V | --version )
      version
      exit 0
      ;;
    *)
      if [ "${KANBOARD_PATH}" == ""  ]; then
        if [ ! -d "$1" ]; then
          echo "error: unknown path '$1'"
          usage
          exit -1
        fi
        KANBOARD_PATH=$1
        shift
      elif [ "$DB_NAME" == ""  ]; then
        DB_NAME=$1
        shift
      else
        echo "error: unknwon argument '$1'"
        usage
        exit -1
      fi
      ;;
  esac
  done
  
  if [ ! "${DB_NAME}" == "" ]; then
    if [ "${DB_USERNAME}" == "" ]; then
        DB_USERNAME=root
    fi
    if [ "${DB_HOSTNAME}" == "" ]; then
        DB_HOSTNAME=localhost
    fi
  fi
  return 0
}

# List tables names of a SQLite database
# 'sqlite3 db.sqlite .tables' already return tables names but only in column mode...
# * @param Database file
sqlite_tables()
{
    local sqliteDbFile=$1
    sqlite3 ${sqliteDbFile} .schema \
        | sed -e '/[^C(]$/d' -e '/^\s\+($/d' -e 's/CREATE TABLE \([a-z_]*\).*/\1/' -e '/^$/d'
}

# List column names of a SQLite table
# * @param Database file
# * @param Table name
sqlite_columns()
{
    local sqliteDbFile=$1
    local table=$2
    sqlite3 -csv -header ${sqliteDbFile} "select * from ${table};" \
        | head -n 1 \
        | sed -e 's/,/","/g' -e 's/^/"/' -e 's/$/"/'
}

# Generate "INSERT INTO" queries to dump data of an SQLite table
# * @param Database file
# * @param Table name
sqlite_dump_table_data()
{
    local sqliteDbFile=$1
    local table=$2
    local columns=`sqlite_columns ${sqliteDbFile} ${table}`
    
    echo -e ".mode insert ${table}\nselect * from ${table};" \
        | sqlite3 ${sqliteDbFile} \
        | sed -e "s/INSERT INTO \([a-z_\"]*\)/INSERT INTO \1 (${columns})/" -e 's/char(\([0-9]\+\))/CHR(\1)/g'
}

# If verbose, displays version of the schema found in the SQLite file. Beware this version is different from PostgreSQL schema versions
sqlite_dump_schemaversion()
{
    local sqliteDbFile=$1
    if [ "1" == "${IS_VERBOSE}" ]; then
        echo "# Found schema version `sqlite3 ${sqliteDbFile} 'PRAGMA user_version'` for SQLite"
    fi
}

# Generate "INSERT INTO" queries to dump data of a SQLite database
# * @param Database file
sqlite_dump_data()
{
    local sqliteDbFile=$1
    local prioritizedTables='plugin_schema_versions projects columns links groups users tasks task_has_links subtasks comments actions'
    for t in $prioritizedTables; do
        # Please do not ask why: this TRUNCATE is already done elsewhere, but this table "plugin_schema_versions" seems to be refillld I don't know where... This fix the issue
        if [ "plugin_schema_versions" == "${t}" ]; then
            echo 'TRUNCATE TABLE plugin_schema_versions;'
        fi
        sqlite_dump_table_data ${sqliteDbFile} ${t}
    done
    for t in $(sqlite_tables ${sqliteDbFile} | sed -e '/^plugin_schema_versions$/d' -e '/^projects$/d' -e '/^columns$/d' -e '/^links$/d' -e '/^groups$/d' -e '/^users$/d' -e '/^tasks$/d' -e '/^task_has_links$/d' -e '/^subtasks$/d' -e '/^comments$/d' -e '/^actions$/d'); do
        sqlite_dump_table_data ${sqliteDbFile} ${t}
    done
}

createPostgresqlDump()
{
    local sqliteDbFile=$1
    
    cat <<EOT >> ${OUTPUT_FILE}
ALTER TABLE task_has_files ALTER is_image DROP DEFAULT;
ALTER TABLE task_has_files ALTER is_image TYPE int USING 0;
ALTER TABLE task_has_files ALTER is_image SET DEFAULT 0;
ALTER TABLE tasks ALTER is_active DROP DEFAULT;
ALTER TABLE tasks ALTER is_active TYPE int USING 0;
ALTER TABLE tasks ALTER is_active SET DEFAULT 1;
ALTER TABLE projects ALTER is_active DROP DEFAULT;
ALTER TABLE projects ALTER is_active TYPE int USING 0;
ALTER TABLE projects ALTER is_active SET DEFAULT 1;
ALTER TABLE users ALTER is_ldap_user DROP DEFAULT;
ALTER TABLE users ALTER is_ldap_user TYPE int USING 0;
ALTER TABLE users ALTER is_ldap_user SET DEFAULT 0;
ALTER TABLE users ALTER notifications_enabled DROP DEFAULT;
ALTER TABLE users ALTER notifications_enabled TYPE int USING 0;
ALTER TABLE users ALTER notifications_enabled SET DEFAULT 0;
ALTER TABLE projects ALTER is_public DROP DEFAULT;
ALTER TABLE projects ALTER is_public TYPE int USING 0;
ALTER TABLE projects ALTER is_public SET DEFAULT 0;
ALTER TABLE projects ALTER is_private DROP DEFAULT;
ALTER TABLE projects ALTER is_private TYPE int USING 0;
ALTER TABLE projects ALTER is_private SET DEFAULT 0;
ALTER TABLE swimlanes ALTER is_active DROP DEFAULT;
ALTER TABLE swimlanes ALTER is_active TYPE int USING 0;
ALTER TABLE swimlanes ALTER is_active SET DEFAULT 1;
ALTER TABLE users ALTER disable_login_form DROP DEFAULT;
ALTER TABLE users ALTER disable_login_form TYPE int USING 0;
ALTER TABLE users ALTER disable_login_form SET DEFAULT 0;
ALTER TABLE users ALTER twofactor_activated DROP DEFAULT;
ALTER TABLE users ALTER twofactor_activated TYPE int USING 0;
ALTER TABLE users ALTER twofactor_activated SET DEFAULT 0;
ALTER TABLE custom_filters ALTER is_shared DROP DEFAULT;
ALTER TABLE custom_filters ALTER is_shared TYPE int USING 0;
ALTER TABLE custom_filters ALTER is_shared SET DEFAULT 0;
ALTER TABLE custom_filters ALTER append DROP DEFAULT;
ALTER TABLE custom_filters ALTER append TYPE int USING 0;
ALTER TABLE custom_filters ALTER append SET DEFAULT 0;
ALTER TABLE password_reset ALTER is_active DROP DEFAULT;
ALTER TABLE password_reset ALTER is_active TYPE int USING 0;
ALTER TABLE users ALTER is_active DROP DEFAULT;
ALTER TABLE users ALTER is_active TYPE int USING 0;
ALTER TABLE users ALTER is_active SET DEFAULT 1;
ALTER TABLE project_has_files ALTER is_image DROP DEFAULT;
ALTER TABLE project_has_files ALTER is_image TYPE int USING 0;
ALTER TABLE project_has_files ALTER is_image SET DEFAULT 0;
ALTER TABLE columns ALTER hide_in_dashboard DROP DEFAULT;
ALTER TABLE columns ALTER hide_in_dashboard TYPE int USING 0;
ALTER TABLE columns ALTER hide_in_dashboard SET DEFAULT 0;
ALTER TABLE column_has_move_restrictions ALTER only_assigned DROP DEFAULT;
ALTER TABLE column_has_move_restrictions ALTER only_assigned TYPE int USING 0;
ALTER TABLE column_has_move_restrictions ALTER only_assigned SET DEFAULT 0;
ALTER TABLE projects ALTER per_swimlane_task_limits DROP DEFAULT;
ALTER TABLE projects ALTER per_swimlane_task_limits TYPE int USING 0;
ALTER TABLE projects ALTER per_swimlane_task_limits SET DEFAULT 0;

ALTER TABLE projects ALTER enable_global_tags DROP DEFAULT;
ALTER TABLE projects ALTER enable_global_tags TYPE int USING 0;
ALTER TABLE projects ALTER enable_global_tags SET DEFAULT 1;
ALTER TABLE users ADD COLUMN is_admin INT DEFAULT 0;
ALTER TABLE users ADD COLUMN default_project_id INT DEFAULT 0;
ALTER TABLE users ADD COLUMN is_project_admin INT DEFAULT 0;
ALTER TABLE tasks ADD COLUMN estimate_duration VARCHAR(255);
ALTER TABLE tasks ADD COLUMN actual_duration VARCHAR(255);
ALTER TABLE project_has_users ADD COLUMN id INT DEFAULT 0;
ALTER TABLE project_has_users ADD COLUMN is_owner INT DEFAULT 0;
ALTER TABLE projects ADD COLUMN is_everybody_allowed SMALLINT DEFAULT 0;
ALTER TABLE projects ADD COLUMN default_swimlane VARCHAR(200) DEFAULT 'Default swimlane';
ALTER TABLE projects ADD COLUMN show_default_swimlane INT DEFAULT 1;
ALTER TABLE tasks DROP CONSTRAINT tasks_swimlane_id_fkey;

TRUNCATE TABLE settings CASCADE;
TRUNCATE TABLE users CASCADE;
TRUNCATE TABLE links CASCADE;
TRUNCATE TABLE plugin_schema_versions CASCADE;
EOT
    
    echo 'ALTER TABLE "tasks" ALTER "column_id" TYPE INT;' >> ${OUTPUT_FILE}

    sqlite_dump_data ${sqliteDbFile} >> ${OUTPUT_FILE}

    cat <<EOT >> ${OUTPUT_FILE}
ALTER TABLE users DROP COLUMN is_admin;
ALTER TABLE users DROP COLUMN default_project_id;
ALTER TABLE users DROP COLUMN is_project_admin;
ALTER TABLE tasks DROP COLUMN estimate_duration;
ALTER TABLE tasks DROP COLUMN actual_duration;
ALTER TABLE project_has_users DROP COLUMN id;
ALTER TABLE project_has_users DROP COLUMN is_owner;
ALTER TABLE projects DROP COLUMN is_everybody_allowed;
ALTER TABLE projects DROP COLUMN default_swimlane;
ALTER TABLE projects DROP COLUMN show_default_swimlane;

ALTER TABLE task_has_files ALTER is_image DROP DEFAULT;
ALTER TABLE task_has_files ALTER is_image TYPE bool USING CASE WHEN is_image=0 THEN FALSE ELSE TRUE END;
ALTER TABLE task_has_files ALTER is_image SET DEFAULT FALSE;
ALTER TABLE tasks ALTER is_active DROP DEFAULT;
ALTER TABLE tasks ALTER is_active TYPE bool USING CASE WHEN is_active=0 THEN FALSE ELSE TRUE END;
ALTER TABLE tasks ALTER is_active SET DEFAULT TRUE;
ALTER TABLE projects ALTER is_active DROP DEFAULT;
ALTER TABLE projects ALTER is_active TYPE bool USING CASE WHEN is_active=0 THEN FALSE ELSE TRUE END;
ALTER TABLE projects ALTER is_active SET DEFAULT TRUE;
ALTER TABLE users ALTER is_ldap_user DROP DEFAULT;
ALTER TABLE users ALTER is_ldap_user TYPE bool USING CASE WHEN is_ldap_user=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER is_ldap_user SET DEFAULT FALSE;
ALTER TABLE users ALTER notifications_enabled DROP DEFAULT;
ALTER TABLE users ALTER notifications_enabled TYPE bool USING CASE WHEN notifications_enabled=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER notifications_enabled SET DEFAULT FALSE;
ALTER TABLE projects ALTER is_public DROP DEFAULT;
ALTER TABLE projects ALTER is_public TYPE bool USING CASE WHEN is_public=0 THEN FALSE ELSE TRUE END;
ALTER TABLE projects ALTER is_public SET DEFAULT FALSE;
ALTER TABLE projects ALTER is_private DROP DEFAULT;
ALTER TABLE projects ALTER is_private TYPE bool USING CASE WHEN is_private=0 THEN FALSE ELSE TRUE END;
ALTER TABLE projects ALTER is_private SET DEFAULT FALSE;
ALTER TABLE swimlanes ALTER is_active DROP DEFAULT;
ALTER TABLE swimlanes ALTER is_active TYPE bool USING CASE WHEN is_active=0 THEN FALSE ELSE TRUE END;
ALTER TABLE swimlanes ALTER is_active SET DEFAULT TRUE;
ALTER TABLE users ALTER disable_login_form DROP DEFAULT;
ALTER TABLE users ALTER disable_login_form TYPE bool USING CASE WHEN disable_login_form=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER disable_login_form SET DEFAULT FALSE;
ALTER TABLE users ALTER twofactor_activated DROP DEFAULT;
ALTER TABLE users ALTER twofactor_activated TYPE bool USING CASE WHEN twofactor_activated=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER twofactor_activated SET DEFAULT FALSE;
ALTER TABLE custom_filters ALTER is_shared DROP DEFAULT;
ALTER TABLE custom_filters ALTER is_shared TYPE bool USING CASE WHEN is_shared=0 THEN FALSE ELSE TRUE END;
ALTER TABLE custom_filters ALTER is_shared SET DEFAULT FALSE;
ALTER TABLE custom_filters ALTER append DROP DEFAULT;
ALTER TABLE custom_filters ALTER append TYPE bool USING CASE WHEN append=0 THEN FALSE ELSE TRUE END;
ALTER TABLE custom_filters ALTER append SET DEFAULT FALSE;
ALTER TABLE password_reset ALTER is_active DROP DEFAULT;
ALTER TABLE password_reset ALTER is_active TYPE bool USING CASE WHEN is_active=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER is_active DROP DEFAULT;
ALTER TABLE users ALTER is_active TYPE bool USING CASE WHEN is_active=0 THEN FALSE ELSE TRUE END;
ALTER TABLE users ALTER is_active SET DEFAULT TRUE;
ALTER TABLE project_has_files ALTER is_image DROP DEFAULT;
ALTER TABLE project_has_files ALTER is_image TYPE bool USING CASE WHEN is_image=0 THEN FALSE ELSE TRUE END;
ALTER TABLE project_has_files ALTER is_image SET DEFAULT FALSE;
ALTER TABLE columns ALTER hide_in_dashboard DROP DEFAULT;
ALTER TABLE columns ALTER hide_in_dashboard TYPE bool USING CASE WHEN hide_in_dashboard=0 THEN FALSE ELSE TRUE END;
ALTER TABLE columns ALTER hide_in_dashboard SET DEFAULT FALSE;
ALTER TABLE column_has_move_restrictions ALTER only_assigned DROP DEFAULT;
ALTER TABLE column_has_move_restrictions ALTER only_assigned TYPE bool USING CASE WHEN only_assigned=0 THEN FALSE ELSE TRUE END;
ALTER TABLE column_has_move_restrictions ALTER only_assigned SET DEFAULT FALSE;
ALTER TABLE projects ALTER per_swimlane_task_limits DROP DEFAULT;
ALTER TABLE projects ALTER per_swimlane_task_limits TYPE bool USING CASE WHEN per_swimlane_task_limits=0 THEN FALSE ELSE TRUE END;
ALTER TABLE projects ALTER per_swimlane_task_limits SET DEFAULT FALSE;
ALTER TABLE projects ALTER enable_global_tags DROP DEFAULT;
ALTER TABLE projects ALTER enable_global_tags TYPE bool USING CASE WHEN enable_global_tags=0 THEN FALSE ELSE TRUE END;
ALTER TABLE projects ALTER enable_global_tags SET DEFAULT TRUE;
EOT

    #echo 'ALTER TABLE `tasks` CHANGE `column_id` `column_id` INT( 11 ) NOT NULL;' >> ${OUTPUT_FILE}

    echo 'ALTER TABLE tasks ADD CONSTRAINT tasks_swimlane_id_fkey FOREIGN KEY (swimlane_id) REFERENCES swimlanes(id) ON DELETE CASCADE;' >> ${OUTPUT_FILE}

    # For PostgreSQL, we need to double the anti-slash (\\ instead of \)
    # But we need to take care of Windows URL (e.g. C:\test\) in the JSON of project_activities (e.g. C:\test\" shall not become C:\\test\\" this will break the json...). Windows URL are transformed into Linux URL for this reason
    cat ${OUTPUT_FILE} \
        | sed -e 's/\\\\"/"/g' \
        | sed -e 's/\\\\/\//g' \
        | sed -e 's/\\"/##"/g' \
        | sed -e 's/\\u\([[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]]\)/##u\1/g' \
        | sed -e 's/\\/\//g' \
        | sed -e 's/##"/\\\\"/g' \
        | sed -e 's/##u\([[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]]\)/\\u\1/g' \
        | sed -e 's/\/Kanboard\/Action\//\\\\Kanboard\\\\Action\\\\/g' \
        | sed -e 's/\/r\/n/\\\\n/g' \
        | sed -e 's/\/\//\//g' \
        > db.postgresql
    mv db.postgresql ${OUTPUT_FILE}
}

generatePostgresqlSchema()
{
    mv ${KANBOARD_PATH}/config.php ${KANBOARD_PATH}/config_tmp.php
    export DATABASE_URL="postgresql://${DB_USERNAME}:${DB_PASSWORD}@${DB_HOSTNAME}/${DB_NAME}"
    php ${KANBOARD_PATH}/app/common.php
    mv ${KANBOARD_PATH}/config_tmp.php ${KANBOARD_PATH}/config.php
}

fillPostgresqlDb()
{
    local verbosity=
    if [ "1" != "${IS_VERBOSE}" ]; then
        verbosity="--quiet"
    fi
    PGPASSWORD=${DB_PASSWORD} psql ${verbosity} -h ${DB_HOSTNAME} -U ${DB_USERNAME} ${DB_NAME} \
        < ${OUTPUT_FILE}
}

main()
{
    cmdline $ARGS
    local sqliteDbFile=${KANBOARD_PATH}/data/db.sqlite

    sqlite_dump_schemaversion ${sqliteDbFile}
    
    echo '# Create PostgreSQL data dump from SQLite database'
    createPostgresqlDump ${sqliteDbFile} \
        && (echo "done" ; echo "check ${OUTPUT_FILE}") \
        || (echo 'FAILLURE' ; exit -1)

    if [ ! "${DB_NAME}" == "" ]; then
        echo '# Generate schema in the PostgreSQL database using Kanboard'
        generatePostgresqlSchema \
            && echo "done" \
            || (echo 'FAILLURE' ; exit -1)

        echo '# Fill the PostgreSQL database with the SQLite database data'
        fillPostgresqlDb \
            && echo "done" \
            || (echo 'FAILLURE' ; exit -1)
    fi
}
main


