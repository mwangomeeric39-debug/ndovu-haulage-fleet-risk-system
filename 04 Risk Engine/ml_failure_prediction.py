# ============================================================
# 04b_ml_failure_prediction
# Predict probability of emergency maintenance within 48 hours
# Databricks Notebook - Python
# ============================================================

from pyspark.ml import Pipeline
from pyspark.ml.feature import Imputer, VectorAssembler
from pyspark.ml.classification import GBTClassifier
from pyspark.ml.evaluation import BinaryClassificationEvaluator
from pyspark.ml.functions import vector_to_array
from pyspark.sql import functions as F

# ------------------------------------------------------------
# 1. CONFIGURATION
# ------------------------------------------------------------

CATALOG = "fleet_catalog"
CUTOFF = "2026-09-01"
THRESHOLD = 0.50

FEATURES = [
    "coolant_max_24h",
    "coolant_trend",
    "oil_min_24h",
    "oil_drop",
    "trans_max_24h",
    "trans_trend",
    "load_avg_24h",
    "battery_min_24h",
    "brake_wear_pct",
    "engine_hours_24h",
    "active_critical_codes",
    "active_high_codes",
    "active_medium_codes",
    "days_since_service"
]

# ------------------------------------------------------------
# 2. LOAD THE VEHICLE HEALTH SNAPSHOTS
# ------------------------------------------------------------

snap = spark.table(
    f"{CATALOG}.risk.vehicle_health_snapshot"
)

for c in FEATURES:
    snap = snap.withColumn(c, F.col(c).cast("double"))

snap = snap.withColumn(
    "label",
    F.col("fail_next_48h").cast("double")
)

# Keep snapshots with known outcomes only
labelled = snap.filter(F.col("label").isNotNull())

# ------------------------------------------------------------
# 3. SPLIT INTO TRAINING AND TEST DATA
# ------------------------------------------------------------

train = labelled.filter(
    F.col("snapshot_ts") < F.to_timestamp(F.lit(CUTOFF))
)

test = labelled.filter(
    F.col("snapshot_ts") >= F.to_timestamp(F.lit(CUTOFF))
)

print("Training rows:", train.count())
print("Testing rows:", test.count())

# Check that both periods contain data
if train.limit(1).count() == 0:
    raise ValueError("Training data is empty. Check CUTOFF and snapshot dates.")

if test.limit(1).count() == 0:
    raise ValueError("Test data is empty. Check CUTOFF and snapshot dates.")

# ------------------------------------------------------------
# 4. HANDLE RARE FAILURE EVENTS
# ------------------------------------------------------------

pos = train.filter("label = 1").count()
neg = train.filter("label = 0").count()

if pos == 0 or neg == 0:
    raise ValueError(
        "Training data must contain both failure and non-failure labels."
    )

# Give failure examples more weight because failures are rare
train = train.withColumn(
    "w",
    F.when(
        F.col("label") == 1,
        F.lit(float(neg) / float(pos))
    ).otherwise(F.lit(1.0))
)

print("Failure examples:", pos)
print("Non-failure examples:", neg)

# ------------------------------------------------------------
# 5. BUILD AND TRAIN THE ML PIPELINE
# ------------------------------------------------------------

imputed_features = [f"{c}_i" for c in FEATURES]

pipeline = Pipeline(stages=[
    Imputer(
        strategy="median",
        inputCols=FEATURES,
        outputCols=imputed_features
    ),
    VectorAssembler(
        inputCols=imputed_features,
        outputCol="features"
    ),
    GBTClassifier(
        labelCol="label",
        featuresCol="features",
        weightCol="w",
        maxIter=60,
        maxDepth=3,
        stepSize=0.1,
        seed=42
    )
])

model = pipeline.fit(train)

print("ML model training completed.")

# ------------------------------------------------------------
# 6. GENERATE FAILURE PROBABILITIES
# ------------------------------------------------------------

