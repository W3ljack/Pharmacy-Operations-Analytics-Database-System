/* =========================================================
   PHARMAS — One-shot executable build + seed (2 pharmacies)
   MySQL 8.x (uses window functions)
   ========================================================= */

-- Hard reset (cleanest way to guarantee an executable run)
DROP DATABASE IF EXISTS Pharmas;
CREATE DATABASE Pharmas
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE Pharmas;

SET FOREIGN_KEY_CHECKS = 0;
SET FOREIGN_KEY_CHECKS = 1;

-- =========================================================
-- CORE TABLES
-- =========================================================

CREATE TABLE address (
  address_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  line1 VARCHAR(120) NOT NULL,
  line2 VARCHAR(120),
  city VARCHAR(80) NOT NULL,
  state CHAR(2) NOT NULL,
  zip VARCHAR(10) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE pharmacy (
  pharmacy_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  npi CHAR(10) NOT NULL UNIQUE,
  store_code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(25),
  address_id BIGINT NOT NULL,
  CONSTRAINT fk_pharmacy_address
    FOREIGN KEY (address_id) REFERENCES address(address_id)
) ENGINE=InnoDB;

CREATE TABLE employee (
  employee_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pharmacy_id BIGINT NOT NULL,
  employee_number VARCHAR(30) NOT NULL UNIQUE,
  email VARCHAR(254) NOT NULL UNIQUE,
  first_name VARCHAR(60) NOT NULL,
  last_name VARCHAR(60) NOT NULL,
  role VARCHAR(40) NOT NULL,
  CONSTRAINT fk_employee_pharmacy
    FOREIGN KEY (pharmacy_id) REFERENCES pharmacy(pharmacy_id)
) ENGINE=InnoDB;

CREATE TABLE pharmacist (
  employee_id BIGINT PRIMARY KEY,
  license_number VARCHAR(40) NOT NULL UNIQUE,
  dea_number VARCHAR(40) UNIQUE,
  CONSTRAINT fk_pharmacist_employee
    FOREIGN KEY (employee_id) REFERENCES employee(employee_id)
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE patient (
  patient_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  mrn VARCHAR(40) UNIQUE,
  address_id BIGINT NOT NULL,
  first_name VARCHAR(60) NOT NULL,
  last_name VARCHAR(60) NOT NULL,
  dob DATE NOT NULL,
  phone VARCHAR(25),
  CONSTRAINT fk_patient_address
    FOREIGN KEY (address_id) REFERENCES address(address_id)
) ENGINE=InnoDB;

CREATE TABLE prescriber (
  prescriber_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  npi CHAR(10) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  specialty VARCHAR(80),
  address_id BIGINT NOT NULL,
  CONSTRAINT fk_prescriber_address
    FOREIGN KEY (address_id) REFERENCES address(address_id)
) ENGINE=InnoDB;

CREATE TABLE drug (
  drug_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ndc11 CHAR(11) UNIQUE,
  generic_name VARCHAR(120) NOT NULL,
  brand_name VARCHAR(120),
  dosage_form VARCHAR(80)
) ENGINE=InnoDB;

CREATE TABLE prescription (
  rx_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pharmacy_id BIGINT NOT NULL,
  patient_id BIGINT NOT NULL,
  prescriber_id BIGINT NOT NULL,
  rx_number VARCHAR(40) NOT NULL,
  written_date DATE NOT NULL,
  status ENUM('NEW','ON_HOLD','ACTIVE','COMPLETED','CANCELLED','EXPIRED') NOT NULL DEFAULT 'NEW',
  UNIQUE KEY uq_rx_pharm_num (pharmacy_id, rx_number),
  CONSTRAINT fk_rx_pharmacy   FOREIGN KEY (pharmacy_id)   REFERENCES pharmacy(pharmacy_id),
  CONSTRAINT fk_rx_patient    FOREIGN KEY (patient_id)    REFERENCES patient(patient_id),
  CONSTRAINT fk_rx_prescriber FOREIGN KEY (prescriber_id) REFERENCES prescriber(prescriber_id)
) ENGINE=InnoDB;

CREATE TABLE dispense_fill (
  fill_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  rx_id BIGINT NOT NULL,
  pharmacist_id BIGINT NOT NULL,
  fill_date DATE NOT NULL,
  quantity DECIMAL(12,3) NOT NULL,
  CONSTRAINT fk_fill_rx   FOREIGN KEY (rx_id)         REFERENCES prescription(rx_id),
  CONSTRAINT fk_fill_rph  FOREIGN KEY (pharmacist_id) REFERENCES pharmacist(employee_id)
) ENGINE=InnoDB;

CREATE TABLE insurance_plan (
  plan_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  bin VARCHAR(10) NOT NULL,
  pcn VARCHAR(10) NOT NULL,
  group_id VARCHAR(20) NOT NULL,
  plan_name VARCHAR(120) NOT NULL,
  UNIQUE KEY uq_plan (bin, pcn, group_id)
) ENGINE=InnoDB;

CREATE TABLE patient_insurance (
  patient_id BIGINT NOT NULL,
  plan_id BIGINT NOT NULL,
  member_id VARCHAR(40) NOT NULL,
  effective_start DATE NOT NULL,
  effective_end DATE NULL,
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (patient_id, plan_id),
  CONSTRAINT fk_pi_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_pi_plan FOREIGN KEY (plan_id) REFERENCES insurance_plan(plan_id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- =========================================================
-- RX LIFECYCLE TABLES
-- =========================================================

CREATE TABLE prescription_item (
  rx_id BIGINT NOT NULL,
  item_no INT NOT NULL,
  drug_id BIGINT NOT NULL,
  sig TEXT NOT NULL,
  qty_prescribed DECIMAL(12,3) NOT NULL,
  days_supply INT NOT NULL,
  refills_authorized INT NOT NULL DEFAULT 0,
  PRIMARY KEY (rx_id, item_no),
  CONSTRAINT fk_rx_item_rx   FOREIGN KEY (rx_id)   REFERENCES prescription(rx_id) ON DELETE CASCADE,
  CONSTRAINT fk_rx_item_drug FOREIGN KEY (drug_id) REFERENCES drug(drug_id)
) ENGINE=InnoDB;

CREATE TABLE refill_request (
  refill_request_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  rx_id BIGINT NOT NULL,
  patient_id BIGINT NOT NULL,
  requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status ENUM('REQUESTED','APPROVED','DENIED','CANCELLED') NOT NULL DEFAULT 'REQUESTED',
  notes VARCHAR(255),
  CONSTRAINT fk_refill_rx      FOREIGN KEY (rx_id)      REFERENCES prescription(rx_id),
  CONSTRAINT fk_refill_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id)
) ENGINE=InnoDB;

CREATE TABLE rx_status_history (
  rx_status_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  rx_id BIGINT NOT NULL,
  status VARCHAR(20) NOT NULL,
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  changed_by_employee_id BIGINT,
  CONSTRAINT fk_rxhist_rx  FOREIGN KEY (rx_id) REFERENCES prescription(rx_id) ON DELETE CASCADE,
  CONSTRAINT fk_rxhist_emp FOREIGN KEY (changed_by_employee_id) REFERENCES employee(employee_id)
) ENGINE=InnoDB;

CREATE TABLE fill_item (
  fill_id BIGINT NOT NULL,
  item_no INT NOT NULL,
  drug_id BIGINT NOT NULL,
  qty_dispensed DECIMAL(12,3) NOT NULL,
  PRIMARY KEY (fill_id, item_no),
  CONSTRAINT fk_fillitem_fill FOREIGN KEY (fill_id) REFERENCES dispense_fill(fill_id) ON DELETE CASCADE,
  CONSTRAINT fk_fillitem_drug FOREIGN KEY (drug_id) REFERENCES drug(drug_id)
) ENGINE=InnoDB;

CREATE TABLE pickup_transaction (
  pickup_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  fill_id BIGINT NOT NULL,
  picked_up_by_patient_id BIGINT NOT NULL,
  pickup_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id_verified TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT fk_pickup_fill    FOREIGN KEY (fill_id) REFERENCES dispense_fill(fill_id),
  CONSTRAINT fk_pickup_patient FOREIGN KEY (picked_up_by_patient_id) REFERENCES patient(patient_id)
) ENGINE=InnoDB;

CREATE TABLE payment (
  payment_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pickup_id BIGINT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  method ENUM('CASH','CARD','CHECK','OTHER') NOT NULL,
  paid_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_payment_pickup FOREIGN KEY (pickup_id) REFERENCES pickup_transaction(pickup_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE counseling_session (
  counsel_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  fill_id BIGINT NOT NULL,
  pharmacist_id BIGINT NOT NULL,
  counsel_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  accepted_flag TINYINT(1) NOT NULL DEFAULT 1,
  notes TEXT,
  UNIQUE KEY uq_counsel_fill (fill_id),
  CONSTRAINT fk_counsel_fill  FOREIGN KEY (fill_id) REFERENCES dispense_fill(fill_id),
  CONSTRAINT fk_counsel_rph   FOREIGN KEY (pharmacist_id) REFERENCES pharmacist(employee_id)
) ENGINE=InnoDB;

CREATE TABLE signature_log (
  signature_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pickup_id BIGINT NOT NULL,
  signed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  signature_type ENUM('PATIENT','CAREGIVER') NOT NULL DEFAULT 'PATIENT',
  CONSTRAINT fk_sig_pickup FOREIGN KEY (pickup_id) REFERENCES pickup_transaction(pickup_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =========================================================
-- INVENTORY / PURCHASING TABLES
-- =========================================================

CREATE TABLE supplier (
  supplier_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  supplier_code VARCHAR(40) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(25)
) ENGINE=InnoDB;

CREATE TABLE purchase_order (
  po_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pharmacy_id BIGINT NOT NULL,
  supplier_id BIGINT NOT NULL,
  po_number VARCHAR(40) NOT NULL,
  order_date DATE NOT NULL,
  status ENUM('DRAFT','SUBMITTED','RECEIVED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  UNIQUE KEY uq_po (pharmacy_id, po_number),
  CONSTRAINT fk_po_pharmacy FOREIGN KEY (pharmacy_id) REFERENCES pharmacy(pharmacy_id),
  CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
) ENGINE=InnoDB;

CREATE TABLE purchase_order_line (
  po_id BIGINT NOT NULL,
  line_no INT NOT NULL,
  drug_id BIGINT NOT NULL,
  qty_ordered DECIMAL(12,3) NOT NULL,
  unit_cost DECIMAL(12,4) NOT NULL,
  PRIMARY KEY (po_id, line_no),
  CONSTRAINT fk_pol_po   FOREIGN KEY (po_id) REFERENCES purchase_order(po_id) ON DELETE CASCADE,
  CONSTRAINT fk_pol_drug FOREIGN KEY (drug_id) REFERENCES drug(drug_id)
) ENGINE=InnoDB;

CREATE TABLE receiving_event (
  receiving_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  po_id BIGINT NOT NULL,
  received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  received_by_employee_id BIGINT,
  CONSTRAINT fk_recv_po  FOREIGN KEY (po_id) REFERENCES purchase_order(po_id),
  CONSTRAINT fk_recv_emp FOREIGN KEY (received_by_employee_id) REFERENCES employee(employee_id)
) ENGINE=InnoDB;

CREATE TABLE inventory_item (
  inventory_item_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  pharmacy_id BIGINT NOT NULL,
  drug_id BIGINT NOT NULL,
  on_hand_qty DECIMAL(12,3) NOT NULL DEFAULT 0,
  reorder_point DECIMAL(12,3) NOT NULL DEFAULT 0,
  reorder_qty DECIMAL(12,3) NOT NULL DEFAULT 0,
  UNIQUE KEY uq_inv_item (pharmacy_id, drug_id),
  CONSTRAINT fk_inv_pharmacy FOREIGN KEY (pharmacy_id) REFERENCES pharmacy(pharmacy_id),
  CONSTRAINT fk_inv_drug     FOREIGN KEY (drug_id)     REFERENCES drug(drug_id)
) ENGINE=InnoDB;

CREATE TABLE inventory_lot (
  lot_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  inventory_item_id BIGINT NOT NULL,
  lot_number VARCHAR(60) NOT NULL,
  expiration_date DATE,
  qty_on_hand DECIMAL(12,3) NOT NULL DEFAULT 0,
  UNIQUE KEY uq_lot (inventory_item_id, lot_number),
  CONSTRAINT fk_lot_item FOREIGN KEY (inventory_item_id) REFERENCES inventory_item(inventory_item_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE inventory_transaction (
  inv_txn_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  inventory_item_id BIGINT NOT NULL,
  lot_id BIGINT NULL,
  txn_type ENUM('RECEIPT','DISPENSE','ADJUSTMENT','RETURN','TRANSFER') NOT NULL,
  qty_change DECIMAL(12,3) NOT NULL,
  txn_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  related_po_id BIGINT NULL,
  related_fill_id BIGINT NULL,
  CONSTRAINT fk_invtxn_item FOREIGN KEY (inventory_item_id) REFERENCES inventory_item(inventory_item_id),
  CONSTRAINT fk_invtxn_lot  FOREIGN KEY (lot_id) REFERENCES inventory_lot(lot_id),
  CONSTRAINT fk_invtxn_po   FOREIGN KEY (related_po_id) REFERENCES purchase_order(po_id),
  CONSTRAINT fk_invtxn_fill FOREIGN KEY (related_fill_id) REFERENCES dispense_fill(fill_id)
) ENGINE=InnoDB;

-- =========================================================
-- CLINICAL / DUR TABLES
-- =========================================================

CREATE TABLE allergy (
  allergy_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  allergen_name VARCHAR(120) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE patient_allergy (
  patient_id BIGINT NOT NULL,
  allergy_id BIGINT NOT NULL,
  severity ENUM('MILD','MODERATE','SEVERE') NULL,
  reaction VARCHAR(120),
  noted_date DATE,
  PRIMARY KEY (patient_id, allergy_id),
  CONSTRAINT fk_pa_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id) ON DELETE CASCADE,
  CONSTRAINT fk_pa_allergy FOREIGN KEY (allergy_id) REFERENCES allergy(allergy_id)
) ENGINE=InnoDB;

CREATE TABLE interaction_rule (
  rule_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  drug_a_id BIGINT NOT NULL,
  drug_b_id BIGINT NOT NULL,
  severity ENUM('MINOR','MODERATE','MAJOR','CONTRAINDICATED') NOT NULL,
  description TEXT,
  UNIQUE KEY uq_drug_pair (drug_a_id, drug_b_id),
  CONSTRAINT fk_ir_a FOREIGN KEY (drug_a_id) REFERENCES drug(drug_id),
  CONSTRAINT fk_ir_b FOREIGN KEY (drug_b_id) REFERENCES drug(drug_id)
) ENGINE=InnoDB;

CREATE TABLE dur_alert (
  dur_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  fill_id BIGINT NOT NULL,
  patient_id BIGINT NOT NULL,
  rule_id BIGINT NULL,
  alert_type ENUM('INTERACTION','ALLERGY','DUPLICATE','CONTRA') NOT NULL,
  severity ENUM('MINOR','MODERATE','MAJOR','CONTRAINDICATED') NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status ENUM('OPEN','REVIEWED','RESOLVED','OVERRIDDEN') NOT NULL DEFAULT 'OPEN',
  CONSTRAINT fk_dur_fill    FOREIGN KEY (fill_id)   REFERENCES dispense_fill(fill_id),
  CONSTRAINT fk_dur_patient FOREIGN KEY (patient_id) REFERENCES patient(patient_id),
  CONSTRAINT fk_dur_rule    FOREIGN KEY (rule_id)   REFERENCES interaction_rule(rule_id)
) ENGINE=InnoDB;

-- =========================================================
-- CLAIMS TABLE
-- =========================================================

CREATE TABLE claim (
  claim_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  fill_id BIGINT NOT NULL,
  plan_id BIGINT NOT NULL,
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status ENUM('SUBMITTED','PAID','REJECTED','REVERSED') NOT NULL DEFAULT 'SUBMITTED',
  paid_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  patient_copay DECIMAL(12,2) NOT NULL DEFAULT 0,
  UNIQUE KEY uq_claim_fill (fill_id),
  CONSTRAINT fk_claim_fill FOREIGN KEY (fill_id) REFERENCES dispense_fill(fill_id),
  CONSTRAINT fk_claim_plan FOREIGN KEY (plan_id) REFERENCES insurance_plan(plan_id)
) ENGINE=InnoDB;

-- =========================================================
-- METADATA DICTIONARY
-- =========================================================

CREATE TABLE metadata_dictionary (
  meta_id BIGINT AUTO_INCREMENT PRIMARY KEY,

  table_schema VARCHAR(64) NOT NULL DEFAULT 'Pharmas',
  table_name VARCHAR(64) NOT NULL,
  column_name VARCHAR(64) NULL, -- NULL = table-level metadata

  business_name VARCHAR(150) NULL,
  description TEXT NOT NULL,

  data_type VARCHAR(64) NULL,
  char_max_length INT NULL,
  numeric_precision INT NULL,
  numeric_scale INT NULL,
  is_nullable ENUM('YES','NO') NULL,
  column_default VARCHAR(255) NULL,

  is_primary_key TINYINT(1) NOT NULL DEFAULT 0,
  is_foreign_key TINYINT(1) NOT NULL DEFAULT 0,
  reference_table VARCHAR(64) NULL,
  reference_column VARCHAR(64) NULL,

  sensitivity_level ENUM('PUBLIC','INTERNAL','CONFIDENTIAL','PHI') NOT NULL DEFAULT 'INTERNAL',
  domain_tags VARCHAR(255) NULL,
  source_system VARCHAR(120) NULL,
  created_by VARCHAR(120) NULL,

  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uq_meta (table_schema, table_name, column_name)
) ENGINE=InnoDB;

-- =========================================================
-- SEED DATA
-- =========================================================

-- 1) ADDRESS (60)
INSERT INTO address (line1, line2, city, state, zip)
SELECT CONCAT(n.n, ' Main St'), NULL, 'Miami', 'FL', LPAD(n.n, 5, '0')
FROM (
  SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
  UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
  UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
  UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL SELECT 23 UNION ALL SELECT 24 UNION ALL SELECT 25
  UNION ALL SELECT 26 UNION ALL SELECT 27 UNION ALL SELECT 28 UNION ALL SELECT 29 UNION ALL SELECT 30
  UNION ALL SELECT 31 UNION ALL SELECT 32 UNION ALL SELECT 33 UNION ALL SELECT 34 UNION ALL SELECT 35
  UNION ALL SELECT 36 UNION ALL SELECT 37 UNION ALL SELECT 38 UNION ALL SELECT 39 UNION ALL SELECT 40
  UNION ALL SELECT 41 UNION ALL SELECT 42 UNION ALL SELECT 43 UNION ALL SELECT 44 UNION ALL SELECT 45
  UNION ALL SELECT 46 UNION ALL SELECT 47 UNION ALL SELECT 48 UNION ALL SELECT 49 UNION ALL SELECT 50
  UNION ALL SELECT 51 UNION ALL SELECT 52 UNION ALL SELECT 53 UNION ALL SELECT 54 UNION ALL SELECT 55
  UNION ALL SELECT 56 UNION ALL SELECT 57 UNION ALL SELECT 58 UNION ALL SELECT 59 UNION ALL SELECT 60
) n;

-- 2) PHARMACY (2)
INSERT INTO pharmacy (npi, store_code, name, phone, address_id)
VALUES
('3333333333','STORE-003','Pharmas Midtown','305-555-0003',1),
('4444444444','STORE-004','Pharmas Downtown','305-555-0004',2);

-- 3) EMPLOYEE (10, split across 2 pharmacies)
INSERT INTO employee (pharmacy_id, employee_number, email, first_name, last_name, role)
SELECT
  CASE WHEN n.n <= 5 THEN 1 ELSE 2 END,
  CONCAT('E', LPAD(n.n, 4, '0')),
  CONCAT('emp', n.n, '@pharmas.com'),
  CONCAT('EmpFirst', n.n),
  CONCAT('EmpLast', n.n),
  CASE WHEN n.n <= 6 THEN 'PHARMACIST' ELSE 'TECH' END
FROM (
  SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
) n;

-- 4) PHARMACIST (employees 1..6)
INSERT INTO pharmacist (employee_id, license_number, dea_number)
SELECT n.n, CONCAT('LIC-', LPAD(n.n, 6, '0')), CONCAT('DEA', LPAD(n.n, 7, '0'))
FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6) n;

-- 5) PATIENT (20, addresses 11..30)
INSERT INTO patient (mrn, address_id, first_name, last_name, dob, phone)
SELECT
  CONCAT('MRN', LPAD(n.n, 6, '0')),
  10 + n.n,
  CONCAT('PatFirst', n.n),
  CONCAT('PatLast', n.n),
  DATE_ADD('1990-01-01', INTERVAL (n.n * 30) DAY),
  CONCAT('305-777-', LPAD(n.n, 4, '0'))
FROM (
  SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
  UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
  UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
) n;

-- 6) PRESCRIBER (5, addresses 31..35)
INSERT INTO prescriber (npi, name, specialty, address_id)
SELECT
  CONCAT('9', LPAD(n.n, 9, '0')),
  CONCAT('Dr. Prescriber ', n.n),
  CASE n.n
    WHEN 1 THEN 'Family Medicine'
    WHEN 2 THEN 'Internal Medicine'
    WHEN 3 THEN 'Cardiology'
    WHEN 4 THEN 'Pulmonology'
    ELSE 'Oncology'
  END,
  30 + n.n
FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) n;

-- 7) DRUG (10)
INSERT INTO drug (ndc11, generic_name, brand_name, dosage_form)
SELECT
  LPAD(n.n, 11, '0'),
  CONCAT('GenericDrug', n.n),
  CONCAT('BrandDrug', n.n),
  CASE
    WHEN MOD(n.n, 3) = 0 THEN 'CAPSULE'
    WHEN MOD(n.n, 3) = 1 THEN 'TABLET'
    ELSE 'SOLUTION'
  END
FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n;

-- 8) INSURANCE_PLAN (10)
INSERT INTO insurance_plan (bin, pcn, group_id, plan_name)
SELECT
  CONCAT('0', LPAD(n.n, 5, '0')),
  CONCAT('PCN', LPAD(n.n, 3, '0')),
  CONCAT('GRP', LPAD(n.n, 3, '0')),
  CONCAT('Plan ', n.n)
FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n;

-- 9) PRESCRIPTION (20; first 10 at pharmacy 1, next 10 at pharmacy 2)
INSERT INTO prescription (pharmacy_id, patient_id, prescriber_id, rx_number, written_date, status)
SELECT
  CASE WHEN n.n <= 10 THEN 1 ELSE 2 END,
  n.n,
  MOD(n.n - 1, 5) + 1,
  CONCAT('RX-', LPAD(n.n, 6, '0')),
  DATE_ADD('2026-01-01', INTERVAL n.n DAY),
  CASE
    WHEN MOD(n.n, 6)=0 THEN 'COMPLETED'
    WHEN MOD(n.n, 6)=1 THEN 'NEW'
    WHEN MOD(n.n, 6)=2 THEN 'ACTIVE'
    WHEN MOD(n.n, 6)=3 THEN 'ON_HOLD'
    WHEN MOD(n.n, 6)=4 THEN 'CANCELLED'
    ELSE 'EXPIRED'
  END
FROM (
  SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
  UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
  UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
) n;

-- 10) PATIENT_INSURANCE (20 primaries)
INSERT INTO patient_insurance (patient_id, plan_id, member_id, effective_start, effective_end, is_primary)
SELECT
  p.patient_id,
  MOD(p.patient_id - 1, 10) + 1,
  CONCAT('MBR', LPAD(p.patient_id, 6, '0')),
  '2025-01-01',
  NULL,
  1
