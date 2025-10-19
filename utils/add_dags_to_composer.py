import os
import glob
import tempfile
from shutil import copytree, ignore_patterns
from google.cloud import storage

def collect_files(source_dir):
    if not os.path.exists(source_dir):
        print(f"Directory '{source_dir}' not found.")
        return "", []

    temp_dir = tempfile.mkdtemp()
    copytree(source_dir, temp_dir, ignore=ignore_patterns("__init__.py", "*_test.py"), dirs_exist_ok=True)
    files = [f for f in glob.glob(f"{temp_dir}/**", recursive=True) if os.path.isfile(f)]
    return temp_dir, files

def upload_files(files, temp_dir, bucket_name, prefix):
    client = storage.Client()
    bucket = client.bucket(bucket_name)

    for file in files:
        dest_path = file.replace(f"{temp_dir}/", prefix)
        blob = bucket.blob(dest_path)
        blob.upload_from_filename(file)
        print(f"Uploaded to gs://{bucket_name}/{dest_path}")

def upload_to_composer(source_dir, bucket_name, prefix):
    temp_dir, files = collect_files(source_dir)
    if files:
        upload_files(files, temp_dir, bucket_name, prefix)
    else:
        print(f"No files to upload from '{source_dir}'.")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--dags_directory")
    parser.add_argument("--dags_bucket")
    parser.add_argument("--data_directory")
    args = parser.parse_args()

    if args.dags_directory:
        upload_to_composer(args.dags_directory, args.dags_bucket, "dags/")
    if args.data_directory:
        upload_to_composer(args.data_directory, args.dags_bucket, "data/")
