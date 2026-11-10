-- =============================================================================
-- Amazon Online Shopping — PostgreSQL DDL
-- File        : sql/01_schema.sql
-- Phase       : 2 — Schema Design
-- Description : Creates all 11 tables in the amazon schema.
--               Indexes are intentionally omitted here; see sql/05_indexes.sql.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS amazon;
SET search_path TO amazon;

-- ---------------------------------------------------------------------------
-- 1. cities
--    Root lookup table; no foreign-key dependencies.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cities (
    city_id   INTEGER      PRIMARY KEY,
    city_name TEXT         NOT NULL,
    state     TEXT         NOT NULL
);

COMMENT ON TABLE  cities          IS 'Master list of cities used by customers, sellers, and addresses.';
COMMENT ON COLUMN cities.city_id  IS 'Surrogate primary key.';
COMMENT ON COLUMN cities.state    IS 'Indian state name.';

-- ---------------------------------------------------------------------------
-- 2. categories
--    Self-referencing tree; root nodes have parent_category_id = NULL.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
    category_id        INTEGER  PRIMARY KEY,
    category_name      TEXT     NOT NULL,
    parent_category_id INTEGER  REFERENCES categories(category_id) ON DELETE SET NULL,
    is_digital         BOOLEAN  NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE  categories                   IS 'Product category tree (e.g. Electronics → Mobiles).';
COMMENT ON COLUMN categories.parent_category_id IS 'NULL for top-level categories; references parent node.';
COMMENT ON COLUMN categories.is_digital         IS 'TRUE for digital goods (e-books, gift cards) that need no shipping.';

-- ---------------------------------------------------------------------------
-- 3. sellers
--    Depends on cities.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sellers (
    seller_id     INTEGER        PRIMARY KEY,
    business_name TEXT           NOT NULL,
    gstin         TEXT           UNIQUE,          -- nullable until GST verified
    city_id       INTEGER        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    joined_on     DATE           NOT NULL,
    seller_rating NUMERIC(3,2)   CHECK (seller_rating BETWEEN 0 AND 5),
    status        TEXT           NOT NULL
                                 CHECK (status IN ('ACTIVE', 'INACTIVE', 'CLOSED', 'SUSPENDED'))
);

COMMENT ON TABLE  sellers             IS 'Marketplace seller accounts.';
COMMENT ON COLUMN sellers.gstin       IS '15-character GST Identification Number; unique when present.';
COMMENT ON COLUMN sellers.seller_rating IS 'Aggregate rating 0–5 maintained by the application.';

-- ---------------------------------------------------------------------------
-- 4. customers
--    Depends on cities.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    customer_id  INTEGER  PRIMARY KEY,
    full_name    TEXT     NOT NULL,
    email        TEXT     NOT NULL UNIQUE,
    phone        TEXT,
    city_id      INTEGER  NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    signup_date  DATE     NOT NULL,
    is_prime     BOOLEAN  NOT NULL DEFAULT FALSE,
    prime_since  DATE     -- NULL when is_prime = FALSE
);

COMMENT ON TABLE  customers             IS 'Registered buyer accounts.';
COMMENT ON COLUMN customers.email       IS 'Login identifier; must be unique across all accounts.';
COMMENT ON COLUMN customers.is_prime    IS 'Whether the customer currently holds an active Prime membership.';
COMMENT ON COLUMN customers.prime_since IS 'Date Prime membership first activated; NULL if never Prime.';