FROM patient p
WHERE p.patient_id BETWEEN 1 AND 20;

-- 11) PRESCRIPTION_ITEM (1 per RX, 20)
INSERT INTO prescription_item (rx_id, item_no, drug_id, sig, qty_prescribed, days_supply, refills_authorized)
SELECT
  rx.rx_id,
  1,
  MOD(rx.rx_id - 1, 10) + 1,
  CONCAT('Take 1 by mouth daily (RX ', rx.rx_id, ')'),
  30.000,
  30,
  2
FROM prescription rx
ORDER BY rx.rx_id
LIMIT 20;

-- 12) DISPENSE_FILL (20)
INSERT INTO dispense_fill (rx_id, pharmacist_id, fill_date, quantity)
SELECT
  r.rx_id,
  ph.employee_id,
  DATE_ADD('2026-01-05', INTERVAL r.rn DAY),
  30.000
FROM (
  SELECT rx_id, ROW_NUMBER() OVER (ORDER BY rx_id) rn
  FROM prescription
  ORDER BY rx_id
  LIMIT 20
) r
JOIN (
  SELECT employee_id, ROW_NUMBER() OVER (ORDER BY employee_id) rn
  FROM pharmacist
) ph
  ON ph.rn = (MOD(r.rn - 1, (SELECT COUNT(*) FROM pharmacist)) + 1);

