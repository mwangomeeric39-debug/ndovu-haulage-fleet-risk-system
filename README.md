Ndovu Haulage — Automated Risk Alerts (n8n)
Overview
This workflow is designed to connect the Ndovu Haulage fleet-risk system in Databricks to operational notifications.

It will retrieve risk records from gold.risk_alert_queue, use Gemini AI to turn technical evidence into a clear explanation, send an email to the responsible team, and record the notification outcome so alerts can be monitored and duplicate emails can be avoided.

Status: Workflow design / implementation in progress. Do not treat alerts as operationally active until the connections, tests, and recipient rules have been validated.
Business objective
Help the fleet team respond to important risks sooner, including:
- Maintenance: vehicles that may need inspection or servicing.
- Fuel: suspicious transactions that require investigation.
- Dispatch: vehicles marked LOCK, RESTRICT, or CLEAR by the risk rules.
- Delivery delay: trips or deliveries that may need intervention.
Fuel-risk alerts are investigation signals, not proof of theft. A modelled failure probability is a risk estimate, not a confirmed mechanical failure.
Architecture
Databricks Gold
gold.risk_alert_queue
        |
        v
n8n Trigger
        |
        v
Fetch risk records from Databricks SQL
        |
        v
Filter / deduplicate alerts
        |
        v
Gemini AI — explain evidence and suggest next steps
        |
        v
Email the responsible team
        |
        v
Record notification outcome in gold.alert_log
        |
        v
Human investigation and follow-up in gold.risk_case
Power BI can be used alongside this workflow to monitor fleet status and risk trends. It is not required for the notification workflow itself.
Prerequisites
1. Access to the Databricks workspace containing the Ndovu Haulage Gold tables.
2. A Databricks SQL warehouse that can query gold.risk_alert_queue and write to the notification log if the workflow is configured to do so.
3. A Databricks personal access token or other supported authentication method, stored securely in n8n credentials.
4. An n8n workspace.
5. A Gemini API credential, if using Gemini for explanations.
6. An email account or SMTP/provider credential supported by n8n.
7. A confirmed recipient-routing rule for each alert category and severity.
Never commit API tokens, passwords, or other secrets to this repository or paste them into public workflow exports.
Suggested n8n nodes
Build and test these nodes incrementally:
1. Manual Trigger — run controlled tests while developing.
2. HTTP Request — Query Databricks — submit SQL using the Databricks SQL Statement Execution API.
3. Wait / Poll for Statement Result — if the API returns a pending statement, poll until it completes.
4. Filter and Deduplicate — process only eligible alerts that have not already been sent.
5. Gemini — produce a concise, evidence-based explanation and recommended next action.
6. Email — send the alert to the assigned owner or team.
7. HTTP Request — Log Outcome — write a successful-send record to gold.alert_log or to the agreed notification store.
8. Error handling — route failed queries, AI requests, or emails to a separate error path and retain enough information to retry safely.
The exact node configuration depends on the Databricks warehouse, table schema, n8n version, and email provider.
Databricks connection
The Databricks SQL Statement Execution API is commonly accessed at:
POST https://<workspace-host>/api/2.0/sql/statements
Configure the HTTP Request node with:
- Method: POST
- URL: your Databricks workspace host plus /api/2.0/sql/statements
- Authentication: a secure credential or supported bearer-token configuration
- Content type: application/json
- Warehouse ID: the ID of the SQL warehouse
- Statement: a SQL query against gold.risk_alert_queue
- Wait timeout / polling: configure according to the API response and query duration
Example request body template (replace placeholders and confirm the API fields against your Databricks environment):
{
  "warehouse_id": "<SQL_WAREHOUSE_ID>",
  "statement": "SELECT * FROM gold.risk_alert_queue LIMIT 100",
  "wait_timeout": "10s",
  "on_wait_timeout": "CONTINUE"
}
Start with a small, read-only query to verify connectivity. Then replace SELECT * with an explicit column list and a tested eligibility/deduplication rule that matches the actual table schema.
Gemini prompt guidance
Give Gemini only the fields needed to explain an alert. Ask it to:
- State the risk category and severity.
- Summarize the evidence provided by the risk engine.
- Explain the possible operational impact without inventing facts or costs.
- Recommend a specific next step and responsible team based on supplied fields.
- Clearly distinguish observed evidence from model predictions or suspicions.
- Return a predictable structure, such as summary, evidence, recommended_action, and caveat.
Do not let Gemini invent vehicle readings, owners, costs, or diagnoses. The source risk-engine fields remain authoritative.
Email contents
Each notification should include, where available:
- Alert ID and creation time
- Vehicle or trip identifier
- Risk category and severity
- Evidence from the risk engine
- Potential impact, if supplied and validated
- Recommended next action
- Responsible team / owner
- Link to the relevant dashboard or case, if available
Use clear, actionable subject lines, for example:
[Ndovu Fleet Risk][HIGH][MAINTENANCE] Vehicle <vehicle_id>
Use the real severity and identifiers from the source record rather than hard-coded example values.
Duplicate prevention and logging
Before sending, check whether the same alert has already been successfully sent. Use a stable alert identifier or a documented deduplication key, such as alert ID plus notification type. Avoid relying only on a changing timestamp or AI-generated text.

