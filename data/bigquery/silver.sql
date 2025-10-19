CREATE TABLE IF NOT EXISTS `forward-cacao-466814-e0.silver_dataset.departments` (
    dept_id STRING,
    name STRING,
    is_quarantined BOOLEAN
);

-- 2. Truncate Silver Table Before Inserting 
TRUNCATE TABLE `forward-cacao-466814-e0.silver_dataset.departments`;

-- 3. full load 
INSERT INTO `forward-cacao-466814-e0.silver_dataset.departments`
SELECT DISTINCT 
    deptid,
    name,
    CASE 
        WHEN deptid IS NULL OR Name IS NULL THEN TRUE 
        ELSE FALSE 
    END AS is_quarantined
FROM (
    SELECT DISTINCT *  FROM `forward-cacao-466814-e0.bronze_dataset.departments`
);

-------------------------------------------------------------------------------------------------------

-- 1. Create table providers 
CREATE TABLE IF NOT EXISTS `forward-cacao-466814-e0.silver_dataset.providers` (
    ProviderID STRING,
    FirstName STRING,
    LastName STRING,
    Specialization STRING,
    DeptID STRING,
    NPI INT64,
    is_quarantined BOOLEAN
);

-- 2. Truncate Silver Table Before Inserting 
TRUNCATE TABLE `forward-cacao-466814-e0.silver_dataset.providers`;

-- 3. full load 
INSERT INTO `forward-cacao-466814-e0.silver_dataset.providers`
SELECT DISTINCT 
    ProviderID,
    FirstName,
    LastName,
    Specialization,
    DeptID,
    CAST(NPI AS INT64) AS NPI,
    CASE 
        WHEN ProviderID IS NULL OR DeptID IS NULL THEN TRUE 
        ELSE FALSE 
    END AS is_quarantined
FROM (
    SELECT DISTINCT * FROM `forward-cacao-466814-e0.bronze_dataset.providers`
 );

-------------------------------------------------------------------------------------------------------
-- patient tables
CREATE TABLE IF NOT EXISTS silver_dataset.patients (
  PatientID STRING NOT NULL,
  FirstName STRING,
  LastName STRING,
  MiddleName STRING,
  SSN STRING,
  PhoneNumber STRING,
  Gender STRING,
  DOB DATE,
  Address STRING,
  ModifiedDate TIMESTAMP,
  is_quarantined BOOLEAN,
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  is_current BOOLEAN,
  HashID_ChangeCheck STRING,
  SilverLoadTime TIMESTAMP
);

-- scd type2
MERGE INTO silver_dataset.patients AS target
USING (
  SELECT
    PatientID,
    FirstName,
    LastName,
    MiddleName,
    SSN,
    PhoneNumber,
    Gender,
    DATE(TIMESTAMP_MILLIS(CAST(DOB AS INT64))) AS DOB,
    Address,
    CURRENT_TIMESTAMP() AS CurrentLoadDate,
    IF(PatientID IS NULL OR SSN IS NULL, TRUE, FALSE) AS is_quarantined,
    TO_HEX(SHA256(CONCAT(
      IFNULL(FirstName, ''), IFNULL(LastName, ''), IFNULL(MiddleName, ''),
      IFNULL(SSN, ''), IFNULL(PhoneNumber, ''), IFNULL(Gender, ''),
      IFNULL(Address, '')
    ))) AS HashID_ChangeCheck
  FROM bronze_dataset.patients
) AS source
ON target.PatientID = source.PatientID AND target.is_current = TRUE

-- 1. Update old version if data changed
WHEN MATCHED AND target.HashID_ChangeCheck != source.HashID_ChangeCheck
THEN UPDATE SET
  target.end_date = TIMESTAMP_SUB(source.CurrentLoadDate, INTERVAL 1 MICROSECOND),
  target.is_current = FALSE,
  target.SilverLoadTime = source.CurrentLoadDate