-- 13) FILL_ITEM (2 items per fill -> 40)
INSERT INTO fill_item (fill_id, item_no, drug_id, qty_dispensed)
SELECT
  f.fill_id,
  i.item_no,
  d.drug_id,
  CASE WHEN i.item_no = 1 THEN 30.000 ELSE 60.000 END
FROM (SELECT fill_id, ROW_NUMBER() OVER (ORDER BY fill_id) rn
      FROM dispense_fill ORDER BY fill_id LIMIT 20) f
CROSS JOIN (SELECT 1 item_no UNION ALL SELECT 2) i
JOIN (SELECT drug_id, ROW_NUMBER() OVER (ORDER BY drug_id) rn FROM drug ORDER BY drug_id LIMIT 10) d
  ON d.rn = (MOD(f.rn + i.item_no - 1, 10) + 1);

-- 14) PICKUP_TRANSACTION (20)
INSERT INTO pickup_transaction (fill_id, picked_up_by_patient_id, pickup_time, id_verified)
SELECT
  f.fill_id,
  rx.patient_id,
  DATE_ADD('2026-01-06', INTERVAL f.rn DAY),
  1
FROM (SELECT fill_id, rx_id, ROW_NUMBER() OVER (ORDER BY fill_id) rn
      FROM dispense_fill ORDER BY fill_id LIMIT 20) f