-- ---------------------------------------------------------------------------
-- 5. addresses
--    Depends on customers, cities.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS addresses (
    address_id  INTEGER  PRIMARY KEY,
    customer_id INTEGER  NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    label       TEXT     NOT NULL
                         CHECK (label IN ('HOME', 'WORK', 'OTHER')),
    line1       TEXT     NOT NULL,
    city_id     INTEGER  NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    pincode     TEXT     NOT NULL,              -- TEXT to preserve leading zeros
    is_default  BOOLEAN  NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE  addresses            IS 'Saved delivery addresses per customer.';
COMMENT ON COLUMN addresses.label      IS 'Friendly label: HOME, WORK, or OTHER.';
COMMENT ON COLUMN addresses.pincode    IS 'Indian 6-digit postal code stored as TEXT.';
COMMENT ON COLUMN addresses.is_default IS 'Pre-selected address at checkout.';

-- ---------------------------------------------------------------------------
-- 6. products
--    Depends on sellers, categories.
--    avg_rating and review_count are denormalized for fast product-page reads.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
    product_id        INTEGER         PRIMARY KEY,
    asin              TEXT            NOT NULL UNIQUE,  -- R24: warehouse barcode lookup
    seller_id         INTEGER         NOT NULL REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    category_id       INTEGER         NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
    title             TEXT            NOT NULL,
    brand             TEXT,
    mrp               NUMERIC(12,2)   NOT NULL CHECK (mrp > 0),
    price             NUMERIC(12,2)   NOT NULL CHECK (price > 0),
    stock_qty         INTEGER         NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    is_prime_eligible BOOLEAN         NOT NULL DEFAULT FALSE,
    avg_rating        NUMERIC(3,2)    CHECK (avg_rating BETWEEN 0 AND 5),  -- denormalized
    review_count      INTEGER         NOT NULL DEFAULT 0,                   -- denormalized
    listed_on         DATE            NOT NULL,
    status            TEXT            NOT NULL
                                      CHECK (status IN ('ACTIVE', 'INACTIVE', 'OUT_OF_STOCK', 'DELETED'))
);

COMMENT ON TABLE  products                 IS 'Product listings by sellers.';
COMMENT ON COLUMN products.asin            IS 'Amazon Standard Identification Number; globally unique.';
COMMENT ON COLUMN products.mrp             IS 'Maximum Retail Price (INR).';
COMMENT ON COLUMN products.price           IS 'Current selling price (INR); should be <= mrp.';
COMMENT ON COLUMN products.avg_rating      IS 'Denormalized average rating; updated after each review insert.';
COMMENT ON COLUMN products.review_count    IS 'Denormalized count of reviews; updated after each review insert.';
COMMENT ON COLUMN products.is_prime_eligible IS 'Whether this listing qualifies for Prime fast delivery.';

-- ---------------------------------------------------------------------------
-- 7. orders
--    Depends on customers, addresses.
--    address_id is nullable for digital-only orders (no shipping required).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
    order_id       INTEGER         PRIMARY KEY,
    customer_id    INTEGER         NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id     INTEGER         REFERENCES addresses(address_id) ON DELETE SET NULL,  -- nullable for digital
    ordered_at     TIMESTAMPTZ     NOT NULL,
    payment_method TEXT            NOT NULL
                                   CHECK (payment_method IN ('CARD','UPI','GIFT_CARD','COD','NETBANKING','NET_BANKING','WALLET','EMI')),
    total_amount   NUMERIC(12,2)   NOT NULL CHECK (total_amount >= 0),
    status         TEXT            NOT NULL
                                   CHECK (status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY',
                                                     'DELIVERED','CANCELLED','RETURNED')),
    shipped_at     TIMESTAMPTZ,    -- NULL until shipped
    delivered_at   TIMESTAMPTZ     -- NULL until delivered
);

COMMENT ON TABLE  orders                IS 'Customer purchase orders (header record).';
COMMENT ON COLUMN orders.address_id     IS 'NULL for digital-only orders requiring no physical delivery.';
COMMENT ON COLUMN orders.payment_method IS 'Payment channel used at checkout.';
COMMENT ON COLUMN orders.total_amount   IS 'Total charged to the customer in INR.';
COMMENT ON COLUMN orders.shipped_at     IS 'Timestamp when the order was handed to logistics; NULL if not yet shipped.';
COMMENT ON COLUMN orders.delivered_at   IS 'Timestamp of delivery confirmation; NULL if not yet delivered.';

