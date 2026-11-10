# Phase 3 — Baseline Query Timings & Bottleneck Analysis

**Course:** Database Management Systems · **Team:** T0063 · **Section:** C  
**Repo:** [DE_PROJECT_2026](https://github.com/Anish-choudharyy/DE_PROJECT_2026)  
**Author:** Aksh Rathi (GitHub: [@aksh2801](https://github.com/aksh2801))

---

## 1. Baseline Environment

All benchmark runs were executed against the unindexed baseline schema (`sql/01_schema.sql`) loaded with the complete dataset (`sql/02_load_data.sql`). At this checkpoint (CP2), the database contains only primary key and unique constraints; no secondary B-tree, partial, covering, expression, or GIN indexes have been applied.

| Parameter | Specification |
|:---|:---|
| **Operating System** | macOS 27.2 (Darwin arm64) |
| **Processor** | Apple M4 (10 cores) |
| **System Memory (RAM)** | 16 GB unified memory |
| **Database Engine** | PostgreSQL 18.6 (Postgres.app, 64-bit) |
| **Storage Subsystem** | Apple APFS high-speed NVMe SSD |
| **Execution Tool** | `benchmarks/run_benchmark.sh` (3 iterations per query with `EXPLAIN (ANALYZE, BUFFERS)`) |
| **Isolation Mode** | Read queries executed directly; Write queries encapsulated in `BEGIN ... ROLLBACK` blocks |

### Seed Dataset Row Counts

| Relation | Primary Key | Row Count | Disk Footprint / Notes |
|:---|:---|---:|:---|
| `cities` | `city_id` | 10 | Master lookup |
| `categories` | `category_id` | 40 | Hierarchical category tree (self-referential) |
| `sellers` | `seller_id` | 1,500 | Marketplace vendors |
| `customers` | `customer_id` | 30,000 | Registered buyers |
| `addresses` | `address_id` | 45,000 | Saved customer delivery locations |
| `products` | `product_id` | 30,000 | Product catalog items |
| `orders` | `order_id` | 120,000 | Header records across 2025–2026 |
| `order_items` | `(order_id, line_no)` | 240,000 | Line-item detail records |
| `cart_items` | `(customer_id, product_id)` | 44,998 | Active customer cart contents |
| `product_reviews` | `review_id` | 38,662 | Star ratings and review text |
| `returns` | `return_id` | 5,374 | Return requests on line items |
| **Total** | | **555,584** | Across all 11 relational tables |

---

## 2. Baseline Benchmark Results (All 30 Queries)

Every query from `queries/workload_30.sql` was evaluated across 3 consecutive iterations using `EXPLAIN (ANALYZE, BUFFERS)`. The metrics below reflect execution times recorded in `benchmarks/results/baseline/summary.csv`.

| Query ID | Type | Workload Description | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Primary Scan Nodes / Access Paths |
|:---|:---:|:---|---:|---:|---:|---:|:---|
| **R01** | READ | Search box: active products with title matching "wireless" | 16.632 | 15.458 | 13.606 | 20.833 | `Seq Scan on products` |
| **R02** | READ | Category browse: all sub-levels under "Electronics" (₹1k–₹5k) | 2.759 | 2.695 | 2.688 | 2.894 | `Seq Scan on categories` \| `Seq Scan on products` |
| **R03** | READ | Product page: rating breakdown (1★–5★) for product 4321 | 1.113 | 1.114 | 1.106 | 1.118 | `Seq Scan on product_reviews` |
| **R04** | READ | "Your Orders": customer 1042's orders with item counts | 3.034 | 3.044 | 2.935 | 3.122 | `Seq Scan on orders` \| `Index Only Scan on order_items` |
| **R05** | READ | Logistics: shipments in transit > 10 days | 4.481 | 4.517 | 4.382 | 4.543 | `Seq Scan on orders` |
| **R06** | READ | Seller Central: seller 217's line items in June 2026 | 4.829 | 4.773 | 4.635 | 5.080 | `Seq Scan on order_items` \| `Index Scan on orders` |
| **R07** | READ | Seller Central: seller 217's low stock products (<= 20) | 1.630 | 1.647 | 1.575 | 1.668 | `Seq Scan on products` |
| **R08** | READ | Merchandising: top 5 best-sellers per sub-category (last 30d) | 22.270 | 22.168 | 21.819 | 22.824 | `Seq Scan on order_items` \| `Seq Scan on orders` \| `Seq Scan on products` |
| **R09** | READ | Prime team: average order value Prime vs non-Prime in 2026 | 22.321 | 22.421 | 21.944 | 22.598 | `Seq Scan on orders` \| `Seq Scan on customers` |
| **R10** | READ | Marketing: abandoned cart customers with no prior orders | 15.696 | 15.771 | 15.303 | 16.015 | `Seq Scan on orders` \| `Seq Scan on cart_items` \| `Seq Scan on products` |
| **R11** | READ | Co-purchase: top 5 products frequently bought with product 1001 | 4.567 | 4.577 | 4.535 | 4.589 | `Seq Scan on order_items` \| `Index Scan on order_items` |
| **R12** | READ | Quality team: top 10 categories with highest return rate | **59.213** | 59.000 | 58.941 | 59.697 | `Seq Scan on order_items` \| `Seq Scan on products` \| `Seq Scan on categories` \| `Seq Scan on returns` |
| **R13** | READ | Fulfillment: orders shipped to non-primary city | 15.971 | 16.086 | 15.729 | 16.097 | `Seq Scan on addresses` \| `Seq Scan on orders` |
| **R14** | READ | Faceted search: count of active products by brand & price band | 3.749 | 3.754 | 3.650 | 3.844 | `Seq Scan on products` |
| **R15** | READ | Seller Central: top 10 sellers by revenue in June 2026 | 21.702 | 21.682 | 21.569 | 21.855 | `Seq Scan on order_items` \| `Seq Scan on orders` \| `Seq Scan on sellers` |
| **R16** | READ | Review insights: Electronics reviews mentioning "battery" | 12.063 | 11.989 | 11.874 | 12.326 | `Seq Scan on product_reviews` \| `Seq Scan on products` \| `Seq Scan on categories` |
| **R17** | READ | Trust & safety: verified reviews lacking delivered orders | **49.522** | 48.897 | 48.256 | 51.414 | `Seq Scan on order_items` \| `Seq Scan on orders` \| `Seq Scan on product_reviews` |
| **R18** | READ | Customer analytics: Mumbai spending quartile breakdown | 8.929 | 8.990 | 8.766 | 9.031 | `Seq Scan on orders` \| `Seq Scan on customers` |
| **R19** | READ | Category report: Mobiles last sale date & units sold | **9037.996** | 9044.592 | 8963.162 | 9106.234 | `Seq Scan on categories` \| `Seq Scan on products` \| `Seq Scan on order_items` \| `Index Scan on orders` |
| **R20** | READ | Finance: daily GMV and running total for June 2026 | 6.282 | 6.357 | 6.051 | 6.439 | `Seq Scan on orders` |
| **R21** | READ | Logistics: June deliveries taking more than 5 days | 5.316 | 5.024 | 4.790 | 6.133 | `Seq Scan on orders` |
| **R22** | READ | Deep pagination: page 3001 of orders sorted newest first | **30.352** | 27.562 | 24.102 | 39.392 | `Seq Scan on orders` (external merge sort to disk) |
| **R23** | READ | Order details: full invoice line items for order 12345 | 0.086 | 0.090 | 0.068 | 0.099 | `Index Scan using order_items_pkey, orders_pkey, products_pkey, sellers_pkey` |
| **R24** | READ | Barcode lookup: find single product by ASIN barcode | 0.038 | 0.041 | 0.024 | 0.049 | `Index Scan using products_asin_key on products` |
| **W01** | WRITE | Checkout: create single new order header record | 0.911 | 0.577 | 0.508 | 1.649 | *(no scan)* — plain single-tuple INSERT |
| **W02** | WRITE | Seller: restock product quantity for product 4321 | 0.343 | 0.383 | 0.154 | 0.492 | `Index Scan using products_pkey on products` |
| **W03** | WRITE | Seller: apply 10% discount across category 5 products | 1.165 | 1.060 | 1.048 | 1.388 | `Seq Scan on products` \| `Seq Scan on categories` |
| **W04** | WRITE | Bulk cart sync: batch insert 5,000 cart items | **29.357** | 29.387 | 29.118 | 29.566 | *(no scan)* — 5,000 FK trigger checks |
| **W05** | WRITE | Logistics: update delivery timestamp for delivered order | 7.183 | 7.210 | 7.107 | 7.233 | `Index Scan using orders_pkey on orders` |
| **W06** | WRITE | Cart cleanup: purge abandoned cart items older than 30d | 5.229 | 5.280 | 4.964 | 5.442 | `Seq Scan on cart_items` |

---

## 3. Bottleneck Analysis: Top 5 Slowest Queries

Across the 30-query workload, five distinct queries emerge as severe performance bottlenecks. Each of these queries exhibits high latency, excessive shared buffer access, disk spilling, or massive repeated sequential scans due to the complete lack of secondary indexes.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              BASELINE BOTTLENECK PROFILE                               │
├────────┬────────────┬──────────────────────────────────────────────────────────────────┤
│ Query  │  Avg Time  │ Dominant Root Cause                                              │
├────────┼────────────┼──────────────────────────────────────────────────────────────────┤
│ R19    │ 9037.99 ms │ N*2 full table scans over 240,000 order_items via correlated subQ│
│ R12    │   59.21 ms │ 4-table join on unindexed FKs with aggregate return rate math    │
│ R17    │   49.52 ms │ Correlated anti-join scanning 240k items + 120k orders + reviews │
│ R22    │   30.35 ms │ Deep offset sort (OFFSET 75000) spilling 5.2 MB temp sort to disk│
│ W04    │   29.36 ms │ 5,000 individual row-by-row foreign key trigger checks on INSERT │
└────────┴────────────┴──────────────────────────────────────────────────────────────────┘
```

---

### Bottleneck #1: Query R19 — Mobiles Category Sales & Last Sold Date

- **Query ID:** `R19` (READ)
- **Average Execution Time:** **9,037.996 ms** (~9.04 seconds)
- **Min / Max:** 8,963.162 ms / 9,106.234 ms
- **Buffer Hits:** `shared hit=2,991,908` (~23.9 GB in-memory data churn)

```sql
SELECT p.product_id, p.title,
       (SELECT max(o.ordered_at)
        FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
        WHERE oi.product_id = p.product_id) AS last_sold_at,
       (SELECT coalesce(sum(oi.quantity), 0)
        FROM order_items oi
        WHERE oi.product_id = p.product_id) AS units_sold
FROM products p
WHERE p.category_id = (SELECT category_id FROM categories WHERE category_name = 'Mobiles')
ORDER BY units_sold DESC, p.product_id;
```

#### Plan Analysis & Root Cause:
1. **Double Correlated Subqueries in SELECT List:**
   The query matches 937 products in the 'Mobiles' category. For *every single one* of these 937 products, the PostgreSQL query planner evaluates **SubPlan 1** (`last_sold_at`) and **SubPlan 2** (`units_sold`).
2. **1,874 Full Table Scans:**
   Neither `SubPlan 1` nor `SubPlan 2` can perform an index lookup because `order_items` has no index on `product_id`. As a result, PostgreSQL performs:
   $$\text{Total Sequential Scans} = 937 \times 2 = 1,874 \text{ full scans of } order\_items$$
   With 240,000 rows in `order_items`, the engine scans over **449,760,000 tuples** in total!
3. **Execution Plan Trace:**
   ```text
   -> Seq Scan on products p (cost=0.00..8670648.12 rows=938)
      SubPlan 1: Nested Loop (loops=937)
         -> Seq Scan on order_items oi (rows=240000, loops=937)
      SubPlan 2: Aggregate (loops=937)
         -> Seq Scan on order_items oi (rows=240000, loops=937)
   ```
4. **CP3 Optimization Plan:**
   - Create a B-tree index on `order_items(product_id, quantity)`.
   - Rewrite the query to eliminate correlated subqueries, using an explicit `LEFT JOIN` on an aggregated CTE or subquery grouped by `product_id`.

---

### Bottleneck #2: Query R12 — Top 10 Categories by Highest Return Rate

- **Query ID:** `R12` (READ)
- **Average Execution Time:** **59.213 ms**
- **Min / Max:** 58.941 ms / 59.697 ms
- **Buffer Hits:** `shared hit=2,653`

```sql
SELECT top.category_name,
       count(oi.*) AS items_sold,
       count(r.return_id) AS items_returned,
       round(100.0 * count(r.return_id) / count(oi.*), 2) AS return_rate_pct
FROM order_items oi
JOIN products p      ON p.product_id = oi.product_id
JOIN categories sub  ON sub.category_id = p.category_id
JOIN categories top  ON top.category_id = coalesce(sub.parent_category_id, sub.category_id)
LEFT JOIN returns r  ON r.order_id = oi.order_id AND r.line_no = oi.line_no
GROUP BY top.category_name
ORDER BY return_rate_pct DESC
LIMIT 10;
```

#### Plan Analysis & Root Cause:
1. **Unindexed Multi-Way Joins on Massive Tables:**
   This query joins four distinct tables: `order_items` (240,000 rows), `products` (30,000 rows), `categories` (scanned twice for hierarchy resolution), and `returns` (5,374 rows).
2. **Missing Secondary Indexes on Join Keys:**
   - `order_items.product_id` has no index.
   - `products.category_id` has no index.
   - `returns(order_id, line_no)` has only the primary key on `return_id`; foreign keys back to `order_items` are not indexed.
3. **Expensive Parallel Sequential Scans & Hash Joins:**
   PostgreSQL is forced to launch parallel workers (`Workers Launched: 1`), execute a `Parallel Seq Scan on order_items` (120,000 rows per loop), build multiple in-memory Hash tables (1,428 kB for `products`), perform a `Hash Left Join` with `returns`, and execute a two-stage `Partial HashAggregate` followed by a `Gather Merge` and sort.
4. **CP3 Optimization Plan:**
   - Create index on `order_items(product_id)`.
   - Create index on `products(category_id)`.
   - Create composite index on `returns(order_id, line_no)`.

---

### Bottleneck #3: Query R17 — Trust & Safety: Unverified Review Auditing

- **Query ID:** `R17` (READ)
- **Average Execution Time:** **49.522 ms**
- **Min / Max:** 48.256 ms / 51.414 ms
- **Buffer Hits:** `shared hit=3,442`

```sql
SELECT r.review_id, r.product_id, r.customer_id
FROM product_reviews r
WHERE r.verified_purchase
  AND NOT EXISTS (
      SELECT 1
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.order_id
      WHERE o.customer_id = r.customer_id
        AND oi.product_id = r.product_id
        AND o.status IN ('DELIVERED', 'RETURNED')
  );
```

#### Plan Analysis & Root Cause:
1. **Unindexed Correlated NOT EXISTS Subquery:**
   The query checks 35,662 `product_reviews` where `verified_purchase = true` against customer purchase histories to detect fraudulent review badges.
2. **Massive Hash Right Anti Join:**
   Without indexes on `orders(customer_id, status)` or `order_items(product_id, order_id)`, the planner transforms the subquery into a `Hash Right Anti Join`:
   - It performs a `Seq Scan on orders` (120,000 rows), filtering on `status = ANY ('{DELIVERED,RETURNED}')` (110,646 matching tuples), building a **5.35 MB hash table**.
   - It executes a full `Seq Scan on order_items` (240,000 rows) to probe the order hash table.
   - It performs another `Seq Scan on product_reviews` (38,662 rows, 2.05 MB hash table) to perform the composite anti-join on `(customer_id, product_id)`.
3. **CP3 Optimization Plan:**
   - Composite B-tree index on `orders(customer_id, status)` to filter eligible deliveries immediately.
   - Composite B-tree index on `order_items(product_id, order_id)`.
   - Partial index on `product_reviews(customer_id, product_id) WHERE verified_purchase = TRUE`.

---

### Bottleneck #4: Query R22 — Deep Order History Pagination

- **Query ID:** `R22` (READ)
- **Average Execution Time:** **30.352 ms**
- **Min / Max:** 24.102 ms / 39.392 ms
- **Temp Disk Spillage:** `temp read=578 written=651` (~5,192 kB written to disk)

```sql
SELECT order_id, ordered_at, customer_id, total_amount, status
FROM orders
ORDER BY ordered_at DESC
OFFSET 75000 LIMIT 25;
```

#### Plan Analysis & Root Cause:
1. **Full Sequential Scan for Sorting:**
   Lacking an index on `orders(ordered_at DESC)`, PostgreSQL cannot walk an index in sort order. It must sequentially scan the entire `orders` table (120,000 rows, 1,392 shared blocks).
2. **External Merge Disk Sort Spillage:**
   Sorting 120,000 rows containing 5 columns exceeds `work_mem`. The planner falls back to an **external merge disk sort**:
   ```text
   -> Sort (cost=15589.10..15889.10 rows=120000 width=30)
      Sort Method: external merge  Disk: 5192kB
      Buffers: shared hit=1395, temp read=578 written=651
   ```
   Writing 5.2 MB of intermediate runfiles to temporary disk space and reading them back introduces severe I/O penalties.
3. **Offset Inefficiency:**
   Skipping 75,000 tuples requires evaluating and discarding 75,000 sorted records before emitting 25 rows.
4. **CP3 Optimization Plan:**
   - Create a descending B-tree index on `orders(ordered_at DESC)`. This allows the planner to perform an `Index Scan Backward` or `Index Scan`, streaming tuples directly and stopping immediately after 75,025 rows with zero disk sort overhead.

---

### Bottleneck #5: Query W04 — Batch Cart Insertions with Foreign Key Verification

- **Query ID:** `W04` (WRITE)
- **Average Execution Time:** **29.357 ms**
- **Min / Max:** 29.118 ms / 29.566 ms
- **Buffer Hits:** `shared hit=32,543 dirtied=182`

```sql
INSERT INTO cart_items (customer_id, product_id, quantity, added_at)
SELECT (1 + (g.i * 7) % 30000)::integer,
       (1 + (g.i * 13) % 30000)::integer,
       1 + (g.i % 5),
       '2026-07-01 12:00:00+05:30'::timestamptz + (g.i || ' seconds')::interval
FROM generate_series(1, 5000) AS g(i)
ON CONFLICT (customer_id, product_id) DO NOTHING;
```

#### Plan Analysis & Root Cause:
1. **Foreign Key Constraint Verification Overhead:**
   While the tuple generation and index insertion on `cart_items_pkey` takes under 8.5 ms, over **70% of the wall-clock time (20.8 ms)** is consumed by constraint verification triggers:
   ```text
   Trigger for constraint cart_items_customer_id_fkey: time=10.436 calls=5000
   Trigger for constraint cart_items_product_id_fkey:  time=10.426 calls=5000
   ```
2. **5,000 Individual Index Lookups per Constraint:**
   Every single inserted tuple triggers two separate referential integrity checks against `customers(customer_id)` and `products(product_id)`. Although both target primary keys, evaluating 10,000 trigger checks per batch creates a noticeable write-path overhead.
3. **CP3 Optimization Plan:**
   - Evaluate `DEFERRABLE INITIALLY DEFERRED` constraint configurations for bulk ingest pipelines or investigate batch transaction structures.

---

## 4. Notable Secondary Bottlenecks

Beyond the top 5, several other queries demonstrate clear symptoms of missing indexes:

1. **R09 (Prime vs. Non-Prime Average Order Value — 22.321 ms):**
   - Performs sequential scans across both `orders` (120k rows) and `customers` (30k rows).
   - Filters on `EXTRACT(year FROM ordered_at) = 2026` and `status <> 'CANCELLED'`, discarding 82,834 orders sequentially.
   - Requires expression/partial index on `orders((ordered_at)) WHERE status <> 'CANCELLED'`.
2. **R08 (Top 5 Best-Selling Products per Sub-Category — 22.270 ms):**
   - Joins 240,000 `order_items`, 120,000 `orders`, and 30,000 `products`.
   - Filters on `ordered_at >= '2026-06-01'` via sequential scan of 120k orders, discarding 113,811 rows.
   - Requires B-tree index on `orders(ordered_at)`.
3. **R15 (Top 10 Sellers by Revenue in June 2026 — 21.702 ms):**
   - Joins `order_items`, `orders`, and `sellers` with date truncation `date_trunc('month', o.ordered_at) = '2026-06-01'`.
   - Lacking indexes on `orders(ordered_at)` and `order_items(seller_id)`, it performs full table scans across 360,000 combined tuples.
4. **R01 (Product Search ILIKE '%wireless%' — 16.632 ms):**
   - Performs a sequential scan over all 30,000 products evaluating substring matching `title ILIKE '%wireless%'`.
   - Standard B-tree indexes cannot accelerate leading-wildcard LIKE queries.
   - Requires a **GIN trigram index** using the `pg_trgm` extension on `products USING gin (title gin_trgm_ops)`.

---

## 5. Optimization Roadmap for Phase 4 (CP3)

Based on these baseline findings, the target index strategy for Checkpoint 3 (`sql/05_indexes.sql`) must focus on:

1. **Foreign Key Coverage:**
   - `order_items(product_id)` (resolves R19 catastrophic loop, speeds up R08, R11, R12).
   - `order_items(seller_id)` (accelerates R06, R15).
   - `products(category_id)` (speeds up R02, R12, R14, R19).
   - `returns(order_id, line_no)` (speeds up R12).
2. **Order Lifecycle & Filtering:**
   - `orders(customer_id, ordered_at DESC)` (speeds up R04).
   - `orders(ordered_at DESC)` (eliminates R22 disk sort and speeds up R08, R20).
   - `orders(status, shipped_at)` (speeds up R05, R21).
3. **Text Search Acceleration:**
   - GIN Trigram index on `products USING gin (title gin_trgm_ops)` for fast ILIKE search (R01).
   - GIN Trigram index on `product_reviews USING gin (body gin_trgm_ops)` for text mining (R16).
4. **Query Rewrites (`sql/06_optimized_queries.sql`):**
   - Eliminate correlated subqueries in R19 by rewriting with aggregated CTEs and LEFT JOINs.
   - Refactor anti-joins and date-truncation expressions where appropriate.