-- 2. Insert new version
WHEN NOT MATCHED THEN
INSERT (
  PatientID, FirstName, LastName, MiddleName, SSN, PhoneNumber,
  Gender, DOB, Address, ModifiedDate, is_quarantined,
  start_date, end_date, is_current, HashID_ChangeCheck, SilverLoadTime
)
VALUES (
  source.PatientID, source.FirstName, source.LastName, source.MiddleName, source.SSN, source.PhoneNumber,
  source.Gender, source.DOB, source.Address, source.CurrentLoadDate, source.is_quarantined,
  source.CurrentLoadDate,
  TIMESTAMP('9999-12-31 23:59:59'),
  TRUE,
  source.HashID_ChangeCheck,
  source.CurrentLoadDate
)

-- 3. Soft delete missing records
WHEN NOT MATCHED BY SOURCE AND target.is_current = TRUE
THEN UPDATE SET
  target.end_date = TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 MICROSECOND),
  target.is_current = FALSE,
  target.SilverLoadTime = CURRENT_TIMESTAMP();

--------------------------------------------------
-- encounters table
CREATE TABLE IF NOT EXISTS `forward-cacao-466814-e0.silver_dataset.encounters` (
  EncounterID STRING,
  PatientID STRING,
  EncounterDate DATE,
  EncounterType STRING,
  ProviderID STRING,
  DepartmentID STRING,
  ProcedureCode INT64,
  InsertedDate DATE,
  ModifiedDate DATE,
  is_quarantined BOOLEAN
);
TRUNCATE TABLE `forward-cacao-466814-e0.silver_dataset.encounters`;
INSERT INTO `forward-cacao-466814-e0.silver_dataset.encounters`
SELECT DISTINCT 
  EncounterID,
  PatientID,
  DATE(TIMESTAMP_MILLIS(CAST(EncounterDate AS INT64))) AS EncounterDate,
  EncounterType,
  ProviderID,
  DepartmentID,
  CAST(ProcedureCode AS INT64) AS ProcedureCode,
  DATE(TIMESTAMP_MILLIS(CAST(InsertedDate AS INT64))) AS InsertedDate,
  DATE(TIMESTAMP_MILLIS(CAST(ModifiedDate AS INT64))) AS ModifiedDate,
  CASE 
    WHEN EncounterID IS NULL OR PatientID IS NULL OR ProviderID IS NULL THEN TRUE 
    ELSE FALSE 
  END AS is_quarantined
FROM (
  SELECT DISTINCT * FROM `forward-cacao-466814-e0.bronze_dataset.encounters`
);

--------------------------------------
CREATE TABLE IF NOT EXISTS `forward-cacao-466814-e0.silver_dataset.transactions` (
  TransactionID STRING,
  EncounterID STRING,
  PatientID STRING,
  ProviderID STRING,
  DeptID STRING,
  VisitDate DATE,
  ServiceDate DATE,
  PaidDate DATE,
  VisitType STRING,
  Amount FLOAT64,
  AmountType STRING,
  PaidAmount FLOAT64,
  ClaimID STRING,
  PayorID STRING,
  ProcedureCode INT64,
  ICDCode STRING,
  LineOfBusiness STRING,
  MedicaidID STRING,
  MedicareID STRING,
  InsertDate DATE,
  ModifiedDate DATE,
  is_quarantined BOOLEAN
);
TRUNCATE TABLE `forward-cacao-466814-e0.silver_dataset.transactions`;
INSERT INTO `forward-cacao-466814-e0.silver_dataset.transactions`
SELECT DISTINCT 
  TransactionID,
  EncounterID,
  PatientID,
  ProviderID,
  DeptID,
  DATE(TIMESTAMP_MILLIS(CAST(VisitDate AS INT64))) AS InserVisitDatetedDate,
  DATE(TIMESTAMP_MILLIS(CAST(ServiceDate AS INT64))) AS ServiceDate,
  DATE(TIMESTAMP_MILLIS(CAST(PaidDate AS INT64))) AS PaidDate,
  VisitType,
  CAST(Amount AS FLOAT64) AS Amount,
  AmountType,
  CAST(PaidAmount AS FLOAT64) AS PaidAmount,
  ClaimID,
  PayorID,
  CAST(ProcedureCode AS INT64) AS ProcedureCode,
  ICDCode,
  LineOfBusiness,
  MedicaidID,
  MedicareID,
  DATE(TIMESTAMP_MILLIS(CAST(InsertDate AS INT64))) AS InsertDate,
  DATE(TIMESTAMP_MILLIS(CAST(ModifiedDate AS INT64))) AS ModifiedDate,
  CASE 
    WHEN TransactionID IS NULL OR PatientID IS NULL OR EncounterID IS NULL THEN TRUE 
    ELSE FALSE 
  END AS is_quarantined
