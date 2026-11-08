-- =============================================================================
-- Amazon Online Shopping — Seed Data Loader
-- File        : sql/02_load_data.sql
-- Phase       : 2 — Schema Design
-- Description : Truncates all 11 tables and reloads them from seed_data/ CSVs.
--               Run from the repository root with:
--                   psql -d <database> -f sql/02_load_data.sql
--               The \copy paths are relative to the directory psql is invoked
--               from (the repo root), so seed_data/filename.csv is correct.
-- =============================================================================

SET search_path TO amazon;

-- ---------------------------------------------------------------------------
-- Step 1: Truncate in reverse dependency order (children first)
--         CASCADE handles any residual FK chains.
-- ---------------------------------------------------------------------------
TRUNCATE amazon.returns          CASCADE;
TRUNCATE amazon.product_reviews  CASCADE;
TRUNCATE amazon.cart_items       CASCADE;
TRUNCATE amazon.order_items      CASCADE;
TRUNCATE amazon.orders           CASCADE;
TRUNCATE amazon.products         CASCADE;
TRUNCATE amazon.addresses        CASCADE;
TRUNCATE amazon.sellers          CASCADE;
TRUNCATE amazon.customers        CASCADE;
TRUNCATE amazon.categories       CASCADE;
TRUNCATE amazon.cities           CASCADE;

-- ---------------------------------------------------------------------------
-- Step 2: Load in dependency order (parents first)
-- ---------------------------------------------------------------------------

-- 1. cities (no dependencies)
\copy amazon.cities FROM 'seed_data/cities.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 2. categories (self-referencing; file must be ordered parent-before-child)
\copy amazon.categories FROM 'seed_data/categories.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 3. sellers (depends on cities)
\copy amazon.sellers FROM 'seed_data/sellers.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 4. customers (depends on cities)
\copy amazon.customers FROM 'seed_data/customers.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 5. addresses (depends on customers, cities)
\copy amazon.addresses FROM 'seed_data/addresses.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 6. products (depends on sellers, categories)
\copy amazon.products FROM 'seed_data/products.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 7. orders (depends on customers, addresses)
\copy amazon.orders FROM 'seed_data/orders.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 8. order_items (depends on orders, products, sellers)
\copy amazon.order_items FROM 'seed_data/order_items.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 9. cart_items (depends on customers, products)
\copy amazon.cart_items FROM 'seed_data/cart_items.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 10. product_reviews (depends on products, customers)
\copy amazon.product_reviews FROM 'seed_data/product_reviews.csv' WITH (FORMAT CSV, HEADER TRUE);

-- 11. returns (depends on order_items)
\copy amazon.returns FROM 'seed_data/returns.csv' WITH (FORMAT CSV, HEADER TRUE);

-- ---------------------------------------------------------------------------
-- Step 3: Quick sanity-check row counts
-- ---------------------------------------------------------------------------
SELECT 'cities'          AS tbl, count(*) AS rows FROM amazon.cities
UNION ALL
SELECT 'categories',              count(*)         FROM amazon.categories
UNION ALL
SELECT 'sellers',                 count(*)         FROM amazon.sellers
UNION ALL
SELECT 'customers',               count(*)         FROM amazon.customers
UNION ALL
SELECT 'addresses',               count(*)         FROM amazon.addresses
UNION ALL
SELECT 'products',                count(*)         FROM amazon.products
UNION ALL
SELECT 'orders',                  count(*)         FROM amazon.orders
UNION ALL
SELECT 'order_items',             count(*)         FROM amazon.order_items
UNION ALL
SELECT 'cart_items',              count(*)         FROM amazon.cart_items
UNION ALL
SELECT 'product_reviews',         count(*)         FROM amazon.product_reviews
UNION ALL
SELECT 'returns',                 count(*)         FROM amazon.returns
ORDER BY tbl;

-- =============================================================================
-- End of 02_load_data.sql
-- =============================================================================
