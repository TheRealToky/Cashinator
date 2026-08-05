/// SQLite schema definition and seed data.
///
/// Kept as plain SQL strings in one place so the shape of the database is
/// readable without tracing through migration code.
library;

/// Bump this and add a branch to `AppDatabase._migrate` for any schema change.
///
/// v2 added the limited back-office `supervisor` role to `app_users`.
const int kSchemaVersion = 2;

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
    role      TEXT    NOT NULL UNIQUE
              CHECK (role IN ('staff', 'manager', 'supervisor')),
    pin_hash  TEXT    NOT NULL,
    pin_salt  TEXT    NOT NULL
  )
  ''',
];

/// Migration to schema v2: admit the limited back-office `supervisor` role.
///
/// SQLite cannot ALTER a CHECK constraint in place, so `app_users` is rebuilt
/// with the widened `role` check and its existing rows copied across. Nothing
/// references `app_users` with a foreign key, so the drop-and-rename is safe.
/// The new supervisor row itself is inserted from Dart (the PIN must be hashed
/// first), not here.
const List<String> kMigrateV2Statements = [
  '''
  CREATE TABLE app_users_new (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    role      TEXT    NOT NULL UNIQUE
              CHECK (role IN ('staff', 'manager', 'supervisor')),
    pin_hash  TEXT    NOT NULL,
    pin_salt  TEXT    NOT NULL
  )
  ''',
  '''
  INSERT INTO app_users_new (id, role, pin_hash, pin_salt)
  SELECT id, role, pin_hash, pin_salt FROM app_users
  ''',
  'DROP TABLE app_users',
  'ALTER TABLE app_users_new RENAME TO app_users',
];

/// Matches the shop's current ledger vocabulary.
const List<Map<String, Object?>> kSeedPaymentMethods = [
  {'name': 'Cash', 'active': 1, 'sort_order': 0},
  {'name': 'MoMo', 'active': 1, 'sort_order': 1},
  {'name': 'Card', 'active': 1, 'sort_order': 2},
];

/// The shop's full catalogue, imported from `products-20260721-1229.xlsx`
/// (128 items). Prices are the selling prices from that sheet, in whole RWF.
///
/// Ordered by category, then by name, so the grid reads the same way the
/// category filter above it does. This runs once, on first launch; after that
/// the back office owns the catalogue.
const List<Map<String, Object?>> kSeedProducts = [
  // Beverages
  {'name': 'Apple juice', 'price': 3500, 'category': 'Beverages', 'sort_order': 0},
  {'name': 'Chocolate milkshake', 'price': 6000, 'category': 'Beverages', 'sort_order': 1},
  {'name': 'Coca cola', 'price': 2000, 'category': 'Beverages', 'sort_order': 2},
  {'name': 'Coca zero', 'price': 2000, 'category': 'Beverages', 'sort_order': 3},
  {'name': 'Fanta ananas', 'price': 2000, 'category': 'Beverages', 'sort_order': 4},
  {'name': 'Fanta citron', 'price': 2000, 'category': 'Beverages', 'sort_order': 5},
  {'name': 'Fanta orange', 'price': 2000, 'category': 'Beverages', 'sort_order': 6},
  {'name': 'Hibiscus juice', 'price': 5000, 'category': 'Beverages', 'sort_order': 7},
  {'name': 'Hot chocolate', 'price': 4000, 'category': 'Beverages', 'sort_order': 8},
  {'name': 'Mango juice', 'price': 4000, 'category': 'Beverages', 'sort_order': 9},
  {'name': 'Milk', 'price': 1500, 'category': 'Beverages', 'sort_order': 10},
  {'name': 'Mint & Lemon', 'price': 3000, 'category': 'Beverages', 'sort_order': 11},
  {'name': 'Mojito', 'price': 18000, 'category': 'Beverages', 'sort_order': 12},
  {'name': 'Panaché', 'price': 2000, 'category': 'Beverages', 'sort_order': 13},
  {'name': 'Passion juice', 'price': 4000, 'category': 'Beverages', 'sort_order': 14},
  {'name': 'Pineapple & ginger juice', 'price': 3500, 'category': 'Beverages', 'sort_order': 15},
  {'name': 'Pineapple juice', 'price': 3500, 'category': 'Beverages', 'sort_order': 16},
  {'name': 'Smoothie', 'price': 7000, 'category': 'Beverages', 'sort_order': 17},
  {'name': 'Sparkling water', 'price': 2000, 'category': 'Beverages', 'sort_order': 18},
  {'name': 'Sprite', 'price': 2000, 'category': 'Beverages', 'sort_order': 19},
  {'name': 'Water', 'price': 1500, 'category': 'Beverages', 'sort_order': 20},

  // Breads
  {'name': 'Baguette with seeds', 'price': 2500, 'category': 'Breads', 'sort_order': 21},
  {'name': 'Brioche', 'price': 2500, 'category': 'Breads', 'sort_order': 22},
  {'name': 'Brown baguette', 'price': 3000, 'category': 'Breads', 'sort_order': 23},
  {'name': 'Brown bread', 'price': 4000, 'category': 'Breads', 'sort_order': 24},
  {'name': 'Chicken bread', 'price': 5000, 'category': 'Breads', 'sort_order': 25},
  {'name': 'Soft bread (Pain de mie)', 'price': 4000, 'category': 'Breads', 'sort_order': 26},
  {'name': 'Sourdough baguette', 'price': 2000, 'category': 'Breads', 'sort_order': 27},
  {'name': 'Sourdough bread', 'price': 3000, 'category': 'Breads', 'sort_order': 28},
  {'name': 'Traditional Baguette', 'price': 2000, 'category': 'Breads', 'sort_order': 29},

  // Cakes
  {'name': 'Cake', 'price': 8000, 'category': 'Cakes', 'sort_order': 30},
  {'name': 'Muffin', 'price': 3000, 'category': 'Cakes', 'sort_order': 31},

  // Coffees
  {'name': 'African coffee', 'price': 4000, 'category': 'Coffees', 'sort_order': 32},
  {'name': 'Americano', 'price': 2800, 'category': 'Coffees', 'sort_order': 33},
  {'name': 'Black coffee', 'price': 2500, 'category': 'Coffees', 'sort_order': 34},
  {'name': 'Cappuccino', 'price': 3500, 'category': 'Coffees', 'sort_order': 35},
  {'name': 'Double espresso', 'price': 3000, 'category': 'Coffees', 'sort_order': 36},
  {'name': 'Espresso', 'price': 2500, 'category': 'Coffees', 'sort_order': 37},
  {'name': 'Flat white', 'price': 2500, 'category': 'Coffees', 'sort_order': 38},
  {'name': 'Ice', 'price': 500, 'category': 'Coffees', 'sort_order': 39},
  {'name': 'Iced black coffee', 'price': 3500, 'category': 'Coffees', 'sort_order': 40},
  {'name': 'Iced cappuccino', 'price': 4000, 'category': 'Coffees', 'sort_order': 41},
  {'name': 'Iced latte', 'price': 4000, 'category': 'Coffees', 'sort_order': 42},
  {'name': 'Latte', 'price': 3500, 'category': 'Coffees', 'sort_order': 43},
  {'name': 'Macchiato', 'price': 3000, 'category': 'Coffees', 'sort_order': 44},
  {'name': 'Mocha', 'price': 4000, 'category': 'Coffees', 'sort_order': 45},
  {'name': 'Spanish latte', 'price': 5000, 'category': 'Coffees', 'sort_order': 46},

  // Containers
  {'name': 'Bag', 'price': 1000, 'category': 'Containers', 'sort_order': 47},
  {'name': 'Takeaway', 'price': 500, 'category': 'Containers', 'sort_order': 48},

  // Fast foods
  {'name': 'Beef burger', 'price': 6500, 'category': 'Fast foods', 'sort_order': 49},
  {'name': 'Beef tacos', 'price': 9500, 'category': 'Fast foods', 'sort_order': 50},
  {'name': 'Chicken burger', 'price': 6900, 'category': 'Fast foods', 'sort_order': 51},
  {'name': 'Chicken tacos', 'price': 9500, 'category': 'Fast foods', 'sort_order': 52},
  {'name': 'Chips', 'price': 2000, 'category': 'Fast foods', 'sort_order': 53},
  {'name': 'Extra chicken', 'price': 2500, 'category': 'Fast foods', 'sort_order': 54},
  {'name': 'Ham & cheese croissant', 'price': 5000, 'category': 'Fast foods', 'sort_order': 55},
  {'name': 'Mini burger', 'price': 1200, 'category': 'Fast foods', 'sort_order': 56},
  {'name': 'Omelette', 'price': 4000, 'category': 'Fast foods', 'sort_order': 57},
  {'name': 'Omelette (customized)', 'price': 5000, 'category': 'Fast foods', 'sort_order': 58},
  {'name': 'Pizza roll', 'price': 6000, 'category': 'Fast foods', 'sort_order': 59},
  {'name': 'Quiche', 'price': 5000, 'category': 'Fast foods', 'sort_order': 60},
  {'name': 'Samosa', 'price': 500, 'category': 'Fast foods', 'sort_order': 61},
  {'name': 'Sausage pizza', 'price': 13000, 'category': 'Fast foods', 'sort_order': 62},
  {'name': 'Tuna panini', 'price': 8000, 'category': 'Fast foods', 'sort_order': 63},
  {'name': 'Tuna quiche (small)', 'price': 1200, 'category': 'Fast foods', 'sort_order': 64},

  // Others
  {'name': 'Malagasy dinner', 'price': 7500, 'category': 'Others', 'sort_order': 65},
  {'name': 'Paper bag', 'price': 200, 'category': 'Others', 'sort_order': 66},

  // Pastries
  {'name': '4/4', 'price': 3000, 'category': 'Pastries', 'sort_order': 67},
  {'name': 'Biscuit sablé', 'price': 2500, 'category': 'Pastries', 'sort_order': 68},
  {'name': 'Brownie', 'price': 3000, 'category': 'Pastries', 'sort_order': 69},
  {'name': 'Brownie (special)', 'price': 15000, 'category': 'Pastries', 'sort_order': 70},
  {'name': 'Cake (6 persons)', 'price': 35000, 'category': 'Pastries', 'sort_order': 71},
  {'name': 'Cheese croissant', 'price': 3000, 'category': 'Pastries', 'sort_order': 72},
  {'name': 'Cinnamon roll', 'price': 2000, 'category': 'Pastries', 'sort_order': 73},
  {'name': 'Cookies', 'price': 3000, 'category': 'Pastries', 'sort_order': 74},
  {'name': 'Croissant', 'price': 3000, 'category': 'Pastries', 'sort_order': 75},
  {'name': 'Feuilleté saucisse', 'price': 5000, 'category': 'Pastries', 'sort_order': 76},
  {'name': 'Laminated dough (pâte viennoiserie)', 'price': 25000, 'category': 'Pastries', 'sort_order': 77},
  {'name': 'Mini macaron', 'price': 1200, 'category': 'Pastries', 'sort_order': 78},
  {'name': 'Mocha tart', 'price': 5000, 'category': 'Pastries', 'sort_order': 79},
  {'name': 'Mocha tart (6 person)', 'price': 35000, 'category': 'Pastries', 'sort_order': 80},
  {'name': 'Opéra', 'price': 5000, 'category': 'Pastries', 'sort_order': 81},
  {'name': 'Pain au chocolat', 'price': 3000, 'category': 'Pastries', 'sort_order': 82},
  {'name': 'Pain aux raisins', 'price': 3000, 'category': 'Pastries', 'sort_order': 83},
  {'name': 'Pain Suisse', 'price': 3000, 'category': 'Pastries', 'sort_order': 84},
  {'name': 'Palmier', 'price': 2500, 'category': 'Pastries', 'sort_order': 85},
  {'name': 'Petit paté', 'price': 1200, 'category': 'Pastries', 'sort_order': 86},
  {'name': 'Puff pastry (pâte feuilletée) — w/h sugar', 'price': 20000, 'category': 'Pastries', 'sort_order': 87},
  {'name': 'Puff pastry (pâte feuilletée) — w/o sugar', 'price': 16000, 'category': 'Pastries', 'sort_order': 88},
  {'name': 'Red velvet', 'price': 5000, 'category': 'Pastries', 'sort_order': 89},
  {'name': 'Red Velvet (6 person)', 'price': 32000, 'category': 'Pastries', 'sort_order': 90},
  {'name': 'Salty crepes', 'price': 7000, 'category': 'Pastries', 'sort_order': 91},
  {'name': 'Tarte au chocolat', 'price': 5000, 'category': 'Pastries', 'sort_order': 92},
  {'name': 'Tarte au citron', 'price': 5000, 'category': 'Pastries', 'sort_order': 93},
  {'name': 'Tarte au fraise', 'price': 5000, 'category': 'Pastries', 'sort_order': 94},
  {'name': 'Tarte au fruits', 'price': 5000, 'category': 'Pastries', 'sort_order': 95},
  {'name': 'Tarte aux fruits (6 pers)', 'price': 35000, 'category': 'Pastries', 'sort_order': 96},
  {'name': 'Tarte mangue passion', 'price': 5000, 'category': 'Pastries', 'sort_order': 97},
  {'name': 'Tartelette aux fruits', 'price': 1200, 'category': 'Pastries', 'sort_order': 98},
  {'name': 'Tiramisu', 'price': 5000, 'category': 'Pastries', 'sort_order': 99},
  {'name': 'Tiramisu (6 person)', 'price': 35000, 'category': 'Pastries', 'sort_order': 100},
  {'name': 'Writing on cake', 'price': 1000, 'category': 'Pastries', 'sort_order': 101},

  // Salads
  {'name': 'Chicken salad', 'price': 6500, 'category': 'Salads', 'sort_order': 102},
  {'name': 'Salad', 'price': 6000, 'category': 'Salads', 'sort_order': 103},

  // Sandwiches
  {'name': 'Beef panini', 'price': 7000, 'category': 'Sandwiches', 'sort_order': 104},
  {'name': 'Beef sandwich', 'price': 8000, 'category': 'Sandwiches', 'sort_order': 105},
  {'name': 'Chicken panini', 'price': 7900, 'category': 'Sandwiches', 'sort_order': 106},
  {'name': 'Chicken sandwich', 'price': 7500, 'category': 'Sandwiches', 'sort_order': 107},
  {'name': 'Club sandwich', 'price': 7000, 'category': 'Sandwiches', 'sort_order': 108},
  {'name': 'Croque madame', 'price': 7000, 'category': 'Sandwiches', 'sort_order': 109},
  {'name': 'Croque monsieur', 'price': 6000, 'category': 'Sandwiches', 'sort_order': 110},
  {'name': 'Ham & cheese panini', 'price': 8500, 'category': 'Sandwiches', 'sort_order': 111},
  {'name': 'Ham sandwich', 'price': 8500, 'category': 'Sandwiches', 'sort_order': 112},
  {'name': 'Hot dog', 'price': 6000, 'category': 'Sandwiches', 'sort_order': 113},
  {'name': 'Sardine sandwich', 'price': 5000, 'category': 'Sandwiches', 'sort_order': 114},
  {'name': 'Tuna sandwich', 'price': 8000, 'category': 'Sandwiches', 'sort_order': 115},

  // Teas
  {'name': 'African tea', 'price': 3500, 'category': 'Teas', 'sort_order': 116},
  {'name': 'Black tea', 'price': 2000, 'category': 'Teas', 'sort_order': 117},
  {'name': 'Green tea', 'price': 2000, 'category': 'Teas', 'sort_order': 118},
  {'name': 'Lemon tea', 'price': 2500, 'category': 'Teas', 'sort_order': 119},
  {'name': 'Spice tea', 'price': 3500, 'category': 'Teas', 'sort_order': 120},

  // Toppings
  {'name': 'Avocado', 'price': 1500, 'category': 'Toppings', 'sort_order': 121},
  {'name': 'Bacon', 'price': 1500, 'category': 'Toppings', 'sort_order': 122},
  {'name': 'Cheese', 'price': 1000, 'category': 'Toppings', 'sort_order': 123},
  {'name': 'Chicken', 'price': 2000, 'category': 'Toppings', 'sort_order': 124},
  {'name': 'Egg', 'price': 500, 'category': 'Toppings', 'sort_order': 125},
  {'name': 'Tuna', 'price': 2500, 'category': 'Toppings', 'sort_order': 126},
  {'name': 'Vanilla', 'price': 1000, 'category': 'Toppings', 'sort_order': 127},
];