-- ---------------------------------------------------------------------------
-- 8. order_items
--    Depends on orders, products, sellers.
--    Composite PK (order_id, line_no); unit_price is a snapshot at checkout time.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_items (
    order_id   INTEGER         NOT NULL REFERENCES orders(order_id)   ON DELETE CASCADE,
    line_no    SMALLINT        NOT NULL,
    product_id INTEGER         NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    seller_id  INTEGER         NOT NULL REFERENCES sellers(seller_id)  ON DELETE RESTRICT,
    quantity   SMALLINT        NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2)   NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, line_no)
);

COMMENT ON TABLE  order_items            IS 'Individual line items within an order.';
COMMENT ON COLUMN order_items.line_no    IS 'Sequential line number within the order (1-based).';
COMMENT ON COLUMN order_items.unit_price IS 'Price per unit locked at checkout; independent of current product price.';
COMMENT ON COLUMN order_items.seller_id  IS 'Seller at time of purchase; stored for billing integrity.';

-- ---------------------------------------------------------------------------
-- 9. cart_items
--    Depends on customers, products.
--    Composite PK (customer_id, product_id) enforces one row per customer-product.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cart_items (
    customer_id INTEGER      NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    product_id  INTEGER      NOT NULL REFERENCES products(product_id)  ON DELETE CASCADE,
    quantity    SMALLINT     NOT NULL CHECK (quantity > 0),
    added_at    TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (customer_id, product_id)
);

COMMENT ON TABLE  cart_items           IS 'Active shopping cart — one row per customer-product pair.';
COMMENT ON COLUMN cart_items.added_at  IS 'Timestamp used for abandoned-cart age calculations.';

-- ---------------------------------------------------------------------------
-- 10. product_reviews
--     Depends on products, customers.
--     body column will carry a GIN trigram index for ILIKE text search (Phase 4).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product_reviews (
    review_id         INTEGER      PRIMARY KEY,
    product_id        INTEGER      NOT NULL REFERENCES products(product_id)  ON DELETE CASCADE,
    customer_id       INTEGER      NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    rating            SMALLINT     NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title             TEXT,
    body              TEXT,
    verified_purchase BOOLEAN      NOT NULL DEFAULT FALSE,
    helpful_votes     INTEGER      NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ  NOT NULL
);

COMMENT ON TABLE  product_reviews                   IS 'Customer reviews for products.';
COMMENT ON COLUMN product_reviews.rating            IS 'Star rating 1–5.';
COMMENT ON COLUMN product_reviews.verified_purchase IS 'TRUE if the system confirmed a delivered order for this product.';
COMMENT ON COLUMN product_reviews.helpful_votes     IS 'Count of "helpful" upvotes from other customers.';
COMMENT ON COLUMN product_reviews.body              IS 'Full review text; GIN/pg_trgm index planned in 05_indexes.sql.';

-- ---------------------------------------------------------------------------
-- 11. returns
--     Depends on order_items (composite FK).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS returns (
    return_id     INTEGER         PRIMARY KEY,
    order_id      INTEGER         NOT NULL,
    line_no       SMALLINT        NOT NULL,
    reason        TEXT            NOT NULL
                                  CHECK (reason IN ('QUALITY_ISSUE','WRONG_ITEM',
                                                    'NOT_AS_DESCRIBED','CHANGED_MIND','DAMAGED',
                                                    'NO_LONGER_NEEDED','SIZE_ISSUE')),
    requested_at  TIMESTAMPTZ     NOT NULL,
    status        TEXT            NOT NULL
                                  CHECK (status IN ('REQUESTED','APPROVED','REJECTED','REFUNDED','PICKED_UP')),
    refund_amount NUMERIC(12,2)   CHECK (refund_amount >= 0),  -- NULL until refund issued
    FOREIGN KEY (order_id, line_no) REFERENCES order_items(order_id, line_no) ON DELETE RESTRICT
);

COMMENT ON TABLE  returns               IS 'Return requests raised against individual order line items.';
COMMENT ON COLUMN returns.reason        IS 'Customer-selected reason code for the return.';
COMMENT ON COLUMN returns.refund_amount IS 'Amount to be refunded (INR); NULL until REFUNDED status.';

-- =============================================================================
-- End of 01_schema.sql
-- Indexes (B-tree, partial, GIN) are defined in sql/05_indexes.sql.
-- =============================================================================
