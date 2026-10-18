# BookMyShow-scale ticketing: P1 & P2
MySQL 8.0+ schema, seed data, P2 query, and concurrency statements.

    mysql < sql/01_schema.sql
    mysql < sql/02_seed.sql
    mysql < sql/03_p2_query.sql

- `sql/04_concurrency.sql`: hold / confirm / idempotent webhook / expiry sweeper
- `race_test.py`: 50 threads race for one seat; exactly one wins (needs `pip install pymysql`)
- `docs/BookMyShow_P1_P2.pdf`: the submission doc
