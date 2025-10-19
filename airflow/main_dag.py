import airflow
from airflow import DAG
from datetime import timedelta
from airflow.utils.dates import days_ago
from airflow.operators.dagrun_operator import TriggerDagRunOperator

# Define default arguments
ARGS = {
    "owner": "airflow",
    "start_date": days_ago(1),
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5)
}

# Define the parent DAG
with DAG(
    dag_id="parent_dag",
    schedule_interval="0 5 * * *",
    description="Parent DAG to trigger PySpark and BigQuery DAGs",
    default_args=ARGS,
    tags=["parent", "orchestration", "etl"]
) as dag:

    trigger_pyspark_dag = TriggerDagRunOperator(
        task_id="trigger_pyspark_dag",
        trigger_dag_id="pyspark_dag",
        wait_for_completion=True,
    )

    trigger_bigquery_dag = TriggerDagRunOperator(
        task_id="trigger_bigquery_dag",
        trigger_dag_id="bigquery_dag",
        wait_for_completion=True,
    )

trigger_pyspark_dag >> trigger_bigquery_dag
