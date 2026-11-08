# Phase 2 — Schema Design

**Course:** Database Management Systems · **Team:** T0063 · **Section:** C

---

## 1. Schema Overview

All 11 tables live in the PostgreSQL schema `amazon`. The schema was reverse-engineered entirely
from the 11 seed-data CSV files. Table dependency order (parent tables first):

```
cities → customers → addresses
       → sellers
       → (via products) categories → products
                                   → order_items ← orders ← customers
                                                           ← addresses
cart_items ← customers, products
product_reviews ← products, customers
returns ← order_items (order_id + line_no)
```

---

## 2. Tables — Columns, Types, and Constraints

### 2.1 `cities`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `city_id` | `INTEGER` | PK | Surrogate key |
| `city_name` | `TEXT` | NOT NULL | e.g., "Bengaluru" |
| `state` | `TEXT` | NOT NULL | e.g., "Karnataka" |

**Primary key:** `city_id`  
**Rows:** 10

---

### 2.2 `customers`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `customer_id` | `INTEGER` | PK | Surrogate key |
| `full_name` | `TEXT` | NOT NULL | |
| `email` | `TEXT` | NOT NULL, UNIQUE | Used for login |
| `phone` | `TEXT` | | Nullable |
| `city_id` | `INTEGER` | FK → cities, NOT NULL | Home city |
| `signup_date` | `DATE` | NOT NULL | |
| `is_prime` | `BOOLEAN` | NOT NULL, DEFAULT FALSE | Current membership status |
| `prime_since` | `DATE` | | NULL if not Prime |

**Primary key:** `customer_id`  
**Rows:** 30,000

---

### 2.3 `addresses`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `address_id` | `INTEGER` | PK | Surrogate key |
| `customer_id` | `INTEGER` | FK → customers NOT NULL | Owner |
| `label` | `TEXT` | NOT NULL, CHECK (label IN ('HOME','WORK','OTHER')) | Address nickname |
| `line1` | `TEXT` | NOT NULL | Street / apartment |
| `city_id` | `INTEGER` | FK → cities NOT NULL | Delivery city |
| `pincode` | `TEXT` | NOT NULL | 6-digit postal code (kept as TEXT to preserve leading zeros) |
| `is_default` | `BOOLEAN` | NOT NULL, DEFAULT FALSE | Pre-selected at checkout |

**Primary key:** `address_id`  
**Rows:** 45,000

---

### 2.4 `sellers`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `seller_id` | `INTEGER` | PK | Surrogate key |
| `business_name` | `TEXT` | NOT NULL | Display name |
| `gstin` | `TEXT` | UNIQUE | 15-char GST ID; nullable if not yet verified |
| `city_id` | `INTEGER` | FK → cities NOT NULL | Registered city |
| `joined_on` | `DATE` | NOT NULL | |
| `seller_rating` | `NUMERIC(3,2)` | CHECK (seller_rating BETWEEN 0 AND 5) | Avg rating 0–5 |
| `status` | `TEXT` | NOT NULL, CHECK (status IN ('ACTIVE','INACTIVE')) | Account state |

**Primary key:** `seller_id`  
**Rows:** 1,500

---

### 2.5 `categories`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `category_id` | `INTEGER` | PK | Surrogate key |
| `category_name` | `TEXT` | NOT NULL | |
| `parent_category_id` | `INTEGER` | FK → categories (self-ref), nullable | NULL for top-level |
| `is_digital` | `BOOLEAN` | NOT NULL, DEFAULT FALSE | e.g., e-books, gift cards |

**Primary key:** `category_id`  
**Design note:** Self-referencing FK enables the recursive CTE queries (P1). NULL parent_category_id
marks a root node.  
**Rows:** 40

---

### 2.6 `products`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `product_id` | `INTEGER` | PK | Surrogate key |
| `asin` | `TEXT` | NOT NULL, UNIQUE | Amazon Standard ID; used by warehouse (R24) |
| `seller_id` | `INTEGER` | FK → sellers NOT NULL | Listing seller |
| `category_id` | `INTEGER` | FK → categories NOT NULL | Leaf category |
| `title` | `TEXT` | NOT NULL | Full product title |
| `brand` | `TEXT` | | Nullable (some sellers have no brand) |
| `mrp` | `NUMERIC(12,2)` | NOT NULL, CHECK (mrp > 0) | Maximum retail price |
| `price` | `NUMERIC(12,2)` | NOT NULL, CHECK (price > 0) | Selling price (≤ mrp) |
| `stock_qty` | `INTEGER` | NOT NULL, DEFAULT 0, CHECK (stock_qty >= 0) | Current units available |
| `is_prime_eligible` | `BOOLEAN` | NOT NULL, DEFAULT FALSE | Visible under Prime filter |
| `avg_rating` | `NUMERIC(3,2)` | CHECK (avg_rating BETWEEN 0 AND 5) | **Denormalized** (see §3) |
| `review_count` | `INTEGER` | NOT NULL, DEFAULT 0 | **Denormalized** (see §3) |
| `listed_on` | `DATE` | NOT NULL | Date first listed |
| `status` | `TEXT` | NOT NULL, CHECK (status IN ('ACTIVE','INACTIVE','DELETED')) | Listing state |