JOIN prescription rx ON rx.rx_id = f.rx_id;

-- 15) PAYMENT (20)
INSERT INTO payment (pickup_id, amount, method, paid_at)
SELECT
  pt.pickup_id,
  25.00 + MOD(pt.pickup_id, 4) * 5.00,
  CASE MOD(pt.pickup_id, 4)
    WHEN 0 THEN 'CASH'
    WHEN 1 THEN 'CARD'
    WHEN 2 THEN 'CHECK'
    ELSE 'OTHER'
  END,
  DATE_ADD(pt.pickup_time, INTERVAL 10 MINUTE)
FROM pickup_transaction pt
ORDER BY pt.pickup_id
LIMIT 20;

-- 16) SIGNATURE_LOG (20)
INSERT INTO signature_log (pickup_id, signed_at, signature_type)
SELECT
  pt.pickup_id,
  DATE_ADD(pt.pickup_time, INTERVAL 5 MINUTE),
  'PATIENT'
FROM pickup_transaction pt
ORDER BY pt.pickup_id
LIMIT 20;

-- 17) COUNSELING_SESSION (20; unique per fill)
INSERT INTO counseling_session (fill_id, pharmacist_id, counsel_time, accepted_flag, notes)
SELECT
  f.fill_id,
  f.pharmacist_id,
  DATE_ADD(f.fill_date, INTERVAL 2 HOUR),
  1,
  'Standard counseling provided.'
FROM dispense_fill f
ORDER BY f.fill_id
LIMIT 20;

-- 18) CLAIM (20; uses primary insurance)
INSERT INTO claim (fill_id, plan_id, submitted_at, status, paid_amount, patient_copay)
SELECT
  f.fill_id,
  pi.plan_id,
  DATE_ADD(f.fill_date, INTERVAL 1 DAY),
  CASE
    WHEN MOD(f.fill_id, 7) = 0 THEN 'REJECTED'
    WHEN MOD(f.fill_id, 11) = 0 THEN 'REVERSED'
    ELSE 'PAID'
  END,
  CASE
    WHEN MOD(f.fill_id, 7) = 0 THEN 0.00
    WHEN MOD(f.fill_id, 11) = 0 THEN 0.00
    ELSE 75.00
  END,
  CASE
    WHEN MOD(f.fill_id, 7) = 0 THEN 0.00
    WHEN MOD(f.fill_id, 11) = 0 THEN 0.00
    ELSE 15.00
  END
FROM dispense_fill f
JOIN prescription rx ON rx.rx_id = f.rx_id
JOIN patient_insurance pi ON pi.patient_id = rx.patient_id AND pi.is_primary = 1
LEFT JOIN claim c ON c.fill_id = f.fill_id
WHERE c.fill_id IS NULL
ORDER BY f.fill_id
LIMIT 20;

-- 19) REFILL_REQUEST (20)
INSERT INTO refill_request (rx_id, patient_id, requested_at, status, notes)
SELECT
  rx.rx_id,
  rx.patient_id,
  DATE_ADD(rx.written_date, INTERVAL 20 DAY),
  'REQUESTED',
  'Auto-generated refill request for testing.'
FROM prescription rx
ORDER BY rx.rx_id
LIMIT 20;

-- 20) RX_STATUS_HISTORY (20)
INSERT INTO rx_status_history (rx_id, status, changed_at, changed_by_employee_id)
SELECT
  rx.rx_id,
  CASE
    WHEN MOD(rx.rx_id,4)=0 THEN 'COMPLETED'
    WHEN MOD(rx.rx_id,4)=1 THEN 'NEW'
    WHEN MOD(rx.rx_id,4)=2 THEN 'ACTIVE'
    ELSE 'ON_HOLD'
  END,
  DATE_ADD(rx.written_date, INTERVAL 1 DAY),
  e.employee_id
FROM prescription rx
JOIN (SELECT employee_id, ROW_NUMBER() OVER (ORDER BY employee_id) rn FROM employee) e
  ON e.rn = (MOD(rx.rx_id - 1, (SELECT COUNT(*) FROM employee)) + 1)
ORDER BY rx.rx_id
LIMIT 20;

-- =========================================================
-- MISSING INSERTS: DUR + INVENTORY/PURCHASING
-- =========================================================

-- A) ALLERGY (10)
INSERT INTO allergy (allergen_name)
SELECT a.allergen_name
FROM (
  SELECT 'Penicillin' allergen_name UNION ALL
  SELECT 'Sulfa Drugs' UNION ALL
  SELECT 'Peanuts' UNION ALL
  SELECT 'Shellfish' UNION ALL
  SELECT 'Latex' UNION ALL
  SELECT 'NSAIDs' UNION ALL
  SELECT 'Codeine' UNION ALL
  SELECT 'Eggs' UNION ALL
  SELECT 'Iodine' UNION ALL
  SELECT 'Milk'
) a
LEFT JOIN allergy x ON x.allergen_name = a.allergen_name
WHERE x.allergen_name IS NULL;

