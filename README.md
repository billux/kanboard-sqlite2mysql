# Kanboard - SQLite2PostgreSQL

This is a fork of [oliviermaridat/kanboard-sqlite2mysql](https://github.com/oliviermaridat/kanboard-sqlite2mysql) with additional changes to make the resulting dump compatible with PostgreSQL.

For usage, please refer to the [initial README](https://github.com/oliviermaridat/kanboard-sqlite2mysql/blob/master/README.md).

The script was used to migrate SQLite schema version 125 to PostgreSQL 13 schema version 115.

After importing the dump, sequences aren't aware of their corresponding IDs in tables. To reset them to the latest used ID of their tables, run this SQL:
```
$ psql <connection param> -Atq -f reset-sequences.sql |psql <connection param>
```
