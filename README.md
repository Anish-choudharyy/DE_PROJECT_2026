# Amazon Online Shopping Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 11 CSV files (120,000 orders): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role | Name | Enrollment No. | GitHub Username |
|------|------|----------------|-----------------|
| Group Lead | | | |
| Member 2 | | | |
| Member 3 | | | |
| Member 4 | | | |

**Team No.:** ____ · **Section:** ____ · **Repository URL:** ____

---

## How this project works

| Phase | What you do | You submit | Marks |
|-------|-------------|------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | 5 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | 25 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | 15 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | 30 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | 25 |
| | **Total** | | **100** |

---

## Phase 1: Problem statements

Amazon India is a marketplace: thousands of **sellers** list products in a **category tree** (Electronics → Mobiles, Books → E-Books, …), customers add products to their **cart**, check out to one of their saved **addresses** (digital products such as e-books and gift cards need no address), pay, and track the shipment. Some items are **returned**, and customers write **reviews** that may or may not be from a verified purchase. Prime members get faster delivery. You have joined the database team for Amazon India.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "**Search and category pages** feel sluggish, especially when a category has many sub-categories." | Search / Browse | R01, R02, R14 |
| P2 | "The **product page** (ratings breakdown, frequently bought together) loads slowly for popular products." | Product page | R03, R11, R24 |
| P3 | "Customers say **Your Orders** and order details take too long to open." | Customer app | R04, R23 |
| P4 | "**Seller Central** dashboards (monthly orders, low stock, price changes) are slow." | Sellers | R06, R07, R15, W02, W03 |
| P5 | "Logistics can't quickly find **stuck and late shipments**, and the packing queue lags." | Logistics | R05, R21, W05 |
| P6 | "The address clean-up report says **no address is unused**, which contradicts customer support's experience." | Data quality | R13 |
| P7 | "**Abandoned-cart** campaigns and cart clean-up jobs run for too long." | Marketing | R10, W04, W06 |
| P8 | "Trust & safety needs to catch **fake 'verified purchase' reviews** and analyse review text." | Trust & Safety | R16, R17 |
| P9 | "Category, Prime and finance reports (returns, AOV, GMV, spend tiers) time out, and traffic will grow **20×** by next festive season." | Analytics / Finance | R08, R09, R12, R18, R19, R20, R22, W01 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P9, write in your own words what the business needs and which **stakeholder** is affected (customer, seller, category manager, logistics, Prime team, marketing, trust & safety, finance, admin).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 11 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `cities.csv` | 10 | Cities of customers and sellers |
| `categories.csv` | 40 | Product categories (a tree: each sub-category points to its parent) |
| `sellers.csv` | 1,500 | Businesses selling on Amazon |
| `products.csv` | 30,000 | Product listings |
| `customers.csv` | 30,000 | Shoppers (some are Prime members) |
| `addresses.csv` | 45,000 | Saved delivery addresses of customers |
| `orders.csv` | 120,000 | Every order placed from 1 Jan 2025 to 30 Jun 2026 |
| `order_items.csv` | 240,000 | Lines of each order |
| `returns.csv` | 5,374 | Return requests for order lines |
| `product_reviews.csv` | 38,662 | Product reviews (verified and unverified) |
| `cart_items.csv` | 44,998 | What customers currently have in their carts |

The first line of every file is the header (column names). Here are the headers and the first rows of each file:

**cities.csv**
```
city_id,city_name,state
1,Bengaluru,Karnataka
2,Mumbai,Maharashtra
```

**categories.csv**
```
category_id,category_name,parent_category_id,is_digital
1,Electronics,,f
2,Fashion,,f
```

**sellers.csv**
```
seller_id,business_name,gstin,city_id,joined_on,seller_rating,status
1,Global Retail 1,02BAPKA0001H1Z1,3,2019-09-24,3.3,ACTIVE
2,Prime Retail 2,03CAPKA0002O1Z2,8,2024-09-10,3.7,ACTIVE
```

**products.csv**
```
product_id,asin,seller_id,category_id,title,brand,mrp,price,stock_qty,is_prime_eligible,avg_rating,review_count,listed_on,status
1,B000001EEF,1,16,Mi Wireless Watch X1,Mi,3539.00,2918.00,32,t,4.0,1,2022-03-21,ACTIVE
2,B000003DDE,1,23,Prestige Wireless E-Book X1,Prestige,299.00,137.00,160,t,,0,2022-05-21,ACTIVE
```

