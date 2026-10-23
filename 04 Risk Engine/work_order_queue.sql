CREATE OR REPLACE VIEW fleet_catalog.risk.work_order_queue AS
SELECT
    CONCAT(
        'WO|', h.vehicle_id, '|',
        COALESCE(h.dtc_code, 'MODEL'), '|',
        DATE_FORMAT(h.snapshot_ts, 'yyyyMMdd')) AS alert_key,

    h.vehicle_id,
    h.reg_no,
    h.make_model,
    h.depot,

    CONCAT(
        a.priority, ' | ',
        h.reg_no, ' | ',
        h.suspect_system, ' | ',
        COALESCE(h.dtc_code, 'predictive')) AS ticket_title,

    a.priority,
    h.suspect_system,
    h.dtc_code,
    h.dtc_description,
    a.recommended_action,
    a.parts_required,
    a.est_labour_hours,
    h.reason,
    h.health_score,
    ROUND(h.failure_prob_48h, 2) AS failure_prob_48h,
    h.coolant_max_24h,
    h.oil_min_24h,
    h.trans_max_24h,
    h.brake_wear_pct,
    h.current_trip_id

FROM fleet_catalog.risk.vehicle_health_current h

JOIN fleet_catalog.risk.ref_system_action a
  ON a.system = h.suspect_system

WHERE h.dispatch_status = 'LOCK'
  AND NOT EXISTS (
      SELECT 1
      FROM fleet_catalog.risk.alert_log l
      WHERE l.alert_key = CONCAT(
          'WO|', h.vehicle_id, '|',
          COALESCE(h.dtc_code, 'MODEL'), '|',
          DATE_FORMAT(h.snapshot_ts, 'yyyyMMdd'))
      AND l.alert_type = 'WORK_ORDER');