def add_prob(df):
    return (
        model.transform(df)
        .withColumn(
            "failure_prob_48h",
            vector_to_array("probability")[1]
        )
    )

pred = add_prob(test)

# ------------------------------------------------------------
# 7. EVALUATE MODEL PERFORMANCE
# ------------------------------------------------------------

auc_roc = BinaryClassificationEvaluator(
    labelCol="label",
    metricName="areaUnderROC"
).evaluate(pred)

auc_pr = BinaryClassificationEvaluator(
    labelCol="label",
    metricName="areaUnderPR"
).evaluate(pred)

tp = pred.filter(
    (F.col("label") == 1) &
    (F.col("failure_prob_48h") >= THRESHOLD)
).count()

fp = pred.filter(
    (F.col("label") == 0) &
    (F.col("failure_prob_48h") >= THRESHOLD)
).count()

fn = pred.filter(
    (F.col("label") == 1) &
    (F.col("failure_prob_48h") < THRESHOLD)
).count()

precision = tp / max(tp + fp, 1)
recall = tp / max(tp + fn, 1)

print(f"TEST AUC-ROC: {auc_roc:.3f}")
print(f"TEST AUC-PR: {auc_pr:.3f}")
print(f"Precision at {THRESHOLD}: {precision:.3f}")
print(f"Recall at {THRESHOLD}: {recall:.3f}")

# ------------------------------------------------------------
# 8. IDENTIFY IMPORTANT FEATURES
# ------------------------------------------------------------

importances = (
    model.stages[-1]
    .featureImportances
    .toArray()
)

importance_rows = sorted(
    zip(FEATURES, importances),
    key=lambda x: -x[1]
)

print("Top 6 feature importance scores:")

for feature, score in importance_rows[:6]:
    print(f"{feature}: {float(score):.3f}")

# ------------------------------------------------------------
# 9. SCORE ALL SNAPSHOTS
# ------------------------------------------------------------

scored = add_prob(snap)

(
    scored
    .select(
        "vehicle_id",
        "snapshot_ts",
        F.round("failure_prob_48h", 4).alias("failure_prob_48h")
    )
    .withColumn("scored_at", F.current_timestamp())
    .withColumn("model_version", F.lit("gbt_v1"))
    .write
    .mode("overwrite")
    .saveAsTable(f"{CATALOG}.gold.failure_risk_score")
)

print("Saved predictions to gold.failure_risk_score")

# ------------------------------------------------------------
# 10. SAVE MODEL METRICS
# ------------------------------------------------------------

metrics = spark.createDataFrame(
    [(
        "gbt_v1",
        CUTOFF,
        float(auc_roc),
        float(auc_pr),
        THRESHOLD,
        float(precision),
        float(recall),
        int(tp),
        int(fp),
        int(fn)
    )],
    """
    model_version string,
    test_from string,
    auc_roc double,
    auc_pr double,
    threshold double,
    precision double,
    recall double,
    tp int,
    fp int,
    fn int
    """
)

(
    metrics.write
    .mode("overwrite")
    .saveAsTable(f"{CATALOG}.gold.model_metrics")
)

print("Saved model metrics to gold.model_metrics")

# ------------------------------------------------------------
# 11. OPTIONAL: TRACK THE EXPERIMENT WITH MLFLOW
# ------------------------------------------------------------

try:
    import mlflow

    with mlflow.start_run(run_name="gbt_v1_failure_48h"):
        mlflow.log_params({
            "cutoff": CUTOFF,
            "threshold": THRESHOLD,
            "maxIter": 60,
            "maxDepth": 3
        })

        mlflow.log_metrics({
            "auc_roc": float(auc_roc),
            "auc_pr": float(auc_pr),
            "precision": float(precision),
            "recall": float(recall)
        })

    print("MLflow experiment logged.")

except Exception as e:
    print("MLflow skipped:", str(e))