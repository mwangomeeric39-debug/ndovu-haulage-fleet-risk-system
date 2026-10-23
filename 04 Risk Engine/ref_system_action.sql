USE CATALOG fleet_catalog;

CREATE OR REPLACE TABLE fleet_catalog.risk.ref_system_action AS
SELECT * FROM VALUES
  ('Cooling', 'Pressure-test cooling system, replace hoses and thermostat, verify coolant level', 'Radiator hose kit, coolant 20L, thermostat', 4.0, 'P1 - within 4h'),
  ('Lubrication', 'Check oil level and pump pressure, replace oil filter, inspect bearings', 'Oil pump assembly, oil filter, engine oil 40L', 6.0, 'P1 - within 2h'),
  ('Transmission', 'Inspect gearbox oil level and temperature, scan TCU, inspect clutch', 'Gearbox oil 25L, clutch kit, transmission temp sensor', 5.0, 'P1 - within 4h'),
  ('Brakes', 'Replace brake linings on all axles, inspect drums and air lines', 'Brake lining set (x6), drum inspection kit', 4.0, 'P2 - within 8h'),
  ('Electrical', 'Load-test batteries and alternator, check wiring harness', 'Alternator, 12V batteries (x2)', 2.0, 'P3 - within 24h'),
  ('None', 'Pre-failure inspection (model flagged risk, no single sub-system dominant)', 'None until inspected', 2.0, 'P2 - within 8h')
AS t(system, recommended_action, parts_required, est_labour_hours, priority);