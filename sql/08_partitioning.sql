-- =============================================================================
-- Checkpoint 4 (CP4): Declarative Table Partitioning DDL & Partition Pruning
-- Database: Amazon Online Shopping Database (PostgreSQL 16+)
-- Team: T0063 · Section C
-- Author: Anish Choudhary (GitHub: @Anish-choudharyy)
-- File: sql/08_partitioning.sql
-- =============================================================================
--
-- TECHNICAL ARCHITECTURE & JUSTIFICATION:
-- In an enterprise e-commerce platform at Amazon scale, the `orders` relation is
-- the single fastest-growing entity, accumulating hundreds of millions of rows
-- annually. While secondary B-tree indexes (designed in sql/05_indexes.sql)
-- accelerate single-row and narrow-range lookups, index sizes eventually outgrow
-- PostgreSQL's `shared_buffers` working memory, leading to heavy random disk I/O,
-- index bloat, and prolonged autovacuum cycles.
--
-- Declarative RANGE partitioning by `ordered_at` addresses these bottlenecks by:
-- 1. Partition Pruning: Queries bounded by time intervals (e.g. June 2026 reports,
--    daily GMV, monthly seller reconciliations) eliminate 85%–95% of table blocks
--    during query planning and execution, reading only relevant partition slices.
-- 2. Maintenance Isolation: VACUUM, REINDEX, and CLUSTER operations execute on
--    individual quarterly slices without locking or stressing the full table.
-- 3. Data Lifecycle & Archival: Aging historical data (e.g., orders > 5 years old)
--    can be detached instantly via `ALTER TABLE ... DETACH PARTITION` and moved to
--    cold columnar storage or dropped with zero table-wide redo log overhead.
--
-- POSTGRESQL PRIMARY KEY CONSTRAINT REQUIREMENT:
-- PostgreSQL declarative partitioning mandates that any UNIQUE or PRIMARY KEY
-- constraint on a partitioned table MUST contain all columns of the partition key.
-- Consequently, the primary key for partitioned orders becomes the composite key:
--     PRIMARY KEY (order_id, ordered_at)
-- =============================================================================

-- Ensure we operate within the correct schema
SET search_path TO amazon, public;

-- Enable partition pruning explicitly (default is on in PostgreSQL)
SET enable_partition_pruning = on;


-- -----------------------------------------------------------------------------
-- 1. DECLARATIVE PARTITIONED TABLE DDL
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS orders_partitioned CASCADE;

CREATE TABLE orders_partitioned (
    order_id       INTEGER         NOT NULL,
    customer_id    INTEGER         NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id     INTEGER         REFERENCES addresses(address_id) ON DELETE SET NULL,
    ordered_at     TIMESTAMPTZ     NOT NULL,
    payment_method TEXT            NOT NULL
                                   CHECK (payment_method IN ('CARD','UPI','GIFT_CARD','COD','NETBANKING','NET_BANKING','WALLET','EMI')),
    total_amount   NUMERIC(12,2)   NOT NULL CHECK (total_amount >= 0),
    status         TEXT            NOT NULL
                                   CHECK (status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY',
                                                     'DELIVERED','CANCELLED','RETURNED')),
    shipped_at     TIMESTAMPTZ,
    delivered_at   TIMESTAMPTZ,
    CONSTRAINT pk_orders_partitioned PRIMARY KEY (order_id, ordered_at)
) PARTITION BY RANGE (ordered_at);

COMMENT ON TABLE orders_partitioned IS 'Declarative RANGE-partitioned orders table partitioned quarterly by ordered_at.';
COMMENT ON COLUMN orders_partitioned.address_id IS 'Nullable for digital items requiring no physical shipping.';


-- -----------------------------------------------------------------------------
-- 2. QUARTERLY PARTITION SLICES (2025 Q1 — 2026 Q4 + DEFAULT)
-- -----------------------------------------------------------------------------

-- 2025 Historical Partitions
CREATE TABLE orders_2025_q1 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE orders_2025_q2 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE orders_2025_q3 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE orders_2025_q4 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- 2026 Active Partitions
CREATE TABLE orders_2026_q1 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

-- Target slice for June 2026 workload benchmarks (R06, R08, R15, R20, R21)
CREATE TABLE orders_2026_q2 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE orders_2026_q3 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE orders_2026_q4 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+05:30') TO ('2027-01-01 00:00:00+05:30');

-- Catch-all Default Partition for future dates and edge cases
CREATE TABLE orders_default PARTITION OF orders_partitioned DEFAULT;


-- -----------------------------------------------------------------------------
-- 3. LOCAL INDEXES ON PARTITIONED RELATIONS
-- In PostgreSQL 11+, defining an index on the partitioned parent automatically
-- propagates corresponding local B-tree indexes onto every child partition slice.
-- -----------------------------------------------------------------------------

-- Target: R04, R09, R10, R17, R18 (Customer purchase history navigation)
CREATE INDEX idx_orders_part_customer_ordered_at
    ON orders_partitioned (customer_id, ordered_at DESC);