FROM (
  SELECT DISTINCT * FROM `forward-cacao-466814-e0.bronze_dataset.transactions`
);

CREATE TABLE IF NOT EXISTS
`forward-cacao-466814-e0.silver_dataset.claims` (
    claim_id STRING,
    transaction_id STRING,
    patient_id STRING,
    encounter_id STRING,
    provider_id STRING,
    dept_id STRING,
    service_date DATE,
    claim_date DATE,
    payor_id STRING,
    claim_amount NUMERIC,
    paid_amount NUMERIC,
    claim_status STRING,
    payor_type STRING,
    deductible NUMERIC,
    coinsurance NUMERIC,
    copay NUMERIC,
    insert_date TIMESTAMP,
    modified_date TIMESTAMP,
    is_quarantined BOOLEAN
);

---

-- 2. Truncate Silver Table Before Inserting 
TRUNCATE TABLE
`forward-cacao-466814-e0.silver_dataset.claims`;

---

-- 3. Full Load with Type Casting and Data Quality Check
INSERT INTO
`forward-cacao-466814-e0.silver_dataset.claims`
SELECT
    -- Directly select and rename fields
    t1.ClaimID AS claim_id,
    t1.TransactionID AS transaction_id,
    t1.PatientID AS patient_id,
    t1.EncounterID AS encounter_id,
    t1.ProviderID AS provider_id,
    t1.DeptID AS dept_id,
    
    -- Type Casting and basic transformation
    SAFE_CAST(t1.ServiceDate AS DATE) AS service_date,
    SAFE_CAST(t1.ClaimDate AS DATE) AS claim_date,
    
    t1.PayorID AS payor_id,
    
    -- Convert money strings to NUMERIC (adjust for specific money format if needed)
    SAFE_CAST(REPLACE(t1.ClaimAmount, '$', '') AS NUMERIC) AS claim_amount,
    SAFE_CAST(REPLACE(t1.PaidAmount, '$', '') AS NUMERIC) AS paid_amount,
    
    t1.ClaimStatus AS claim_status,
    t1.PayorType AS payor_type,
    
    SAFE_CAST(t1.Deductible AS NUMERIC) AS deductible,
    SAFE_CAST(t1.Coinsurance AS NUMERIC) AS coinsurance,
    SAFE_CAST(t1.Copay AS NUMERIC) AS copay,

    -- Convert insert/modified dates to TIMESTAMP
    SAFE_CAST(t1.InsertDate AS TIMESTAMP) AS insert_date,
    SAFE_CAST(t1.ModifiedDate AS TIMESTAMP) AS modified_date,
    
    -- Data Quality Check: Quarantines records missing essential IDs or amounts
    CASE 
        WHEN t1.ClaimID IS NULL 
        OR t1.TransactionID IS NULL 
        OR t1.PatientID IS NULL
        OR t1.ClaimAmount IS NULL
        OR t1.PaidAmount IS NULL
        THEN TRUE 
        ELSE FALSE 
    END AS is_quarantined
FROM
    `forward-cacao-466814-e0.bronze_dataset.claims` t1;