-- B) PATIENT_ALLERGY (30)
INSERT INTO patient_allergy (patient_id, allergy_id, severity, reaction, noted_date)
SELECT
  t.patient_id,
  t.allergy_id,
  CASE (t.rn % 3)
    WHEN 0 THEN 'MILD'
    WHEN 1 THEN 'MODERATE'
    ELSE 'SEVERE'
  END,
  CONCAT('Reaction ', t.rn),
  DATE_ADD('2025-01-01', INTERVAL t.rn DAY)
FROM (
  SELECT
    p.patient_id,
    a.allergy_id,
    ROW_NUMBER() OVER (ORDER BY p.patient_id, a.allergy_id) rn
  FROM (SELECT patient_id FROM patient ORDER BY patient_id LIMIT 20) p
  CROSS JOIN (SELECT allergy_id FROM allergy ORDER BY allergy_id LIMIT 10) a
) t
LEFT JOIN patient_allergy pa
  ON pa.patient_id = t.patient_id AND pa.allergy_id = t.allergy_id
WHERE t.rn <= 30
  AND pa.patient_id IS NULL;

-- C) INTERACTION_RULE (9 consecutive pairs from first 10 drugs; generates 9 rows)
INSERT INTO interaction_rule (drug_a_id, drug_b_id, severity, description)
SELECT
  a.drug_id,
  b.drug_id,
  CASE (a.rn % 4)
    WHEN 0 THEN 'MINOR'
    WHEN 1 THEN 'MODERATE'
    WHEN 2 THEN 'MAJOR'
    ELSE 'CONTRAINDICATED'
  END,
  CONCAT('Auto rule between drug ', a.drug_id, ' and drug ', b.drug_id)
FROM (SELECT drug_id, ROW_NUMBER() OVER (ORDER BY drug_id) rn FROM drug ORDER BY drug_id LIMIT 10) a
JOIN (SELECT drug_id, ROW_NUMBER() OVER (ORDER BY drug_id) rn FROM drug ORDER BY drug_id LIMIT 10) b
  ON b.rn = a.rn + 1
LEFT JOIN interaction_rule ir
  ON ir.drug_a_id = a.drug_id AND ir.drug_b_id = b.drug_id
WHERE ir.rule_id IS NULL;

-- D) DUR_ALERT (20)
INSERT INTO dur_alert (fill_id, patient_id, rule_id, alert_type, severity, created_at, status)
SELECT
  f.fill_id,
  rx.patient_id,
  CASE WHEN MOD(f.rn, 2) = 0 THEN ir.rule_id ELSE NULL END,
  CASE WHEN MOD(f.rn, 2) = 0 THEN 'INTERACTION' ELSE 'ALLERGY' END,
  CASE
    WHEN MOD(f.rn, 4) = 0 THEN 'MINOR'
    WHEN MOD(f.rn, 4) = 1 THEN 'MODERATE'
    WHEN MOD(f.rn, 4) = 2 THEN 'MAJOR'
    ELSE 'CONTRAINDICATED'
  END,
  DATE_ADD(f.fill_date, INTERVAL 1 HOUR),
  CASE
    WHEN MOD(f.rn, 5) = 0 THEN 'RESOLVED'
    WHEN MOD(f.rn, 5) = 1 THEN 'REVIEWED'
    WHEN MOD(f.rn, 5) = 2 THEN 'OPEN'
    ELSE 'OVERRIDDEN'
  END
FROM (
  SELECT fill_id, rx_id, fill_date, ROW_NUMBER() OVER (ORDER BY fill_id) rn
  FROM dispense_fill
  ORDER BY fill_id
  LIMIT 20
) f
JOIN prescription rx ON rx.rx_id = f.rx_id
LEFT JOIN (SELECT rule_id, ROW_NUMBER() OVER (ORDER BY rule_id) rn FROM interaction_rule) ir
  ON ir.rn = (MOD(f.rn - 1, (SELECT COUNT(*) FROM interaction_rule)) + 1)
LEFT JOIN dur_alert da ON da.fill_id = f.fill_id
WHERE da.dur_id IS NULL;

-- E) SUPPLIER (5)
INSERT INTO supplier (supplier_code, name, phone)
SELECT s.supplier_code, s.name, s.phone
FROM (
  SELECT 'SUP-001' supplier_code, 'MedSupply One' name, '305-888-0001' phone UNION ALL
  SELECT 'SUP-002', 'Health Wholesale', '305-888-0002' UNION ALL
  SELECT 'SUP-003', 'Rx Distributors', '305-888-0003' UNION ALL
  SELECT 'SUP-004', 'Coastal Pharma Supply', '305-888-0004' UNION ALL
  SELECT 'SUP-005', 'Sunshine Med Logistics', '305-888-0005'
) s
LEFT JOIN supplier x ON x.supplier_code = s.supplier_code
WHERE x.supplier_code IS NULL;

-- F) PURCHASE_ORDER (10)
INSERT INTO purchase_order (pharmacy_id, supplier_id, po_number, order_date, status)
SELECT
  ph.pharmacy_id,
  sup.supplier_id,
  CONCAT('PO-', LPAD(t.rn, 5, '0')),
  DATE_ADD('2026-01-01', INTERVAL t.rn DAY),
  CASE (t.rn % 4)
    WHEN 0 THEN 'DRAFT'
    WHEN 1 THEN 'SUBMITTED'
    WHEN 2 THEN 'RECEIVED'
    ELSE 'CANCELLED'
  END
FROM (
  SELECT ROW_NUMBER() OVER (ORDER BY x.n) rn, x.n
  FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) x
) t
JOIN (SELECT pharmacy_id, ROW_NUMBER() OVER (ORDER BY pharmacy_id) rn FROM pharmacy ORDER BY pharmacy_id LIMIT 2) ph
  ON ph.rn = (MOD(t.rn - 1, 2) + 1)
JOIN (SELECT supplier_id, ROW_NUMBER() OVER (ORDER BY supplier_id) rn FROM supplier ORDER BY supplier_id LIMIT 5) sup
  ON sup.rn = (MOD(t.rn - 1, 5) + 1)
