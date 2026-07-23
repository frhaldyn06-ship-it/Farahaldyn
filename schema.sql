-- ============================================================
-- Africa HealthOS — Database Schema
-- Phase 1: Accounts & Digital Health Record
-- Phase 2: Pharmacy Module
-- Engine: PostgreSQL 14+
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------
-- PHASE 1: ACCOUNTS
-- ------------------------------------------------------------

CREATE TYPE user_role AS ENUM ('patient', 'pharmacist', 'doctor', 'nurse', 'lab_tech', 'admin');

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role            user_role NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    phone           VARCHAR(20) UNIQUE NOT NULL,
    email           VARCHAR(150) UNIQUE,
    password_hash   TEXT NOT NULL,
    country         VARCHAR(60),
    city            VARCHAR(60),
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE auth_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token   TEXT NOT NULL,
    user_agent      TEXT,
    ip_address      VARCHAR(45),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_auth_sessions_user ON auth_sessions(user_id);

CREATE TABLE otp_codes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone           VARCHAR(20) NOT NULL,
    code_hash       TEXT NOT NULL,
    purpose         VARCHAR(30) NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    consumed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_phone ON otp_codes(phone);

-- ------------------------------------------------------------
-- PHASE 1: DIGITAL HEALTH RECORD (patient-owned)
-- ------------------------------------------------------------

CREATE TABLE patient_profiles (
    user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    date_of_birth       DATE,
    sex                 VARCHAR(10),
    blood_type          VARCHAR(5),
    height_cm           NUMERIC(5,1),
    weight_kg           NUMERIC(5,1),
    emergency_contact   VARCHAR(150),
    emergency_phone     VARCHAR(20)
);

CREATE TABLE patient_allergies (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      UUID NOT NULL REFERENCES patient_profiles(user_id) ON DELETE CASCADE,
    allergen        VARCHAR(150) NOT NULL,
    severity        VARCHAR(20),
    noted_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE patient_conditions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      UUID NOT NULL REFERENCES patient_profiles(user_id) ON DELETE CASCADE,
    condition_name  VARCHAR(150) NOT NULL,
    diagnosed_at    DATE,
    is_chronic      BOOLEAN DEFAULT TRUE,
    notes           TEXT
);

CREATE TABLE patient_medications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      UUID NOT NULL REFERENCES patient_profiles(user_id) ON DELETE CASCADE,
    medicine_name   VARCHAR(150) NOT NULL,
    dosage          VARCHAR(80),
    frequency       VARCHAR(80),
    started_at      DATE,
    ended_at        DATE,
    prescribed_by   UUID REFERENCES users(id)
);

-- ------------------------------------------------------------
-- PHASE 2: PHARMACY MODULE
-- ------------------------------------------------------------

CREATE TABLE pharmacies (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id   UUID NOT NULL REFERENCES users(id),
    name            VARCHAR(150) NOT NULL,
    license_number  VARCHAR(80) UNIQUE,
    country         VARCHAR(60) NOT NULL,
    city            VARCHAR(60) NOT NULL,
    address         TEXT,
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    phone           VARCHAR(20),
    opens_at        TIME,
    closes_at       TIME,
    is_open_now     BOOLEAN DEFAULT TRUE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pharmacies_city ON pharmacies(city);

CREATE TABLE medicines (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(150) NOT NULL,
    generic_name    VARCHAR(150),
    manufacturer    VARCHAR(150),
    category        VARCHAR(80),
    requires_prescription BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_medicines_name ON medicines USING GIN (to_tsvector('simple', name));

CREATE TABLE pharmacy_inventory (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id     UUID NOT NULL REFERENCES pharmacies(id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines(id),
    price           NUMERIC(10,2) NOT NULL,
    currency        VARCHAR(5) NOT NULL DEFAULT 'USD',
    quantity        INTEGER NOT NULL DEFAULT 0,
    expiry_date     DATE,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (pharmacy_id, medicine_id)
);
CREATE INDEX idx_inventory_pharmacy ON pharmacy_inventory(pharmacy_id);
CREATE INDEX idx_inventory_medicine ON pharmacy_inventory(medicine_id);

CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'ready', 'completed', 'cancelled');

CREATE TABLE pharmacy_orders (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id      UUID NOT NULL REFERENCES users(id),
    pharmacy_id     UUID NOT NULL REFERENCES pharmacies(id),
    status          order_status NOT NULL DEFAULT 'pending',
    total_amount    NUMERIC(10,2) NOT NULL DEFAULT 0,
    currency        VARCHAR(5) NOT NULL DEFAULT 'USD',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE pharmacy_order_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES pharmacy_orders(id) ON DELETE CASCADE,
    medicine_id     UUID NOT NULL REFERENCES medicines(id),
    quantity        INTEGER NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL
);

-- ------------------------------------------------------------
-- Trigger: keep updated_at fresh
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON pharmacy_orders
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
