CREATE TABLE IF NOT EXISTS `gold_dataset.encounter_summary` (
    DepartmentID STRING,
    DepartmentName STRING,
    Year INT,
    EncounterType STRING,
    TotalEncounters INT,
    UniquePatients INT,
    UniqueProcedures INT
);

TRUNCATE TABLE `gold_dataset.encounter_summary`;

INSERT INTO `gold_dataset.encounter_summary`
SELECT
  CAST(e.DepartmentID AS STRING) AS DepartmentID,
  d.name AS DepartmentName,
  EXTRACT(YEAR FROM e.EncounterDate) AS Year,
  e.EncounterType,
  COUNT(DISTINCT e.EncounterID) AS TotalEncounters,
  COUNT(DISTINCT e.PatientID) AS UniquePatients,
  COUNT(DISTINCT e.ProcedureCode) AS UniqueProcedures
FROM `silver_dataset.encounters` e
JOIN `silver_dataset.departments` d 
  ON e.DepartmentID = d.dept_id
GROUP BY 
  e.DepartmentID, d.name, Year, e.EncounterType;




CREATE TABLE IF NOT EXISTS `gold_dataset.provider_performance_summary` (
    ProviderID STRING,
    FirstName STRING,
    LastName STRING,
    Specialization STRING,
    TotalEncounters INT,
    AvgBilledAmount FLOAT64,
    AvgPaidAmount FLOAT64,
    ClaimApprovalRate FLOAT64
);

TRUNCATE TABLE `gold_dataset.provider_performance_summary`;

INSERT INTO `gold_dataset.provider_performance_summary`
SELECT
  p.ProviderID,
  p.FirstName,
  p.LastName,
  p.Specialization,
  COUNT(DISTINCT e.EncounterID) AS TotalEncounters,
  AVG(t.Amount) AS AvgBilledAmount,
  AVG(t.PaidAmount) AS AvgPaidAmount,
  ROUND(SUM(CASE WHEN c.claim_status = 'Approved' THEN 1 ELSE 0 END) / COUNT(c.claim_ID), 2) AS ClaimApprovalRate
FROM `.silver_dataset.providers` p
JOIN `.silver_dataset.encounters` e 
  ON p.ProviderID = e.ProviderID
JOIN `.silver_dataset.transactions` t 
  ON e.EncounterID = t.EncounterID
JOIN `.silver_dataset.claims` c 
  ON t.TransactionID = c.transaction_id
GROUP BY 
  p.ProviderID, p.FirstName, p.LastName, p.Specialization;




CREATE TABLE IF NOT EXISTS `gold_dataset.patient_billing_summary` (
    PatientID STRING,
    TotalEncounters INT,
    TotalBilled FLOAT64,
    TotalPaid FLOAT64,
    TotalClaims INT,
    AvgDeductible FLOAT64
);

TRUNCATE TABLE `gold_dataset.patient_billing_summary`;

INSERT INTO `gold_dataset.patient_billing_summary`
SELECT
  t.PatientID,
  COUNT(DISTINCT t.EncounterID) AS TotalEncounters,
  SUM(t.Amount) AS TotalBilled,
  SUM(t.PaidAmount) AS TotalPaid,
  COUNT(DISTINCT c.claim_ID) AS TotalClaims,
  AVG(c.Deductible) AS AvgDeductible
FROM `silver_dataset.transactions` t
JOIN `silver_dataset.claims` c 
  ON t.TransactionID = c.transaction_ID
GROUP BY t.PatientID;




CREATE TABLE IF NOT EXISTS `gold_dataset.claims_summary_by_status_payor` (
    claim_status STRING,
    payor_type STRING,
    Year INT,
    TotalClaims INT,
    TotalClaimAmount FLOAT64,
    TotalPaidAmount FLOAT64
);

TRUNCATE TABLE `gold_dataset.claims_summary_by_status_payor`;

INSERT INTO `gold_dataset.claims_summary_by_status_payor`
SELECT
  c.claim_status,
  c.payor_type,
  EXTRACT(YEAR FROM c.claim_date) AS Year,
  COUNT(c.claim_ID) AS TotalClaims,
  SUM(c.claim_amount) AS TotalClaimAmount,
  SUM(c.paid_amount) AS TotalPaidAmount
FROM `silver_dataset.claims` c
GROUP BY c.claim_status, c.payor_type, Year;



