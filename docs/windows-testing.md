# pglogical Windows Testing Guide

## Setup

```sql
-- Create databases
CREATE DATABASE provider_db;
CREATE DATABASE subscriber_db;
```

## Provider Setup

```sql
-- Connect to provider_db
\c provider_db

-- Install extension
CREATE EXTENSION pglogical;

-- Create node
SELECT pglogical.create_node(
    node_name := 'provider',
    dsn := 'host=localhost port=5432 dbname=provider_db user=postgres password=postgres'
);

-- Create test table
CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- Add table to default replication set
SELECT pglogical.replication_set_add_table('default', 'test_data', true);

-- Insert test data
INSERT INTO test_data (name) VALUES ('row1'), ('row2'), ('row3');
```

## Subscriber Setup

```sql
-- Connect to subscriber_db
\c subscriber_db

-- Install extension
CREATE EXTENSION pglogical;

-- Create node
SELECT pglogical.create_node(
    node_name := 'subscriber',
    dsn := 'host=localhost port=5432 dbname=subscriber_db user=postgres password=postgres'
);

-- Create matching table structure
CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- Create subscription
SELECT pglogical.create_subscription(
    subscription_name := 'test_subscription',
    provider_dsn := 'host=localhost port=5432 dbname=provider_db user=postgres password=postgres',
    synchronize_data := true
);
```

## Verify Replication

```sql
-- On subscriber_db: check data was synchronized
SELECT * FROM test_data;

-- On provider_db: insert new row
INSERT INTO test_data (name) VALUES ('row4');

-- On subscriber_db: verify new row appears
SELECT * FROM test_data;
```

## Check Status

```sql
-- View subscription status
SELECT * FROM pglogical.show_subscription_status();

-- View replication sets
SELECT * FROM pglogical.replication_set;
```

## Cleanup

```sql
-- On subscriber_db
SELECT pglogical.drop_subscription('test_subscription');
SELECT pglogical.drop_node('subscriber');

-- On provider_db
SELECT pglogical.drop_node('provider');

-- Then drop databases
DROP DATABASE subscriber_db;
DROP DATABASE provider_db;
```
