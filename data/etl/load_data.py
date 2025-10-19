from google.cloud import storage, bigquery
import pandas as pd
from pyspark.sql import SparkSession
import datetime
import json

spark = SparkSession.builder.appName('healthpipeline').getOrCreate()

storage_client = storage.Client()
bq_client = bigquery.Client()

GCS_BUCKET = "avd_buck1"
HOSPITAL_NAME = "hospital"
LANDING_PATH = f"gs://{GCS_BUCKET}/landing/{HOSPITAL_NAME}/"
ARCHIVE_PATH = f"gs://{GCS_BUCKET}/landing/{HOSPITAL_NAME}/archive/"
CONFIG_FILE_PATH = f"gs://{GCS_BUCKET}/configs/config.csv"

# BigQuery Configuration
BQ_PROJECT = "forward-cacao-466814-e0"
BQ_AUDIT_TABLE = f"{BQ_PROJECT}.temp_dataset.audit_log"
BQ_LOG_TABLE = f"{BQ_PROJECT}.temp_dataset.pipeline_logs"
BQ_TEMP_PATH = f"{GCS_BUCKET}/temp/"  

MYSQL_CONFIG = {
    'url' : 'jdbc:mysql://34.66.27.179:3306/hospital_db',
    'driver' : 'com.mysql.cj.jdbc.Driver',
    'user' : 'user1',
    'password' : 'Use@1234'
}

def read_config_file():
    df = spark.read.csv(CONFIG_FILE_PATH, header = True)
    return df

log_entries = []
def log_event(event_type, message, table = None):
    log_entry = {
        'timestamp' : datetime.datetime.now().isoformat(),
        'event_type' : event_type,
        'message' : message,
        'table' : table
    }
log_entries.append(log_entry)

def save_logs_to_gcs():
    log_file_name = f"pipeline_log_{datetime.datetime.now().isoformat('%Y%M%d%H%m%s')}.json"
    log_filepath = f"temp/pipeline_logs/{log_file_name}"

    json_data = json.dumps(log_entries, indent=4)

    bucket = storage_client.bucket(GCS_BUCKET)
    blob = bucket.blob(log_filepath)
    blob.upload_from_string(json_data, content_type = "application/json")

def save_logs_to_bigquery():
    if log_entries:
        log_df = spark.createDataFrame(log_entries)

        (log_df
         .write
         .format('bigquery')
         .option('table', BQ_LOG_TABLE)
         .option('temporaryGcsBucket',BQ_TEMP_PATH)
         .mode('append')
         .save()
         )
        
        # Function to Get Latest Watermark from BigQuery Audit Table
def get_latest_watermark(table_name):
    query = f"""
        SELECT MAX(load_timestamp) AS latest_timestamp
        FROM `{BQ_AUDIT_TABLE}`
        WHERE tablename = '{table_name}' and data_source = "hospital_db"
    """
    query_job = bq_client.query(query)
    result = query_job.result()
    for row in result:
        return row.latest_timestamp if row.latest_timestamp else "1900-01-01 00:00:00"
    return "1900-01-01 00:00:00"


# Function to Move Existing Files to Archive
def move_existing_files_to_archive(table):
    blobs = list(storage_client.bucket(GCS_BUCKET).list_blobs(prefix=f"landing/{HOSPITAL_NAME}/{table}/"))
    existing_files = [blob.name for blob in blobs if blob.name.endswith(".json")]

    if not existing_files:
        log_event("INFO", f"No existing files for table {table}")
        return

    for file in existing_files:
        source_blob = storage_client.bucket(GCS_BUCKET).blob(file)

        # Extract Date from File Name
        date_part = file.split("_")[-1].split(".")[0]
        year, month, day = date_part[-4:], date_part[2:4], date_part[:2]

        # Move to Archive
        archive_path = f"landing/{HOSPITAL_NAME}/archive/{table}/{year}/{month}/{day}/{file.split('/')[-1]}"
        destination_blob = storage_client.bucket(GCS_BUCKET).blob(archive_path)

        # Copy file to archive and delete original
        storage_client.bucket(GCS_BUCKET).copy_blob(source_blob, storage_client.bucket(GCS_BUCKET), destination_blob.name)
        source_blob.delete()

        log_event("INFO", f"Moved {file} to {archive_path}", table=table)

        # Function to Extract Data from MySQL and Save to GCS (MODIFIED)
def extract_and_save_to_landing(table, load_type, watermark_col):
    try:
        last_watermark = get_latest_watermark(table) if load_type.lower() == "incremental" else None
        log_event("INFO", f"Latest watermark for {table}: {last_watermark}", table=table)

        query = f"(SELECT * FROM {table}) AS t" if load_type.lower() == "full" else \
                f"(SELECT * FROM {table} WHERE {watermark_col} > '{last_watermark}') AS t"
        
        log_event("INFO", f"Executing query: {query}", table=table)

        df = (spark.read.format("jdbc")
                .option("url", MYSQL_CONFIG["url"])
                .option("user", MYSQL_CONFIG["user"])
                .option("password", MYSQL_CONFIG["password"])
                .option("driver", MYSQL_CONFIG["driver"])
                .option("dbtable", query)
                .load())

        # Count records before proceeding
        record_count = df.count()
        log_event("SUCCESS", f"Successfully extracted {record_count} records from {table}", table=table)

        if record_count > 0:
            move_existing_files_to_archive(table)
            today = datetime.datetime.today().strftime('%d%m%Y')
            JSON_FILE_PATH = f"landing/{HOSPITAL_NAME}/{table}/{table}_{today}.json"

            bucket = storage_client.bucket(GCS_BUCKET)
            blob = bucket.blob(JSON_FILE_PATH)
            
            blob.upload_from_string(df.toPandas().to_json(orient="records", lines=True), content_type="application/json")

            log_event("SUCCESS", f"JSON file successfully written to gs://{GCS_BUCKET}/{JSON_FILE_PATH} with {record_count} records.", table=table)
        else:
            log_event("INFO", f"Skipping GCS file creation for {table} as 0 new records were found. Previous file preserved.", table=table)

             # Insert Audit Entry (Always update audit log with current run info)
        audit_df = spark.createDataFrame([
            ("hospital_db", table, load_type, record_count, datetime.datetime.now(), "SUCCESS")], 
            ["data_source", "tablename", "load_type", "record_count", "load_timestamp", "status"])

        (audit_df.write.format("bigquery")
            .option("table", BQ_AUDIT_TABLE)
            .option("temporaryGcsBucket", GCS_BUCKET)
            .mode("append")
            .save())

        log_event("SUCCESS", f"Audit log updated for {table}", table=table)

    except Exception as e:
        # If extraction fails, still log the error and an audit failure entry
        log_event("ERROR", f"Error processing {table}: {str(e)}", table=table)

        # Insert Audit Entry with failure status
        audit_df = spark.createDataFrame([
            ("hospital_db", table, load_type, 0, datetime.datetime.now(), "FAILURE")], 
            ["data_source", "tablename", "load_type", "record_count", "load_timestamp", "status"])

        (audit_df.write.format("bigquery")
            .option("table", BQ_AUDIT_TABLE)
            .option("temporaryGcsBucket", GCS_BUCKET)
            .mode("append")
            .save())


# read config file
config_df = read_config_file()

for row in config_df.collect():
    if row["is_active"] == '1' and row["database"] == "hospital_db": 
        db, src, table, load_type, watermark, _, targetpath = row
        extract_and_save_to_landing(table, load_type, watermark)

save_logs_to_gcs()
save_logs_to_bigquery()




    