Write to gold.alert_log only after the email provider confirms success. Capture the alert identifier, recipient, sent timestamp, notification type, and delivery outcome where supported by the existing schema.

If the email succeeds but the logging step fails, the workflow must handle retries carefully to avoid sending the same email repeatedly. Test this failure scenario before enabling scheduled execution.
Safety and operational controls
- Begin with Manual Trigger and test records.
- Send initial tests only to a controlled internal address.
- Do not automatically dispatch, ground, or unlock a vehicle based solely on an email or AI response.
- Treat LOCK, RESTRICT, and CLEAR as decisions produced by the configured rules; verify these rules with the fleet operator before operational use.
- Treat suspected fuel anomalies as cases for investigation, not as confirmed misconduct.
- Validate the machine-learning model and thresholds before using predictions for real maintenance decisions.
- Restrict Databricks permissions to the minimum required.
- Keep credentials in n8n's credential store, not in node text, Git, or this README.
- Add monitoring and a failure-notification path before enabling the schedule.
Test checklist
- [ ] Manual trigger runs successfully.
- [ ] n8n authenticates to Databricks.
- [ ] A read-only query returns expected risk records.
- [ ] Empty result sets are handled without errors.
- [ ] Only eligible, unsent alerts continue through the workflow.
- [ ] Gemini explains the supplied evidence without inventing details.
- [ ] Email reaches the intended test recipient.
- [ ] Successful notifications are logged.
- [ ] Re-running the workflow does not resend already logged alerts.
- [ ] Databricks, Gemini, and email failures are visible and recoverable.
- [ ] Recipient routing and severity thresholds have been reviewed.
- [ ] Scheduled execution is enabled only after end-to-end testing.
Rollout plan
1. Verify Databricks access with a read-only query.
2. Test one sample alert end to end using Manual Trigger.
3. Add deduplication and notification logging.
4. Test empty results, repeated runs, and failure/retry scenarios.
5. Review alert content and routing with the intended fleet users.
6. Enable a conservative schedule and monitor results.
7. Refine thresholds and routing based on reviewed outcomes.
Related Gold tables
Table	Intended role
gold.risk_alert_queue	Unified queue of maintenance, fuel, dispatch, and delay risks
gold.alert_log	Record of notifications sent and their outcomes
gold.risk_case	Human follow-up and investigation register
gold.vehicle_health_current	Current vehicle health and dispatch recommendation
gold.dispatch_lock_queue	Vehicles requiring dispatch review
gold.work_order_queue	Maintenance work requiring attention
gold.fuel_alert_queue	Fuel anomalies requiring investigation


Confirm the actual schemas, column names, and write permissions before configuring production queries.