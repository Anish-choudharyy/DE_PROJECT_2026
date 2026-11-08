# Phase 1 — Problem Understanding

**Course:** Database Management Systems · **Team:** T0063 · **Section:** C  
**Repo:** [DE_PROJECT_2026](https://github.com/Anish-choudharyy/DE_PROJECT_2026)

---

## 1. System Overview

Amazon India is a large-scale online marketplace connecting **sellers** and **customers** across
the country. At its core, the platform manages:

- A **category tree** (e.g., Electronics → Mobiles → Smartphones) used to browse and search products.
- Thousands of **seller** accounts who list **products** with individual prices, stock, and ratings.
- **Customer** accounts with one or more saved **addresses** (digital products such as e-books or
  gift cards need no shipping address).
- A **shopping cart** that holds items before checkout.
- **Orders** that track the full lifecycle: PLACED → PACKED → SHIPPED → OUT_FOR_DELIVERY → DELIVERED
  (or CANCELLED / RETURNED).
- A **reviews** system where customers can leave ratings and text; reviews are flagged as
  `verified_purchase` when the customer has an actual delivered order for that product.
- A **returns** workflow with reason codes, refund amounts, and approval statuses.
- A **Prime** membership programme that filters eligibility at the product level.

The current database was assembled quickly by an earlier team. Only data exports (CSV files) survive —
there is no documented schema, no index strategy, and no query plan analysis. Product teams across
Search, Logistics, Marketing, Trust & Safety, and Finance are all reporting slowdowns and correctness
bugs. This project systematically reverses-engineers the schema, documents the design, loads the data,
profiles the 30-query workload, and applies targeted optimizations.

---

## 2. Problem Statements

| # | Problem Reported | Affected Team | Related Queries |
|---|------------------|---------------|-----------------|
| P1 | Search and category pages are sluggish, especially for categories with many sub-categories | Search / Browse | R01, R02, R14 |
| P2 | Product page (ratings breakdown, frequently-bought-together) loads slowly for popular products | Product Page | R03, R11, R24 |
| P3 | "Your Orders" and order-detail pages take too long to open | Customer App | R04, R23 |
| P4 | Seller Central dashboards (monthly orders, low stock, price changes) are slow | Sellers | R06, R07, R15, W02, W03 |
| P5 | Logistics cannot quickly surface stuck / late shipments; the packing queue lags | Logistics | R05, R21, W05 |
| P6 | The address clean-up report claims "no address is unused", contradicting Support's experience | Data Quality | R13 |
| P7 | Abandoned-cart campaigns and nightly cart-clean-up jobs run far too long | Marketing | R10, W04, W06 |
| P8 | Trust & Safety needs to detect fake "verified purchase" reviews and analyse review text | Trust & Safety | R16, R17 |
| P9 | Category, Prime, and finance reports time out; a 20× traffic spike is expected next festive season | Analytics / Finance | R08, R09, R12, R18, R19, R20, R22 |

---

### P1 — Search and Category Pages Are Slow

**What:** Queries that browse a category or its full sub-tree (R01, R02, R14) are slow.  
**Why:** The `categories` table has a self-referencing `parent_category_id` column forming a tree.
Fetching all descendants requires a recursive CTE (`WITH RECURSIVE`). Without an index on
`parent_category_id`, this requires sequential scans at every level of the tree. Additionally,
joining back to `products` with no composite index on `(category_id, status, price)` forces
another full scan over 30,000 product rows.  
**Affected queries:** R01 (product listing for a category), R02 (sub-category tree traversal), R14
(Prime-eligible products by category).

---

### P2 — Product Page Loads Slowly

**What:** Fetching a product's full detail — including rating histogram and "frequently bought together"
items — is slow for popular products.  
**Why:** `avg_rating` and `review_count` on `products` are denormalized for fast reads, but the full
ratings breakdown still needs an aggregation over `product_reviews`. The "frequently bought together"
query (R11) scans all orders containing the target product and cross-joins with other items in those
orders — an expensive operation with no covering index. ASIN lookup (R24) used in warehouse scanners
has no unique index, forcing a full table scan.  
**Affected queries:** R03 (ratings histogram), R11 (frequently bought together), R24 (lookup by ASIN).

---

### P3 — "Your Orders" Is Slow

**What:** The order list and individual order-detail page (R04, R23) take too long to load.  
**Why:** Fetching a customer's orders requires filtering `orders` by `customer_id`. Without a
B-tree index on `(customer_id, ordered_at DESC)`, the database performs a full scan of 120,000 order
rows. The order-detail page (R23) further joins `order_items`, `products`, and `sellers` — four-table
joins with no covering indexes.  
**Affected queries:** R04 (order list for a customer), R23 (single order detail with line items).

---

### P4 — Seller Central Dashboards Are Slow

**What:** Monthly order summaries, low-stock alerts, and bulk price updates (R06, R07, R15, W02, W03)
are slow.  
**Why:** `orders` and `order_items` have no composite index on `(seller_id, ordered_at)`. Low-stock
queries (R07) scan all 30,000 products rows without a partial index on `stock_qty`. Bulk price updates
(W03) join `products` with `categories` and filter by `seller_id` and `category_name` — a double
scan without indexes.  
**Affected queries/writes:** R06, R07, R15, W02, W03.

---

### P5 — Logistics: Stuck and Late Shipments Hard to Find

**What:** Finding orders that are stuck in PACKED status or were delivered late (R05, R21, W05) is slow.  
**Why:** Filtering `orders` by `status = 'PACKED'` or by `delivered_at > ordered_at + interval '5 days'`
requires a full table scan. Without a partial index on status or a functional index on delivery latency,
the logistics dashboard becomes a bottleneck as order volume grows.  
**Affected queries/writes:** R05, R21, W05.

---

### P6 — "No Address Is Unused" Data Quality Bug

**What:** The address clean-up report (R13) says every address has been used in an order, which
contradicts customer support's experience of addresses never being selected at checkout.  
**Why:** This is likely a query correctness bug — a `LEFT JOIN` that should be checking for NULL
in `orders.address_id` is instead written as an `INNER JOIN`, returning only addresses that _are_
used. No address is ever reported as unused because unused addresses are silently excluded.  
**Affected query:** R13.

---

### P7 — Abandoned-Cart Campaigns Are Slow

**What:** Finding customers with items in cart for over N days (R10) and batch-inserting 5,000 cart
events (W04) or deleting old items (W06) run for too long.  
**Why:** `cart_items` has a composite primary key on `(customer_id, product_id)` but no index on
`added_at`. The nightly clean-up (`DELETE WHERE added_at < X`) and campaign query (`WHERE added_at < NOW() - interval`)
both scan the full table. Batch inserts with `ON CONFLICT DO NOTHING` also stall without an efficient
unique index.  
**Affected queries/writes:** R10, W04, W06.

---

### P8 — Fake "Verified Purchase" Reviews

**What:** Trust & Safety needs to detect reviews marked `verified_purchase = TRUE` for products the
customer never actually received (R17), and also search review text for keywords like "battery" (R16).  
**Why:** R17 uses a correlated `NOT EXISTS` subquery that for each review checks all orders and
order_items — an O(reviews × orders) scan. R16 uses `ILIKE '%battery%'` which cannot use a standard
B-tree index; a GIN/pg_trgm index on `body` would help.  
**Affected queries:** R16, R17.

---

### P9 — Analytics and Finance Reports Time Out

**What:** Reports on category performance, Prime vs. non-Prime splits, GMV, AOV, spending tiers,
returns, and deep-pagination admin views (R08, R09, R12, R18, R19, R20, R22) all time out. With a
20× traffic multiplier expected during the next festive season, the system must be re-architected.  
**Why:** These are heavy aggregation queries across `orders`, `order_items`, `products`, and
`categories`. Without partial indexes, covering indexes, table partitioning on `ordered_at`, or
materialized views for pre-aggregated summaries, each report does a full scan of 240,000 order-item
rows and 120,000 order rows. Deep-offset pagination (R22, OFFSET 75,000) is inherently slow.  
**Affected queries:** R08, R09, R12, R18, R19, R20, R22.

---

## 3. Project Plan

This project addresses all nine problem statements in five phases:

| Phase | Deliverable | Goal |
|-------|-------------|------|
| 1 | Problem understanding (this document) | Map complaints to root causes and affected queries |
| 2 | Schema DDL + load script + schema design doc | Establish a clean, normalized PostgreSQL schema and load 11 CSVs |
| 3 | Baseline timings (30 queries, 3 runs each) | Quantify current performance with `EXPLAIN ANALYZE` |
| 4 | Indexes + optimized queries + optimization report | Apply B-tree, partial, GIN, and composite indexes; rewrite slow queries; measure improvement |
| 5 | Scalability report on large dataset | Validate that optimizations hold under a 20× data volume |

The schema will be designed in **3NF**, with carefully chosen denormalizations (e.g., `avg_rating`
and `review_count` on `products`) justified by workload analysis. All indexes will be in a separate
`sql/05_indexes.sql` file so the before/after benchmark remains reproducible.