**customers.csv**
```
customer_id,full_name,email,phone,city_id,signup_date,is_prime,prime_since
1,Vivaan Sharma,Vivaan.Sharma1@Outlook.com,9000000001,2,2022-06-10,f,
2,Aditya Sharma,Aditya.Sharma2@Outlook.com,9000000002,4,2020-04-01,f,
```

**addresses.csv**
```
address_id,customer_id,label,line1,city_id,pincode,is_default
1,1,HOME,"Flat 101, Station Road",2,400007,t
3,2,HOME,"Flat 102, Park Street",4,500014,t
```

**orders.csv**
```
order_id,customer_id,address_id,ordered_at,payment_method,total_amount,status,shipped_at,delivered_at
1,8181,16361,2025-01-01 00:00:00+05:30,CARD,31084.00,DELIVERED,2025-01-01 18:00:00+05:30,2025-01-04 19:00:00+05:30
2,15765,31529,2025-01-01 00:06:33+05:30,GIFT_CARD,42814.00,DELIVERED,2025-01-01 16:06:33+05:30,2025-01-04 13:06:33+05:30
```

**order_items.csv**
```
order_id,line_no,product_id,seller_id,quantity,unit_price
1,1,6245,313,1,28864.00
1,2,3646,183,2,1110.00
```

**returns.csv**
```
return_id,order_id,line_no,reason,requested_at,status,refund_amount
1,8,1,QUALITY_ISSUE,2025-01-10 13:04:14+05:30,REQUESTED,
2,22,1,WRONG_ITEM,2025-01-09 15:04:36+05:30,REJECTED,
```

**product_reviews.csv**
```
review_id,product_id,customer_id,rating,title,body,verified_purchase,helpful_votes,created_at
1,5768,4360,4,Good quality,Fabric quality is good,t,66,2025-01-07 02:05:07+05:30
2,7215,16945,3,Excellent product,,t,214,2025-01-07 04:43:54+05:30
```

