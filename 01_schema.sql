-- 01_schema.sql : table definitions for the manufacturing quality database (SQLite)

DROP TABLE IF EXISTS downtime_events;
DROP TABLE IF EXISTS production_log;
DROP TABLE IF EXISTS inventory_monthly;
DROP TABLE IF EXISTS machines;
DROP TABLE IF EXISTS products;

CREATE TABLE products (
    product_id      TEXT PRIMARY KEY,
    product_name    TEXT NOT NULL,
    product_family  TEXT
);

CREATE TABLE machines (
    machine_id      TEXT PRIMARY KEY,
    line_id         TEXT NOT NULL,
    machine_type    TEXT NOT NULL,
    product_id      TEXT NOT NULL REFERENCES products(product_id),
    daily_capacity  INTEGER
);

CREATE TABLE production_log (
    record_id        INTEGER PRIMARY KEY,
    production_date  DATE    NOT NULL,
    machine_id       TEXT    NOT NULL REFERENCES machines(machine_id),
    product_id       TEXT    NOT NULL REFERENCES products(product_id),
    units_produced   INTEGER NOT NULL CHECK (units_produced >= 0),
    units_defective  INTEGER NOT NULL CHECK (units_defective >= 0)
);

CREATE TABLE downtime_events (
    event_id          INTEGER PRIMARY KEY,
    machine_id        TEXT    NOT NULL REFERENCES machines(machine_id),
    event_date        DATE    NOT NULL,
    duration_minutes  INTEGER NOT NULL CHECK (duration_minutes > 0),
    reason            TEXT
);

CREATE TABLE inventory_monthly (
    month           TEXT NOT NULL,          -- 'YYYY-MM'
    product_id      TEXT NOT NULL REFERENCES products(product_id),
    on_hand_units   INTEGER NOT NULL,
    reorder_point   INTEGER NOT NULL,
    PRIMARY KEY (month, product_id)
);

CREATE INDEX idx_prod_date    ON production_log(production_date);
CREATE INDEX idx_prod_machine ON production_log(machine_id);
CREATE INDEX idx_down_machine ON downtime_events(machine_id);
