-- =============================================================================
-- Amazon Online Shopping — Database Indexes
-- File        : sql/05_indexes.sql
-- Phase       : 4 — Optimization
-- Description : Secondary B-tree, composite, partial, expression, and GIN indexes
--               designed to optimize the 30-query workload without changing results.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS amazon;
SET search_path TO amazon;

-- Enable trigram extension in amazon schema for fast ILIKE substring search
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA amazon;

-- -----------------------------------------------------------------------------
-- 1. FOREIGN KEY & JOIN INDEXES (B-tree)
-- -----------------------------------------------------------------------------

-- idx_categories_parent_id
-- Target: R02, R12, R16 (hierarchical category tree navigation)
-- Table : categories (parent_category_id)
CREATE INDEX IF NOT EXISTS idx_categories_parent_id
    ON categories (parent_category_id);

-- idx_customers_city_id
-- Target: R18 (filter Mumbai customers: c.city_id = 2)
-- Table : customers (city_id)
CREATE INDEX IF NOT EXISTS idx_customers_city_id
    ON customers (city_id);

-- idx_addresses_customer_id
-- Target: FK lookups from customers to saved addresses
-- Table : addresses (customer_id)
CREATE INDEX IF NOT EXISTS idx_addresses_customer_id
    ON addresses (customer_id);

-- idx_products_category_id
-- Target: R02, R08, R12, R16, R19 (joining products to category tree)
-- Table : products (category_id)
CREATE INDEX IF NOT EXISTS idx_products_category_id
    ON products (category_id);

-- idx_products_seller_id
-- Target: R07, W03 (FK lookups by vendor)
-- Table : products (seller_id)
CREATE INDEX IF NOT EXISTS idx_products_seller_id
    ON products (seller_id);

-- idx_orders_customer_ordered_at
-- Target: R04, R09, R10, R17, R18 (lookups of orders by customer)
-- Composite with ordered_at DESC for order history navigation
CREATE INDEX IF NOT EXISTS idx_orders_customer_ordered_at
    ON orders (customer_id, ordered_at DESC);

-- idx_orders_address_id
-- Target: R13 (anti-join for unused addresses: WHERE address_id IS NOT NULL)
-- Table : orders (address_id)
CREATE INDEX IF NOT EXISTS idx_orders_address_id
    ON orders (address_id)
    WHERE address_id IS NOT NULL;

-- idx_order_items_product_order
-- Target: R08, R11, R12, R17, R19 (frequently bought together, top sellers, category reports)
-- Table : order_items (product_id, order_id)
CREATE INDEX IF NOT EXISTS idx_order_items_product_order
    ON order_items (product_id, order_id);

-- idx_order_items_seller_order
-- Target: R06, R15 (seller central order items in date ranges)
-- Table : order_items (seller_id, order_id)
CREATE INDEX IF NOT EXISTS idx_order_items_seller_order
    ON order_items (seller_id, order_id);

-- idx_cart_items_product_id
-- Target: R10, W04 (FK constraint enforcement and join with products)
-- Table : cart_items (product_id)
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id
    ON cart_items (product_id);

-- idx_returns_order_line
-- Target: R12 (LEFT JOIN returns ON order_id, line_no)
-- Table : returns (order_id, line_no)
CREATE UNIQUE INDEX IF NOT EXISTS idx_returns_order_line
    ON returns (order_id, line_no);

-- idx_product_reviews_customer_product
-- Target: R17 (reviews lookup by customer and product)
-- Table : product_reviews (customer_id, product_id)
CREATE INDEX IF NOT EXISTS idx_product_reviews_customer_product
    ON product_reviews (customer_id, product_id);


-- -----------------------------------------------------------------------------
-- 2. COMPOSITE & COVERING INDEXES (B-tree)
-- -----------------------------------------------------------------------------

-- idx_products_category_price
-- Target: R02 (category browse with price range ₹1,000–₹5,000)
-- Equality column (category_id) first, range column (price) second
CREATE INDEX IF NOT EXISTS idx_products_category_price
    ON products (category_id, price)
    WHERE status = 'ACTIVE';