**cart_items.csv**
```
customer_id,product_id,quantity,added_at
1,4849,2,2026-03-22 13:40:52+05:30
1,26738,3,2026-03-09 15:04:39+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, timestamps with a time-zone offset, yes/no columns, small whole numbers, decimals and short codes.
3. **Primary key.** Is it one column, or a combination? (Look closely at `order_items`, `cart_items`, and how `returns` points to an order line.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why**, and decide which columns must never be empty. Why do some orders have no `address_id`? Look at the categories of their products. Also look at `prime_since`, `shipped_at`, `delivered_at` and `refund_amount`.
6. **UNIQUE** columns (natural candidate keys such as emails, phone numbers, codes and handles).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Look for allowed values (statuses, payment methods, address labels, return reasons), formats (GSTIN, ASIN, pincode), price rules (price vs MRP), and rules that tie columns together (e.g. Prime flag vs `prime_since`, a refund amount only when refunded, at most one default address per customer).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: `products.avg_rating`/`review_count` vs `product_reviews`; `order_items.seller_id` vs `products`; `orders.total_amount` vs `order_items`) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`amazon`**: `CREATE SCHEMA amazon;` and `SET search_path TO amazon;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO amazon;
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
-- ... the other tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "`order_items.seller_id` always matches the product's seller", "every customer has exactly one default address", "orders without an address contain only digital products"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 11 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 24 reads (`R01`–`R24`) and 6 writes (`W01`–`W06`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W06`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **several seconds** on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Search box: active products whose title contains "wireless", best rated first | READ | | | | |
| R02: Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000 | READ | | | | |
| R03: Product page: rating breakdown (how many 5★, 4★ …) for product 4321 | READ | | | | |
| R04: "Your Orders": customer 1042's orders with the number of items in each | READ | | | | |
| R05: Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026) | READ | | | | |
| R06: Seller Central: seller 217's order lines in June 2026 | READ | | | | |
| R07: Seller Central: seller 217's products that are low on stock | READ | | | | |
| R08: Merchandising: top 5 best-selling products in every sub-category, last 30 days | READ | | | | |
| R09: Prime team: average order value of Prime vs non-Prime customers per month in 2026 | READ | | | | |
| R10: Marketing: carts untouched since May 2026 whose owner has not ordered since then | READ | | | | |
| R11: Product page: "Frequently bought together" with product 4321 | READ | | | | |
| R12: Category managers: return rate per top-level category | READ | | | | |
| R13: Data clean-up: saved addresses that have never been used for any order | READ | | | | |
| R14: Deals page: active products selling at less than half of MRP, biggest discount first | READ | | | | |
| R15: Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026 | READ | | | | |
| R16: Review insights: Electronics reviews that mention the battery | READ | | | | |
| R17: Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer | READ | | | | |
| R18: Customer analytics: Mumbai customers split into 4 spending tiers (2026) | READ | | | | |
| R19: Category report: every Mobile phone with its last sale date and units sold (all time) | READ | | | | |
| R20: Finance: daily sales (GMV) and running total for June 2026 | READ | | | | |
| R21: Logistics: deliveries in June 2026 that took more than 5 days | READ | | | | |
| R22: Admin: "All orders", newest first, page 3,001 (25 rows per page) | READ | | | | |
| R23: Order details page: one order with its lines, products and sellers | READ | | | | |
| R24: Product lookup by ASIN (barcode scanner in the warehouse) | READ | | | | |
| W01: Checkout: create a new order (header row) | WRITE | | | | |
| W02: Checkout: reduce stock of product 4322 after a sale | WRITE | | | | |
| W03: Seller Central: 10% price cut on all of seller 217's Watches | WRITE | | | | |
| W04: Big sale: 5,000 "add to cart" events loaded in one batch | WRITE | | | | |
| W05: Logistics: mark the oldest packed order as shipped | WRITE | | | | |
| W06: Nightly clean-up: remove cart items older than 90 days | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN index | for `ILIKE '%text%'` (extension `pg_trgm`), arrays or full-text search |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination; `UNION ALL` instead of `OR` across columns |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule about NULLs. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R04 | | e.g. Seq Scan on 120k orders | e.g. index on `orders(customer_id, ordered_at DESC)` | | e.g. 98.9% (90×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which write queries got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 120,000 orders. Next year the business expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 11 CSV files with about **20× the rows** (≈ 2,400,000 orders, ≈ 4,800,000 order items, ≈ 600,000 products, ≈ 600,000 customers). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them could run for a very long time.
   - R22 pages with `OFFSET`; if you replaced it with keyset pagination, explain how the "last seen" value is chosen for the large data.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / customer-facing | R03, R04, R05, R07, R11, R23, R24, W01, W02, W03, W05 | **under 5 ms** |
| Interactive search and seller tools | R01, R02, R06, R13, R14, R16, R21, R22 | **under 250 ms** |
| Reports and analytics | R08, R09, R10, R12, R15, R17, R18, R19, R20 | **under 5,000 ms** |
| Batch jobs | W04, W06 | **under 2,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100×:** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `orders`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** Would you shard by customer, by seller, or by order? Think about which side of R04 (customer view) and R06 (seller view) becomes cross-shard. Which queries become cross-shard, and how would you handle them?
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `orders`, archiving old data, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
amazon-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Mon 2 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (100 marks)

| Phase | Criteria | Marks |
|-------|----------|------:|
| 1 | Problems understood, stakeholders and query groups correctly identified | 5 |
| 2 | Correct data types (6), keys and foreign keys with justified delete rules (6), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (6), ER diagram + normal-form analysis (4), data loads cleanly + integrity checks (3) | 25 |
| 3 | All 30 queries measured with the required method (8), raw plans committed (3), scan type and reason for each query (4) | 15 |
| 4 | Speed-up achieved with appropriate techniques (12), every index justified (5), results proven unchanged (4), wrong-result query found and explained (4), write overhead and index storage reported (5) | 30 |
| 5 | Large-dataset results with all targets met or explained (8), growth analysis (6), scale-only problems found and fixed (5), partitioning DDL + sharding/replica design backed by your numbers (6) | 25 |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Search box: active products whose title contains "wireless", best rated first**
```sql
SELECT product_id, title, price, avg_rating, review_count
FROM products
WHERE title ILIKE '%wireless%' AND status = 'ACTIVE'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 24;
```

**R02: Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000**
```sql
WITH RECURSIVE tree AS (
    SELECT category_id FROM categories WHERE category_name = 'Electronics'
    UNION ALL
    SELECT c.category_id FROM categories c JOIN tree t ON c.parent_category_id = t.category_id
)
SELECT p.product_id, p.title, p.price
FROM products p
WHERE p.category_id IN (SELECT category_id FROM tree)
  AND p.price BETWEEN 1000 AND 5000
  AND p.status = 'ACTIVE'
ORDER BY p.price
LIMIT 48;
```

**R03: Product page: rating breakdown (how many 5★, 4★ …) for product 4321**
```sql
SELECT rating, count(*) AS reviews
FROM product_reviews
WHERE product_id = 4321
GROUP BY rating
ORDER BY rating DESC;
```

**R04: "Your Orders": customer 1042's orders with the number of items in each**
```sql
SELECT o.order_id, o.ordered_at, o.status, o.total_amount, count(oi.line_no) AS items
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.ordered_at, o.status, o.total_amount
ORDER BY o.ordered_at DESC;
```

**R05: Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026)**
```sql
SELECT order_id, customer_id, shipped_at
FROM orders
WHERE status = 'SHIPPED'
  AND shipped_at < '2026-06-20'
ORDER BY shipped_at;
```

**R06: Seller Central: seller 217's order lines in June 2026**
```sql
SELECT o.order_id, o.ordered_at, oi.product_id, oi.quantity, oi.unit_price
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE oi.seller_id = 217
  AND date_trunc('month', o.ordered_at) = '2026-06-01'
ORDER BY o.ordered_at;
```

**R07: Seller Central: seller 217's products that are low on stock**
```sql
SELECT product_id, title, stock_qty, status
FROM products
WHERE seller_id = 217
  AND stock_qty <= 20
  AND status IN ('ACTIVE', 'OUT_OF_STOCK')
ORDER BY stock_qty;
```

**R08: Merchandising: top 5 best-selling products in every sub-category, last 30 days**
```sql
SELECT *
FROM (
    SELECT p.category_id, oi.product_id, sum(oi.quantity) AS units,
           RANK() OVER (PARTITION BY p.category_id ORDER BY sum(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.ordered_at >= '2026-06-01'
      AND o.status NOT IN ('CANCELLED')
    GROUP BY p.category_id, oi.product_id
) t
WHERE rnk <= 5
ORDER BY category_id, rnk;
```

**R09: Prime team: average order value of Prime vs non-Prime customers per month in 2026**
```sql
SELECT date_trunc('month', o.ordered_at) AS month, c.is_prime,
       count(*) AS orders, round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE EXTRACT(YEAR FROM o.ordered_at) = 2026
  AND o.status <> 'CANCELLED'
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R10: Marketing: carts untouched since May 2026 whose owner has not ordered since then**
```sql
SELECT ci.customer_id, count(*) AS items, sum(ci.quantity * p.price) AS cart_value
FROM cart_items ci
JOIN products p ON p.product_id = ci.product_id
WHERE ci.added_at < '2026-05-01'
  AND NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customer_id = ci.customer_id AND o.ordered_at >= '2026-05-01')
GROUP BY ci.customer_id
ORDER BY cart_value DESC
LIMIT 100;
```

**R11: Product page: "Frequently bought together" with product 4321**
```sql
SELECT b.product_id, count(*) AS times_together
FROM order_items a
JOIN order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
WHERE a.product_id = 4321
GROUP BY b.product_id
ORDER BY times_together DESC
LIMIT 10;
```

**R12: Category managers: return rate per top-level category**
```sql
SELECT top.category_name,
       count(oi.*) AS lines_sold,
       count(r.return_id) AS lines_returned,
       round(100.0 * count(r.return_id) / count(oi.*), 2) AS return_pct
FROM order_items oi
JOIN products p     ON p.product_id = oi.product_id
JOIN categories sub ON sub.category_id = p.category_id
JOIN categories top ON top.category_id = sub.parent_category_id
LEFT JOIN returns r ON r.order_id = oi.order_id AND r.line_no = oi.line_no
GROUP BY top.category_name
ORDER BY return_pct DESC;
```

**R13: Data clean-up: saved addresses that have never been used for any order**
```sql
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o);
```

**R14: Deals page: active products selling at less than half of MRP, biggest discount first**
```sql
SELECT product_id, title, mrp, price, round(100 * (1 - price / mrp), 1) AS discount_pct
FROM products
WHERE price < mrp * 0.5 AND status = 'ACTIVE'
ORDER BY price / mrp
LIMIT 50;
```

**R15: Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026**
```sql
SELECT s.seller_id, s.business_name, count(*) AS lines_sold, sum(oi.quantity * oi.unit_price) AS revenue
FROM sellers s
JOIN order_items oi ON oi.seller_id = s.seller_id
JOIN orders o       ON o.order_id = oi.order_id
WHERE o.ordered_at >= '2026-01-01' AND o.status IN ('DELIVERED', 'SHIPPED', 'OUT_FOR_DELIVERY')
GROUP BY s.seller_id, s.business_name
HAVING count(*) >= 50
ORDER BY revenue DESC
LIMIT 20;
```

**R16: Review insights: Electronics reviews that mention the battery**
```sql
SELECT r.review_id, r.product_id, r.rating, r.body
FROM product_reviews r
JOIN products p     ON p.product_id = r.product_id
JOIN categories c   ON c.category_id = p.category_id
WHERE c.parent_category_id = 1
  AND r.body ILIKE '%battery%'
ORDER BY r.created_at DESC
LIMIT 50;
```

**R17: Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer**
```sql
SELECT r.review_id, r.product_id, r.customer_id
FROM product_reviews r
WHERE r.verified_purchase
  AND NOT EXISTS (SELECT 1
                  FROM orders o
                  JOIN order_items oi ON oi.order_id = o.order_id
                  WHERE o.customer_id = r.customer_id
                    AND oi.product_id = r.product_id
                    AND o.status IN ('DELIVERED', 'RETURNED'));
```

**R18: Customer analytics: Mumbai customers split into 4 spending tiers (2026)**
```sql
SELECT customer_id, total_spend, NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_tier
FROM (
    SELECT o.customer_id, sum(o.total_amount) AS total_spend
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.city_id = 2 AND o.ordered_at >= '2026-01-01' AND o.status = 'DELIVERED'
    GROUP BY o.customer_id
) t
ORDER BY spend_tier, total_spend DESC;
```

**R19: Category report: every Mobile phone with its last sale date and units sold (all time)**
```sql
SELECT p.product_id, p.title,
       (SELECT max(o.ordered_at) FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
         WHERE oi.product_id = p.product_id) AS last_sold_at,
       (SELECT coalesce(sum(oi.quantity), 0) FROM order_items oi WHERE oi.product_id = p.product_id) AS units_sold
FROM products p
WHERE p.category_id = (SELECT category_id FROM categories WHERE category_name = 'Mobiles')
ORDER BY units_sold DESC, p.product_id;
```

**R20: Finance: daily sales (GMV) and running total for June 2026**
```sql
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT ordered_at::date AS day, sum(total_amount) AS gmv
    FROM orders
    WHERE status <> 'CANCELLED'
      AND ordered_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**R21: Logistics: deliveries in June 2026 that took more than 5 days**
```sql
SELECT order_id, customer_id, ordered_at, delivered_at
FROM orders
WHERE delivered_at > ordered_at + interval '5 days'
  AND ordered_at >= '2026-06-01'
ORDER BY delivered_at - ordered_at DESC;
```

**R22: Admin: "All orders", newest first, page 3,001 (25 rows per page)**
```sql
SELECT order_id, customer_id, status, total_amount, ordered_at
FROM orders
ORDER BY ordered_at DESC
OFFSET 75000
LIMIT 25;
```

**R23: Order details page: one order with its lines, products and sellers**
```sql
SELECT o.order_id, o.ordered_at, o.status, oi.line_no, p.title, s.business_name, oi.quantity, oi.unit_price
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
JOIN sellers s      ON s.seller_id = oi.seller_id
WHERE o.order_id = 100001
ORDER BY oi.line_no;
```

**R24: Product lookup by ASIN (barcode scanner in the warehouse)**
```sql
SELECT product_id, title, seller_id, stock_qty
FROM products
WHERE asin = 'B0020A200F';
```

**W01: Checkout: create a new order (header row)**
```sql
INSERT INTO orders (order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status)
VALUES (90000001, 1042, 2083, '2026-07-01 10:30:00+05:30', 'UPI', 3935.00, 'PLACED');
```

**W02: Checkout: reduce stock of product 4322 after a sale**
```sql
UPDATE products
SET stock_qty = stock_qty - 1
WHERE product_id = 4322 AND stock_qty >= 1;
```

**W03: Seller Central: 10% price cut on all of seller 217's Watches**
```sql
UPDATE products p
SET price = round(p.price * 0.90, 0)
FROM categories c
WHERE c.category_id = p.category_id
  AND c.category_name = 'Watches'
  AND p.seller_id = 217;
```

**W04: Big sale: 5,000 "add to cart" events loaded in one batch**
```sql
INSERT INTO cart_items (customer_id, product_id, quantity, added_at)
SELECT 1 + (g * 7) % 30000, 1 + (g * 13) % 30000, 1, TIMESTAMPTZ '2026-07-01 00:00:00+05:30' + g * interval '1 second'
FROM generate_series(1, 5000) AS g
ON CONFLICT (customer_id, product_id) DO NOTHING;
```

**W05: Logistics: mark the oldest packed order as shipped**
```sql
UPDATE orders
SET status = 'SHIPPED', shipped_at = ordered_at + interval '6 hours'
WHERE order_id = (SELECT min(order_id) FROM orders WHERE status = 'PACKED');
```

**W06: Nightly clean-up: remove cart items older than 90 days**
```sql
DELETE FROM cart_items
WHERE added_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '90 days';
```