**Primary key:** `product_id`  
**Rows:** 30,000

---

### 2.7 `orders`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `order_id` | `INTEGER` | PK | Surrogate key |
| `customer_id` | `INTEGER` | FK → customers NOT NULL | Buyer |
| `address_id` | `INTEGER` | FK → addresses | Nullable for digital-only orders |
| `ordered_at` | `TIMESTAMPTZ` | NOT NULL | Checkout timestamp |
| `payment_method` | `TEXT` | NOT NULL, CHECK (payment_method IN ('CARD','UPI','GIFT_CARD','COD','NET_BANKING','WALLET')) | |
| `total_amount` | `NUMERIC(12,2)` | NOT NULL, CHECK (total_amount >= 0) | Order total |
| `status` | `TEXT` | NOT NULL, CHECK (status IN ('PLACED','PACKED','SHIPPED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED','RETURNED')) | Lifecycle status |
| `shipped_at` | `TIMESTAMPTZ` | | NULL until shipped |
| `delivered_at` | `TIMESTAMPTZ` | | NULL until delivered |

**Primary key:** `order_id`  
**Rows:** 120,000

---

### 2.8 `order_items`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `order_id` | `INTEGER` | PK part 1, FK → orders | |
| `line_no` | `SMALLINT` | PK part 2 | Line number within order |
| `product_id` | `INTEGER` | FK → products NOT NULL | |
| `seller_id` | `INTEGER` | FK → sellers NOT NULL | Seller at time of purchase |
| `quantity` | `SMALLINT` | NOT NULL, CHECK (quantity > 0) | Units ordered |
| `unit_price` | `NUMERIC(12,2)` | NOT NULL, CHECK (unit_price > 0) | Price locked at checkout |

**Primary key:** `(order_id, line_no)` — composite  
**Design note:** Line items are immutable once created, so `unit_price` and `seller_id` are stored
here even if the product changes price or seller later (preserves billing history).  
**Rows:** 240,000

---

### 2.9 `cart_items`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `customer_id` | `INTEGER` | PK part 1, FK → customers | |
| `product_id` | `INTEGER` | PK part 2, FK → products | |
| `quantity` | `SMALLINT` | NOT NULL, CHECK (quantity > 0) | |
| `added_at` | `TIMESTAMPTZ` | NOT NULL | Used for abandoned-cart age checks |

**Primary key:** `(customer_id, product_id)` — composite  
**Design note:** A customer can hold at most one cart row per product; changing quantity is an UPDATE,
adding a duplicate is an ON CONFLICT DO UPDATE. This prevents duplicate rows.  
**Rows:** ~44,998

---

### 2.10 `product_reviews`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `review_id` | `INTEGER` | PK | Surrogate key |
| `product_id` | `INTEGER` | FK → products NOT NULL | |
| `customer_id` | `INTEGER` | FK → customers NOT NULL | |
| `rating` | `SMALLINT` | NOT NULL, CHECK (rating BETWEEN 1 AND 5) | Star rating |
| `title` | `TEXT` | | Headline; nullable |
| `body` | `TEXT` | | Full text; nullable — GIN index for text search (P8) |
| `verified_purchase` | `BOOLEAN` | NOT NULL, DEFAULT FALSE | Flagged by system |
| `helpful_votes` | `INTEGER` | NOT NULL, DEFAULT 0 | Upvotes from other customers |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | |

**Primary key:** `review_id`  
**Rows:** 38,662

---

### 2.11 `returns`

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `return_id` | `INTEGER` | PK | Surrogate key |
| `order_id` | `INTEGER` | FK part of composite → order_items | |
| `line_no` | `SMALLINT` | FK part of composite → order_items | |
| `reason` | `TEXT` | NOT NULL, CHECK (reason IN ('QUALITY_ISSUE','WRONG_ITEM','NOT_AS_DESCRIBED','CHANGED_MIND','DAMAGED')) | |
| `requested_at` | `TIMESTAMPTZ` | NOT NULL | |
| `status` | `TEXT` | NOT NULL, CHECK (status IN ('REQUESTED','APPROVED','REJECTED','REFUNDED')) | Approval lifecycle |
| `refund_amount` | `NUMERIC(12,2)` | CHECK (refund_amount >= 0) | NULL until refund issued |

