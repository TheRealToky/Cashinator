/// SQLite schema definition and seed data.
///
/// Kept as plain SQL strings in one place so the shape of the database is
/// readable without tracing through migration code.
library;

/// Bump this and add a branch to `AppDatabase._migrate` for any schema change.
const int kSchemaVersion = 1;

const List<String> kCreateStatements = [
  '''
  CREATE TABLE products (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    price       INTEGER NOT NULL CHECK (price >= 0),
    category    TEXT,
    active      INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    sort_order  INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE payment_methods (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    active      INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    sort_order  INTEGER NOT NULL DEFAULT 0
  )
  ''',
  // Names are matched case-insensitively so staff can't create both "MoMo" and
  // "Momo" — the legacy ledger exports contain exactly that split (1543 vs 73
  // rows), which forces the downstream script to sum two columns for one method.
  '''
  CREATE UNIQUE INDEX idx_payment_methods_name
    ON payment_methods (name COLLATE NOCASE)
  ''',
  '''
  CREATE TABLE orders (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    order_label         TEXT    NOT NULL,
    business_date       TEXT    NOT NULL,
    created_at          TEXT    NOT NULL,
    payment_method_id   INTEGER REFERENCES payment_methods (id),
    payment_method_name TEXT    NOT NULL,
    status              TEXT    NOT NULL DEFAULT 'normal'
                        CHECK (status IN ('normal', 'voided')),
    total               INTEGER NOT NULL DEFAULT 0,
    void_reason         TEXT,
    voided_at           TEXT,
    -- A voided order must carry its audit trail; a normal one must not.
    CHECK (
      (status = 'voided' AND void_reason IS NOT NULL AND voided_at IS NOT NULL)
      OR
      (status = 'normal' AND void_reason IS NULL AND voided_at IS NULL)
    )
  )
  ''',
  '''
  CREATE INDEX idx_orders_business_date ON orders (business_date)
  ''',
  '''
  CREATE INDEX idx_orders_created_at ON orders (created_at)
  ''',
  '''
  CREATE TABLE order_lines (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id     INTEGER NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    product_id   INTEGER REFERENCES products (id),
    product_name TEXT    NOT NULL,
    qty          INTEGER NOT NULL CHECK (qty > 0),
    unit_price   INTEGER NOT NULL CHECK (unit_price >= 0),
    line_total   INTEGER NOT NULL CHECK (line_total >= 0),
    line_no      INTEGER NOT NULL DEFAULT 0
  )
  ''',
  '''
  CREATE INDEX idx_order_lines_order_id ON order_lines (order_id)
  ''',
  // One row per role. PINs are stored as salted SHA-256, never in clear text —
  // the device leaves the counter sometimes, and a plain-text PIN column would
  // be readable by anyone who pulls the database file off it.
  '''
  CREATE TABLE app_users (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    role      TEXT    NOT NULL UNIQUE CHECK (role IN ('staff', 'manager')),
    pin_hash  TEXT    NOT NULL,
    pin_salt  TEXT    NOT NULL
  )
  ''',
];

/// Matches the shop's current ledger vocabulary.
const List<Map<String, Object?>> kSeedPaymentMethods = [
  {'name': 'Cash', 'active': 1, 'sort_order': 0},
  {'name': 'MoMo', 'active': 1, 'sort_order': 1},
  {'name': 'Card', 'active': 1, 'sort_order': 2},
];

/// A starter catalogue drawn from the products that appear most often in the
/// existing ledger exports. Management edits these on day one; they exist so
/// the grid is not empty on first launch.
const List<Map<String, Object?>> kSeedProducts = [
  {'name': 'Croissant', 'price': 3000, 'category': 'Pastry', 'sort_order': 0},
  {'name': 'Pain au raisins', 'price': 3000, 'category': 'Pastry', 'sort_order': 1},
  {'name': 'Pain Suisse', 'price': 3000, 'category': 'Pastry', 'sort_order': 2},
  {'name': 'Cinnamon Roll', 'price': 2000, 'category': 'Pastry', 'sort_order': 3},
  {'name': 'Muffin', 'price': 2000, 'category': 'Pastry', 'sort_order': 4},
  {'name': 'Traditional baguette', 'price': 2000, 'category': 'Bread', 'sort_order': 5},
  {'name': 'Sourdough baguette', 'price': 2000, 'category': 'Bread', 'sort_order': 6},
  {'name': 'Baguette with Seeds', 'price': 2500, 'category': 'Bread', 'sort_order': 7},
  {'name': 'Chicken Sandwich', 'price': 7500, 'category': 'Savoury', 'sort_order': 8},
  {'name': 'Chicken Bread', 'price': 5000, 'category': 'Savoury', 'sort_order': 9},
  {'name': 'Cappuccino', 'price': 3500, 'category': 'Drinks', 'sort_order': 10},
  {'name': 'Black Tea', 'price': 2000, 'category': 'Drinks', 'sort_order': 11},
  {'name': 'Takeaway', 'price': 500, 'category': 'Extras', 'sort_order': 12},
];
