-- =====================================================================
-- Amazon DBMS Project: 30 Optimized Queries
-- File        : sql/06_optimized_queries.sql
-- Phase       : 4 — Optimization
-- Description : Optimized rewrites of workload_30.sql leveraging
--               sargable filters, JOIN/EXISTS replacements, index-friendly
--               predicates, and bug fix for SQL NULL semantics in NOT IN.
-- =====================================================================
SET search_path TO amazon;
BEGIN;

-- @R01
-- Search box: active products whose title contains "wireless", best rated first
SELECT product_id, title, price, avg_rating, review_count
FROM products
WHERE title ILIKE '%wireless%' AND status = 'ACTIVE'
ORDER BY avg_rating DESC NULLS LAST, review_count DESC
LIMIT 24;

-- @R02
-- Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000
WITH RECURSIVE tree AS (
    SELECT category_id FROM categories WHERE category_name = 'Electronics'
    UNION ALL
    SELECT c.category_id FROM categories c JOIN tree t ON c.parent_category_id = t.category_id
)
SELECT p.product_id, p.title, p.price
FROM products p
JOIN tree t ON t.category_id = p.category_id
WHERE p.price BETWEEN 1000 AND 5000
  AND p.status = 'ACTIVE'
ORDER BY p.price
LIMIT 48;

-- @R03
-- Product page: rating breakdown (how many 5★, 4★ …) for product 4321
SELECT rating, count(*) AS reviews
FROM product_reviews
WHERE product_id = 4321
GROUP BY rating
ORDER BY rating DESC;

-- @R04
-- "Your Orders": customer 1042's orders with the number of items in each
SELECT o.order_id, o.ordered_at, o.status, o.total_amount, count(oi.line_no) AS items
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1042
GROUP BY o.order_id, o.ordered_at, o.status, o.total_amount
ORDER BY o.ordered_at DESC;

-- @R05
-- Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026)
SELECT order_id, customer_id, shipped_at
FROM orders
WHERE status = 'SHIPPED'
  AND shipped_at < '2026-06-20'
ORDER BY shipped_at;

-- @R06
-- Seller Central: seller 217's order lines in June 2026
SELECT o.order_id, o.ordered_at, oi.product_id, oi.quantity, oi.unit_price
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE oi.seller_id = 217
  AND o.ordered_at >= '2026-06-01 00:00:00+05:30'
  AND o.ordered_at <  '2026-07-01 00:00:00+05:30'
ORDER BY o.ordered_at;

-- @R07
-- Seller Central: seller 217's products that are low on stock
SELECT product_id, title, stock_qty, status
FROM products
WHERE seller_id = 217
  AND stock_qty <= 20
  AND status IN ('ACTIVE', 'OUT_OF_STOCK')
ORDER BY stock_qty;