-- Target: R13 (Anti-join index for identifying unused shipping addresses)
CREATE INDEX idx_orders_part_address_id
    ON orders_partitioned (address_id)
    WHERE address_id IS NOT NULL;

-- Target: R22 (Deep pagination walking ordered_at descending)
CREATE INDEX idx_orders_part_ordered_at_desc
    ON orders_partitioned (ordered_at DESC);

-- Target: R08, R20, R21 (Chronological active orders, excluding CANCELLED)
CREATE INDEX idx_orders_part_ordered_at_active
    ON orders_partitioned (ordered_at)
    WHERE status <> 'CANCELLED';

-- Target: R05 (Logistics monitoring for in-transit shipments)
CREATE INDEX idx_orders_part_shipped
    ON orders_partitioned (shipped_at)
    INCLUDE (customer_id, order_id)
    WHERE status = 'SHIPPED';

-- Target: W05 (Warehouse fulfillment: fast lookup of lowest pending packed order)
CREATE INDEX idx_orders_part_packed_min
    ON orders_partitioned (order_id)
    WHERE status = 'PACKED';


-- -----------------------------------------------------------------------------
-- 4. DATA MIGRATION FROM MONOLITHIC ORDERS TABLE
-- -----------------------------------------------------------------------------

-- Populate partitioned table from existing monolithic relation
INSERT INTO orders_partitioned
SELECT order_id, customer_id, address_id, ordered_at, payment_method,
       total_amount, status, shipped_at, delivered_at
FROM orders;

-- Refresh table-level and partition-level optimizer statistics
ANALYZE orders_partitioned;


-- -----------------------------------------------------------------------------
-- 5. PARTITION PRUNING DEMONSTRATION & VERIFICATION
-- The following queries run EXPLAIN (ANALYZE, BUFFERS) to verify that the query
-- planner isolates execution to the exact relevant partition slice (orders_2026_q2),
-- eliminating all historical and future partitions from the scan tree.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- DEMONSTRATION 1: Query R20 — Daily GMV & Running Total in June 2026
-- Expected Pruning: Scans ONLY orders_2026_q2. Prunes 8 out of 9 partitions.
-- -----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT ordered_at::date AS day, sum(total_amount) AS gmv
    FROM orders_partitioned
    WHERE status <> 'CANCELLED'
      AND ordered_at >= '2026-06-01 00:00:00+05:30'
      AND ordered_at <  '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- -----------------------------------------------------------------------------
-- DEMONSTRATION 2: Query R21 — Delayed Delivery Identification (June 2026)
-- Expected Pruning: Scans ONLY orders_2026_q2 using local active index.
-- -----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, ordered_at, delivered_at
FROM orders_partitioned
WHERE delivered_at > ordered_at + interval '5 days'
  AND ordered_at >= '2026-06-01 00:00:00+05:30'
  AND ordered_at <  '2026-07-01 00:00:00+05:30'
ORDER BY delivered_at - ordered_at DESC;

-- -----------------------------------------------------------------------------
-- DEMONSTRATION 3: Query R06 — Seller Central Orders for Seller 217 (June 2026)
-- Expected Pruning: Join between order_items and orders_partitioned accesses only
-- orders_2026_q2; all other quarters are pruned.
-- -----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.ordered_at, oi.product_id, oi.quantity, oi.unit_price
FROM order_items oi
JOIN orders_partitioned o ON o.order_id = oi.order_id
WHERE oi.seller_id = 217
  AND o.ordered_at >= '2026-06-01 00:00:00+05:30'
  AND o.ordered_at <  '2026-07-01 00:00:00+05:30'
ORDER BY o.ordered_at;

-- -----------------------------------------------------------------------------
-- DEMONSTRATION 4: Query R08 — Merchandising Top 5 Sub-category Products (June 2026)
-- Expected Pruning: Multi-table join filters orders to June 2026, pruning 8 partitions.
-- -----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM (
    SELECT p.category_id, oi.product_id, sum(oi.quantity) AS units,
           RANK() OVER (PARTITION BY p.category_id ORDER BY sum(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN orders_partitioned o ON o.order_id = oi.order_id
    JOIN products p          ON p.product_id = oi.product_id
    WHERE o.ordered_at >= '2026-06-01 00:00:00+05:30'
      AND o.ordered_at <  '2026-07-01 00:00:00+05:30'
      AND o.status <> 'CANCELLED'
    GROUP BY p.category_id, oi.product_id
) t
WHERE rnk <= 5
ORDER BY category_id, rnk;


-- -----------------------------------------------------------------------------
-- 6. PARTITION METRIC AUDITING & METADATA INSPECTION
-- -----------------------------------------------------------------------------
SELECT
    child.relname AS partition_name,
    pg_size_pretty(pg_relation_size(child.oid)) AS data_size,
    pg_size_pretty(pg_indexes_size(child.oid)) AS index_size,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size,
    pg_catalog.pg_get_expr(child.relpartbound, child.oid) AS partition_bounds
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child  ON pg_inherits.inhrelid = child.oid
WHERE parent.relname = 'orders_partitioned'
ORDER BY child.relname;