LEFT JOIN purchase_order po
  ON po.pharmacy_id = ph.pharmacy_id AND po.po_number = CONCAT('PO-', LPAD(t.rn, 5, '0'))
WHERE po.po_id IS NULL;

-- G) PURCHASE_ORDER_LINE (2 per PO -> 20)
INSERT INTO purchase_order_line (po_id, line_no, drug_id, qty_ordered, unit_cost)
SELECT
  po.po_id,
  l.line_no,
  d.drug_id,
  CASE WHEN l.line_no = 1 THEN 100.000 ELSE 200.000 END,
  12.5000 + (d.drug_id % 5)
FROM (SELECT po_id, ROW_NUMBER() OVER (ORDER BY po_id) rn FROM purchase_order ORDER BY po_id LIMIT 10) po
CROSS JOIN (SELECT 1 line_no UNION ALL SELECT 2) l
JOIN (SELECT drug_id, ROW_NUMBER() OVER (ORDER BY drug_id) rn FROM drug ORDER BY drug_id LIMIT 10) d
  ON d.rn = (MOD(po.rn + l.line_no - 1, 10) + 1)
LEFT JOIN purchase_order_line pol
  ON pol.po_id = po.po_id AND pol.line_no = l.line_no
WHERE pol.po_id IS NULL;

-- H) RECEIVING_EVENT (10)
INSERT INTO receiving_event (po_id, received_at, received_by_employee_id)
SELECT
  po.po_id,
  DATE_ADD(po.order_date, INTERVAL 2 DAY),
  e.employee_id
FROM (SELECT po_id, order_date, ROW_NUMBER() OVER (ORDER BY po_id) rn FROM purchase_order ORDER BY po_id LIMIT 10) po
LEFT JOIN (SELECT employee_id, ROW_NUMBER() OVER (ORDER BY employee_id) rn FROM employee) e
  ON e.rn = (MOD(po.rn - 1, (SELECT COUNT(*) FROM employee)) + 1)
LEFT JOIN receiving_event r ON r.po_id = po.po_id
WHERE r.receiving_id IS NULL;

-- I) INVENTORY_ITEM (2 pharmacies x 10 drugs -> 20)
INSERT INTO inventory_item (pharmacy_id, drug_id, on_hand_qty, reorder_point, reorder_qty)
SELECT
  ph.pharmacy_id,
  d.drug_id,
  500.000,
  100.000,
  300.000
FROM (SELECT pharmacy_id FROM pharmacy ORDER BY pharmacy_id LIMIT 2) ph
CROSS JOIN (SELECT drug_id FROM drug ORDER BY drug_id LIMIT 10) d
LEFT JOIN inventory_item ii
  ON ii.pharmacy_id = ph.pharmacy_id AND ii.drug_id = d.drug_id
WHERE ii.inventory_item_id IS NULL;

-- J) INVENTORY_LOT (2 lots per first 15 inventory items -> 30)
INSERT INTO inventory_lot (inventory_item_id, lot_number, expiration_date, qty_on_hand)
SELECT
  ii.inventory_item_id,
  CONCAT('LOT-', LPAD(ii.rn, 4, '0'), '-', l.lot_no),
  DATE_ADD('2027-01-01', INTERVAL (ii.rn * 10) DAY),
  250.000
FROM (
  SELECT inventory_item_id, ROW_NUMBER() OVER (ORDER BY inventory_item_id) rn
  FROM inventory_item
  ORDER BY inventory_item_id
  LIMIT 15
) ii
CROSS JOIN (SELECT 'A' lot_no UNION ALL SELECT 'B') l
LEFT JOIN inventory_lot il
  ON il.inventory_item_id = ii.inventory_item_id
 AND il.lot_number = CONCAT('LOT-', LPAD(ii.rn, 4, '0'), '-', l.lot_no)
WHERE il.lot_id IS NULL;

-- K1) INVENTORY_TRANSACTION RECEIPT (from PO lines; 20)
INSERT INTO inventory_transaction
  (inventory_item_id, lot_id, txn_type, qty_change, txn_time, related_po_id, related_fill_id)
SELECT
  ii.inventory_item_id,
  il.lot_id,
  'RECEIPT',
  pol.qty_ordered,
  DATE_ADD(po.order_date, INTERVAL 3 DAY),
  po.po_id,
  NULL
FROM purchase_order_line pol
JOIN purchase_order po ON po.po_id = pol.po_id
JOIN inventory_item ii
  ON ii.pharmacy_id = po.pharmacy_id AND ii.drug_id = pol.drug_id
LEFT JOIN (
  SELECT lot_id, inventory_item_id,
         ROW_NUMBER() OVER (PARTITION BY inventory_item_id ORDER BY lot_id) rn
  FROM inventory_lot
) il
  ON il.inventory_item_id = ii.inventory_item_id AND il.rn = 1
LEFT JOIN inventory_transaction it
  ON it.related_po_id = po.po_id
 AND it.inventory_item_id = ii.inventory_item_id
 AND it.txn_type = 'RECEIPT'
WHERE it.inv_txn_id IS NULL
ORDER BY po.po_id, pol.line_no
LIMIT 20;

-- K2) INVENTORY_TRANSACTION DISPENSE (from fills; 20)
INSERT INTO inventory_transaction
  (inventory_item_id, lot_id, txn_type, qty_change, txn_time, related_po_id, related_fill_id)
SELECT
  ii.inventory_item_id,
  il.lot_id,
  'DISPENSE',
  -fi.qty_dispensed,
  df.fill_date,
  NULL,
  df.fill_id
FROM (SELECT fill_id, rx_id, fill_date FROM dispense_fill ORDER BY fill_id LIMIT 20) df
JOIN fill_item fi ON fi.fill_id = df.fill_id AND fi.item_no = 1
JOIN prescription rx ON rx.rx_id = df.rx_id
JOIN inventory_item ii ON ii.pharmacy_id = rx.pharmacy_id AND ii.drug_id = fi.drug_id
LEFT JOIN (
  SELECT lot_id, inventory_item_id,
         ROW_NUMBER() OVER (PARTITION BY inventory_item_id ORDER BY lot_id) rn
  FROM inventory_lot
) il
  ON il.inventory_item_id = ii.inventory_item_id AND il.rn = 1