-- @R08
-- Merchandising: top 5 best-selling products in every sub-category, last 30 days
SELECT *
FROM (
    SELECT p.category_id, oi.product_id, sum(oi.quantity) AS units,
           RANK() OVER (PARTITION BY p.category_id ORDER BY sum(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE o.ordered_at >= '2026-06-01'
      AND o.status <> 'CANCELLED'
    GROUP BY p.category_id, oi.product_id
) t
WHERE rnk <= 5
ORDER BY category_id, rnk;

-- @R09
-- Prime team: average order value of Prime vs non-Prime customers per month in 2026
SELECT date_trunc('month', o.ordered_at) AS month, c.is_prime,
       count(*) AS orders, round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.ordered_at >= '2026-01-01 00:00:00+05:30'
  AND o.ordered_at <  '2027-01-01 00:00:00+05:30'
  AND o.status <> 'CANCELLED'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R10
-- Marketing: carts untouched since May 2026 whose owner has not ordered since then
SELECT ci.customer_id, count(*) AS items, sum(ci.quantity * p.price) AS cart_value
FROM cart_items ci
JOIN products p ON p.product_id = ci.product_id
WHERE ci.added_at < '2026-05-01'
  AND NOT EXISTS (SELECT 1 FROM orders o
                  WHERE o.customer_id = ci.customer_id AND o.ordered_at >= '2026-05-01')
GROUP BY ci.customer_id
ORDER BY cart_value DESC
LIMIT 100;

-- @R11
-- Product page: "Frequently bought together" with product 4321
SELECT b.product_id, count(*) AS times_together
FROM order_items a
JOIN order_items b ON b.order_id = a.order_id AND b.product_id <> a.product_id
WHERE a.product_id = 4321
GROUP BY b.product_id
ORDER BY times_together DESC
LIMIT 10;

-- @R12
-- Category managers: return rate per top-level category
SELECT top.category_name,
       count(*) AS lines_sold,
       count(r.return_id) AS lines_returned,
       round(100.0 * count(r.return_id) / count(*), 2) AS return_pct
FROM order_items oi
JOIN products p     ON p.product_id = oi.product_id
JOIN categories sub ON sub.category_id = p.category_id
JOIN categories top ON top.category_id = sub.parent_category_id
LEFT JOIN returns r ON r.order_id = oi.order_id AND r.line_no = oi.line_no
GROUP BY top.category_name
ORDER BY return_pct DESC;

-- @R13
-- Data clean-up: saved addresses that have never been used for any order
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.address_id = a.address_id);

-- @R14
-- Deals page: active products selling at less than half of MRP, biggest discount first
SELECT product_id, title, mrp, price, round(100 * (1 - price / mrp), 1) AS discount_pct
FROM products
WHERE price < mrp * 0.5 AND status = 'ACTIVE'
ORDER BY price / mrp
LIMIT 50;

-- @R15
-- Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026
SELECT s.seller_id, s.business_name, count(*) AS lines_sold, sum(oi.quantity * oi.unit_price) AS revenue
FROM sellers s
JOIN order_items oi ON oi.seller_id = s.seller_id
JOIN orders o       ON o.order_id = oi.order_id
WHERE o.ordered_at >= '2026-01-01' AND o.status IN ('DELIVERED', 'SHIPPED', 'OUT_FOR_DELIVERY')
GROUP BY s.seller_id, s.business_name
HAVING count(*) >= 50
ORDER BY revenue DESC
LIMIT 20;

-- @R16
-- Review insights: Electronics reviews that mention the battery
SELECT r.review_id, r.product_id, r.rating, r.body
FROM product_reviews r
JOIN products p     ON p.product_id = r.product_id
JOIN categories c   ON c.category_id = p.category_id
WHERE c.parent_category_id = 1
  AND r.body ILIKE '%battery%'
ORDER BY r.created_at DESC
LIMIT 50;

-- @R17
-- Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer
SELECT r.review_id, r.product_id, r.customer_id
FROM product_reviews r
WHERE r.verified_purchase
  AND NOT EXISTS (SELECT 1
                  FROM orders o
                  JOIN order_items oi ON oi.order_id = o.order_id
                  WHERE o.customer_id = r.customer_id
                    AND oi.product_id = r.product_id
                    AND o.status IN ('DELIVERED', 'RETURNED'));

-- @R18
-- Customer analytics: Mumbai customers split into 4 spending tiers (2026)
SELECT customer_id, total_spend, NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_tier
FROM (
    SELECT o.customer_id, sum(o.total_amount) AS total_spend
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE c.city_id = 2 AND o.ordered_at >= '2026-01-01' AND o.status = 'DELIVERED'
    GROUP BY o.customer_id
) t
ORDER BY spend_tier, total_spend DESC;

-- @R19
-- Category report: every Mobile phone with its last sale date and units sold (all time)
WITH mobile_products AS (
    SELECT p.product_id, p.title
    FROM products p
    JOIN categories c ON c.category_id = p.category_id
    WHERE c.category_name = 'Mobiles'
)
SELECT mp.product_id, mp.title,
       max(o.ordered_at) AS last_sold_at,
       coalesce(sum(oi.quantity), 0) AS units_sold
FROM mobile_products mp
LEFT JOIN order_items oi ON oi.product_id = mp.product_id
LEFT JOIN orders o ON o.order_id = oi.order_id
GROUP BY mp.product_id, mp.title
ORDER BY units_sold DESC, mp.product_id;

-- @R20
-- Finance: daily sales (GMV) and running total for June 2026
SELECT day, gmv, sum(gmv) OVER (ORDER BY day) AS running_gmv
FROM (
    SELECT ordered_at::date AS day, sum(total_amount) AS gmv
    FROM orders
    WHERE status <> 'CANCELLED'
      AND ordered_at >= '2026-06-01 00:00:00+05:30'
      AND ordered_at <  '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Logistics: deliveries in June 2026 that took more than 5 days
SELECT order_id, customer_id, ordered_at, delivered_at
FROM orders
WHERE delivered_at > ordered_at + interval '5 days'
  AND ordered_at >= '2026-06-01'
ORDER BY delivered_at - ordered_at DESC;

-- @R22
-- Admin: "All orders", newest first, page 3,001 (25 rows per page)
SELECT order_id, customer_id, status, total_amount, ordered_at
FROM orders
ORDER BY ordered_at DESC
OFFSET 75000
LIMIT 25;

-- @R23
-- Order details page: one order with its lines, products and sellers
SELECT o.order_id, o.ordered_at, o.status, oi.line_no, p.title, s.business_name, oi.quantity, oi.unit_price
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p     ON p.product_id = oi.product_id
JOIN sellers s      ON s.seller_id = oi.seller_id
WHERE o.order_id = 100001
ORDER BY oi.line_no;

-- @R24
-- Product lookup by ASIN (barcode scanner in the warehouse)
SELECT product_id, title, seller_id, stock_qty
FROM products
WHERE asin = 'B0020A200F';

-- @W01
-- Checkout: create a new order (header row)
INSERT INTO orders (order_id, customer_id, address_id, ordered_at, payment_method, total_amount, status)
VALUES (90000001, 1042, 2083, '2026-07-01 10:30:00+05:30', 'UPI', 3935.00, 'PLACED');

-- @W02
-- Checkout: reduce stock of product 4322 after a sale
UPDATE products
SET stock_qty = stock_qty - 1
WHERE product_id = 4322 AND stock_qty >= 1;

-- @W03
-- Seller Central: 10% price cut on all of seller 217's Watches
UPDATE products p
SET price = round(p.price * 0.90, 0)
FROM categories c
WHERE c.category_id = p.category_id
  AND c.category_name = 'Watches'
  AND p.seller_id = 217;

-- @W04
-- Big sale: 5,000 "add to cart" events loaded in one batch
INSERT INTO cart_items (customer_id, product_id, quantity, added_at)
SELECT 1 + (g * 7) % 30000, 1 + (g * 13) % 30000, 1, TIMESTAMPTZ '2026-07-01 00:00:00+05:30' + g * interval '1 second'
FROM generate_series(1, 5000) AS g
ON CONFLICT (customer_id, product_id) DO NOTHING;

-- @W05
-- Logistics: mark the oldest packed order as shipped
UPDATE orders
SET status = 'SHIPPED', shipped_at = ordered_at + interval '6 hours'
WHERE order_id = (SELECT min(order_id) FROM orders WHERE status = 'PACKED');

-- @W06
-- Nightly clean-up: remove cart items older than 90 days
DELETE FROM cart_items
WHERE added_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '90 days';

-- @END
ROLLBACK;
