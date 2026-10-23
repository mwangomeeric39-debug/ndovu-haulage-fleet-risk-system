CREATE OR REPLACE VIEW fleet_catalog.risk.dispatch_lock_queue AS
SELECT
    CONCAT(
        h.vehicle_id, '|',
        h.dispatch_status, '|',
        COALESCE(h.dtc_code, 'MODEL'), '|',
        DATE_FORMAT(h.snapshot_ts, 'yyyyMMdd')) AS alert_key,
    h.vehicle_id,
    h.reg_no,
    h.make_model,
    h.depot,
    h.dispatch_status,
    h.health_score,
    h.health_band,
    ROUND(h.failure_prob_48h, 2) AS failure_prob_48h,
    h.reason,
    h.suspect_system,
    h.dtc_code,
    h.current_trip_id,

    IF( h.current_trip_id IS NOT NULL,
        'EN_ROUTE',
        'AT_DEPOT') AS location_state,

    CASE
        WHEN h.dispatch_status = 'LOCK'
            THEN 'Do NOT assign any trip until workshop clears the truck.'
        ELSE 'Restricted: short-haul (<200 km) only, workshop within 24h.'
    END AS dispatcher_instruction

FROM fleet_catalog.risk.vehicle_health_current h

WHERE h.dispatch_status IN ('LOCK', 'RESTRICT')
  AND NOT EXISTS (
      SELECT 1
      FROM fleet_catalog.risk.alert_log a
      WHERE a.alert_key = CONCAT(
          h.vehicle_id, '|',
          h.dispatch_status, '|',
          COALESCE(h.dtc_code, 'MODEL'), '|',
          DATE_FORMAT(h.snapshot_ts, 'yyyyMMdd'))
      AND a.alert_type = 'DISPATCH_LOCK');