-- idx_products_seller_stock
-- Target: R07 (seller low-stock alerts)
-- Equality column (seller_id) first, range column (stock_qty) second
CREATE INDEX IF NOT EXISTS idx_products_seller_stock
    ON products (seller_id, stock_qty)
    WHERE status IN ('ACTIVE', 'OUT_OF_STOCK');

-- idx_product_reviews_product_rating
-- Target: R03 (product page rating breakdown)
-- Covering index allowing Index Only Scan Backward on product_id = X
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_rating
    ON product_reviews (product_id, rating);

-- idx_orders_ordered_at_desc
-- Target: R22 (deep pagination on orders sorted newest first)
-- Table : orders (ordered_at DESC)
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at_desc
    ON orders (ordered_at DESC);

-- idx_orders_ordered_at_active
-- Target: R08, R20, R21 (date range queries on active orders in June/2026)
-- Filter out CANCELLED orders
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at_active
    ON orders (ordered_at)
    WHERE status <> 'CANCELLED';

-- idx_cart_items_added_at
-- Target: R10, W06 (abandoned cart marketing and nightly cleanup)
-- Table : cart_items (added_at)
CREATE INDEX IF NOT EXISTS idx_cart_items_added_at
    ON cart_items (added_at);


-- -----------------------------------------------------------------------------
-- 3. PARTIAL INDEXES (B-tree)
-- -----------------------------------------------------------------------------

-- idx_orders_shipped
-- Target: R05 (logistics: shipments in transit > 10 days)
-- Indexes only rows with status = 'SHIPPED', includes customer_id for Index Only Scan
CREATE INDEX IF NOT EXISTS idx_orders_shipped
    ON orders (shipped_at)
    INCLUDE (customer_id, order_id)
    WHERE status = 'SHIPPED';

-- idx_orders_packed_min
-- Target: W05 (logistics: find minimum order_id with status = 'PACKED')
-- Tiny partial index allowing instant sub-millisecond MIN(order_id) lookup
CREATE INDEX IF NOT EXISTS idx_orders_packed_min
    ON orders (order_id)
    WHERE status = 'PACKED';

-- idx_reviews_verified
-- Target: R17 (trust & safety: verified purchase review validation)
-- Filters strictly to verified_purchase = TRUE
CREATE INDEX IF NOT EXISTS idx_reviews_verified
    ON product_reviews (customer_id, product_id)
    WHERE verified_purchase = TRUE;


-- -----------------------------------------------------------------------------
-- 4. EXPRESSION INDEXES (B-tree)
-- -----------------------------------------------------------------------------

-- idx_products_discount_pct
-- Target: R14 (deals page: products with discount > 50%, sorted by price / mrp)
-- Precomputes expression (price / mrp) avoiding table scan and sort node
CREATE INDEX IF NOT EXISTS idx_products_discount_pct
    ON products ((price / mrp))
    WHERE status = 'ACTIVE' AND price < mrp * 0.5;


-- -----------------------------------------------------------------------------
-- 5. TRIGRAM / GIN INDEXES (pg_trgm)
-- -----------------------------------------------------------------------------

-- idx_products_title_trgm
-- Target: R01 (search box: title ILIKE '%wireless%')
-- Inverted trigram index enabling Bitmap Index Scan for substring matching
CREATE INDEX IF NOT EXISTS idx_products_title_trgm
    ON products USING gin (title gin_trgm_ops);

-- idx_product_reviews_body_trgm
-- Target: R16 (review insights: body ILIKE '%battery%')
-- Inverted trigram index enabling Bitmap Index Scan on review text
CREATE INDEX IF NOT EXISTS idx_product_reviews_body_trgm
    ON product_reviews USING gin (body gin_trgm_ops);


-- -----------------------------------------------------------------------------
-- 6. FRESH STATISTICS
-- -----------------------------------------------------------------------------
ANALYZE;