**Primary key:** `return_id`  
**FK:** `(order_id, line_no)` → `order_items(order_id, line_no)`  
**Rows:** 5,374

---

## 3. Normalization Decisions (3NF)

The schema is in **Third Normal Form (3NF)**: every non-key attribute depends on the whole key
and nothing but the key.

| Table | 3NF Reasoning |
|-------|---------------|
| `cities` | Extracted from customers/sellers/addresses to remove transitive dependency `city_id → state` |
| `categories` | Self-referencing; each category row stores only its own name and parent — no transitive facts |
| `order_items` | PK is `(order_id, line_no)`; `unit_price` and `seller_id` depend on the full composite key |
| `customers` | `prime_since` depends only on `customer_id`, not transitively on any other column |

---

## 4. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `avg_rating` and `review_count` on `products` are **denormalized** | These are read on every product page (R03, R24). Recomputing them on-the-fly via `AVG(rating)` over `product_reviews` for every product request would be too slow. They are updated via trigger or application code after each review insert. |
| `unit_price` and `seller_id` stored on `order_items` | Prices and seller assignments can change over time; storing a snapshot ensures billing integrity and correct "order detail" display (R23). |
| `address_id` nullable on `orders` | Digital products (e-books, gift cards) require no shipping address. Forcing NOT NULL would break digital checkouts. |
| Composite PK `(customer_id, product_id)` on `cart_items` | Enforces at most one cart row per customer–product pair at the DB level, eliminating duplicates without application logic. |
| Composite PK `(order_id, line_no)` on `order_items` | Naturally models a line-item within an order; also the FK target of `returns`. |
| `pincode` stored as TEXT | Indian pincodes are always 6 digits but can start with a 0 in some edge cases; TEXT avoids accidental trimming. |
| `gstin` nullable on `sellers` | Not all sellers have completed GST verification; a UNIQUE constraint still prevents duplicates once set. |
| `asin` UNIQUE on `products` | ASIN is Amazon's global product identifier; it must be unique per listing. Also the lookup key for R24. |
| `parent_category_id` nullable (self-ref FK) | Root categories have no parent; NULL correctly models the tree root. |

---

## 5. Query–Column Mapping

| Query | Key Columns Used |
|-------|-----------------|
| R01 — Product listing by category | `products.category_id`, `products.status`, `products.price` |
| R02 — Sub-category tree | `categories.parent_category_id` (recursive CTE) |
| R03 — Ratings histogram | `product_reviews.product_id`, `product_reviews.rating` |
| R04 — Customer order list | `orders.customer_id`, `orders.ordered_at` |
| R05 — Stuck PACKED orders | `orders.status`, `orders.ordered_at` |
| R06 — Seller monthly orders | `order_items.seller_id`, `orders.ordered_at` |
| R07 — Low-stock products | `products.seller_id`, `products.stock_qty`, `products.status` |
| R08 — Prime vs non-Prime split | `customers.is_prime`, `orders.total_amount` |
| R09 — Category revenue | `products.category_id`, `order_items.quantity`, `order_items.unit_price` |
| R10 — Abandoned carts | `cart_items.customer_id`, `cart_items.added_at` |
| R11 — Frequently bought together | `order_items.product_id`, `order_items.order_id` |
| R12 — Returns by reason | `returns.reason`, `returns.status`, `returns.refund_amount` |
| R13 — Unused addresses | `addresses.address_id`, `orders.address_id` (LEFT JOIN) |
| R14 — Prime-eligible products | `products.is_prime_eligible`, `products.category_id` |
| R15 — Seller performance | `order_items.seller_id`, `products.avg_rating` |
| R16 — Review text search | `product_reviews.body` (ILIKE / GIN) |
| R17 — Fake verified reviews | `product_reviews.verified_purchase`, `orders.status`, `order_items.product_id` |
| R18 — Spending tiers | `orders.customer_id`, `customers.city_id`, `orders.total_amount` |
| R19 — Mobile sales | `products.category_id`, `order_items.product_id` |
| R20 — Daily GMV | `orders.ordered_at`, `orders.total_amount`, `orders.status` |
| R21 — Late deliveries | `orders.delivered_at`, `orders.ordered_at` |
| R22 — Deep-paginated admin view | `orders.ordered_at` |
| R23 — Order detail | `orders.order_id`, `order_items`, `products`, `sellers` |
| R24 — ASIN lookup | `products.asin` |
| W01–W06 | Various PKs and indexed columns above |

---

> **Note:** Indexes are intentionally omitted from `01_schema.sql`. All indexes are in `05_indexes.sql`
> so that Phase 3 baseline timings can be recorded on the un-indexed schema.