LEFT JOIN inventory_transaction it
  ON it.related_fill_id = df.fill_id
 AND it.inventory_item_id = ii.inventory_item_id
 AND it.txn_type = 'DISPENSE'
WHERE it.inv_txn_id IS NULL
ORDER BY df.fill_id
LIMIT 20;

-- =========================================================
-- METADATA POPULATION (columns + table-level)
-- =========================================================

INSERT IGNORE INTO metadata_dictionary (
  table_schema, table_name, column_name,
  description,
  data_type, char_max_length, numeric_precision, numeric_scale,
  is_nullable, column_default,
  is_primary_key, is_foreign_key,
  reference_table, reference_column
)
SELECT
  c.table_schema,
  c.table_name,
  c.column_name,
  CONCAT('TODO: add business definition for ', c.table_name, '.', c.column_name),
  c.data_type,
  c.character_maximum_length,
  c.numeric_precision,
  c.numeric_scale,
  c.is_nullable,
  c.column_default,
  CASE WHEN tc.constraint_type = 'PRIMARY KEY' THEN 1 ELSE 0 END,
  CASE WHEN kcu.referenced_table_name IS NOT NULL THEN 1 ELSE 0 END,
  kcu.referenced_table_name,
  kcu.referenced_column_name
FROM information_schema.columns c
LEFT JOIN information_schema.key_column_usage kcu
  ON kcu.table_schema = c.table_schema
 AND kcu.table_name = c.table_name
 AND kcu.column_name = c.column_name
LEFT JOIN information_schema.table_constraints tc
  ON tc.table_schema = kcu.table_schema
 AND tc.table_name = kcu.table_name
 AND tc.constraint_name = kcu.constraint_name
WHERE c.table_schema = 'Pharmas';

INSERT INTO metadata_dictionary (table_schema, table_name, column_name, business_name, description, domain_tags, created_by)
SELECT 'Pharmas', t.table_name, NULL,
       CONCAT(UPPER(t.table_name), ' table'),
       CONCAT('Stores ', t.table_name, ' records for the retail/community pharmacy workflow.'),
       'Core',
       'Riley Yee'
FROM information_schema.tables t
WHERE t.table_schema = 'Pharmas'
  AND t.table_type = 'BASE TABLE'
  AND NOT EXISTS (
    SELECT 1 FROM metadata_dictionary md
    WHERE md.table_schema='Pharmas' AND md.table_name=t.table_name AND md.column_name IS NULL
  );

-- Example targeted metadata updates (optional)
UPDATE metadata_dictionary
SET business_name='Patient Identifier',
    description='System-generated unique identifier for a patient record.',
    sensitivity_level='PHI',
    domain_tags='Clinical,Identity'
WHERE table_schema='Pharmas' AND table_name='patient' AND column_name='patient_id';

UPDATE metadata_dictionary
SET business_name='Prescription Number',
    description='Pharmacy-assigned prescription number; unique within (pharmacy_id).',
    sensitivity_level='PHI',
    domain_tags='Clinical,Dispensing'
WHERE table_schema='Pharmas' AND table_name='prescription' AND column_name='rx_number';

-- =========================================================
-- QUICK CHECKS
-- =========================================================

SELECT 'pharmacy' tbl, COUNT(*) cnt FROM pharmacy
UNION ALL SELECT 'address', COUNT(*) FROM address
UNION ALL SELECT 'employee', COUNT(*) FROM employee
UNION ALL SELECT 'pharmacist', COUNT(*) FROM pharmacist
UNION ALL SELECT 'patient', COUNT(*) FROM patient
UNION ALL SELECT 'prescriber', COUNT(*) FROM prescriber
UNION ALL SELECT 'drug', COUNT(*) FROM drug
UNION ALL SELECT 'prescription', COUNT(*) FROM prescription
UNION ALL SELECT 'dispense_fill', COUNT(*) FROM dispense_fill
UNION ALL SELECT 'fill_item', COUNT(*) FROM fill_item
UNION ALL SELECT 'pickup_transaction', COUNT(*) FROM pickup_transaction
UNION ALL SELECT 'payment', COUNT(*) FROM payment
UNION ALL SELECT 'claim', COUNT(*) FROM claim
UNION ALL SELECT 'supplier', COUNT(*) FROM supplier
UNION ALL SELECT 'purchase_order', COUNT(*) FROM purchase_order
UNION ALL SELECT 'purchase_order_line', COUNT(*) FROM purchase_order_line
UNION ALL SELECT 'inventory_item', COUNT(*) FROM inventory_item
UNION ALL SELECT 'inventory_lot', COUNT(*) FROM inventory_lot
UNION ALL SELECT 'inventory_transaction', COUNT(*) FROM inventory_transaction
UNION ALL SELECT 'allergy', COUNT(*) FROM allergy
UNION ALL SELECT 'patient_allergy', COUNT(*) FROM patient_allergy
UNION ALL SELECT 'interaction_rule', COUNT(*) FROM interaction_rule
UNION ALL SELECT 'dur_alert', COUNT(*) FROM dur_alert
UNION ALL SELECT 'metadata_dictionary', COUNT(*) FROM metadata_dictionary;

-- Orphan checks (should return 0)
SELECT 'bad_employee_pharmacy' issue, COUNT(*) cnt
FROM employee e LEFT JOIN pharmacy p ON p.pharmacy_id = e.pharmacy_id
WHERE p.pharmacy_id IS NULL;

SELECT 'bad_fill_rx_or_rph' issue, COUNT(*) cnt
FROM dispense_fill f
LEFT JOIN prescription rx ON rx.rx_id = f.rx_id
LEFT JOIN pharmacist ph ON ph.employee_id = f.pharmacist_id
WHERE rx.rx_id IS NULL OR ph.employee_id IS NULL;

SELECT 'dup_rx_number' issue, COUNT(*) cnt
FROM (
  SELECT pharmacy_id, rx_number, COUNT(*) c
  FROM prescription
  GROUP BY pharmacy_id, rx_number
  HAVING COUNT(*) > 1
) x;

SELECT 'not_exactly_one_primary_ins' issue, COUNT(*) cnt
FROM (
  SELECT patient_id, SUM(is_primary) primaries
  FROM patient_insurance
  GROUP BY patient_id
  HAVING SUM(is_primary) <> 1
) x;

SHOW TABLES;