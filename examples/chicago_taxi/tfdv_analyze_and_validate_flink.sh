#!/bin/bash
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -u

echo Starting distributed TFDV stats computation and schema generation...

if [ -z "$MYBUCKET" ]; then
  echo MYBUCKET was not set
  echo Please set MYBUCKET to your GCP bucket using: export MYBUCKET=gs://bucket
  exit 1
fi

JOB_ID="chicago-taxi-tfdv-$(date +%Y%m%d-%H%M%S)"
JOB_INPUT_PATH=$MYBUCKET/$JOB_ID/chicago_taxi_input
JOB_OUTPUT_PATH=$MYBUCKET/$JOB_ID/chicago_taxi_output
TEMP_PATH=$MYBUCKET/$JOB_ID/tmp/
MYPROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)

# Variables needed for subsequent stages.
export TFDV_OUTPUT_PATH=$JOB_OUTPUT_PATH/tfdv_output
export SCHEMA_PATH=$TFDV_OUTPUT_PATH/schema.pbtxt

echo Using GCP project: $MYPROJECT
echo Job input path: $JOB_INPUT_PATH
echo Job output path: $JOB_OUTPUT_PATH
echo TFDV output path: $TFDV_OUTPUT_PATH

# move data to gcs
echo Uploading data to GCS
gsutil cp -r ./data/eval/ ./data/train/ $JOB_INPUT_PATH/

image="goenka-docker-apache.bintray.io/beam/python"
#image="gcr.io/dataflow-build/goenka/my_beam_python"

#input=bigquery-public-data.chicago_taxi_trips.taxi_trips
#input=gs://clouddfe-goenka/chicago_taxi_data/taxi_trips_000000000000.csv
eval_input=$JOB_INPUT_PATH/eval/data.csv
#input=$JOB_INPUT_PATH/eval/data_medium.csv
#input=$JOB_INPUT_PATH/eval/data_133M.csv

train_input=$JOB_INPUT_PATH/train/data.csv

threads=100
#sdk=--sdk_location=/usr/local/google/home/goenka/d/work/beam/beam/sdks/python/build/apache-beam-2.9.0.dev0.tar.gz
sdk=""


# Compute stats and generate a schema based on the stats.
python tfdv_analyze_and_validate.py \
  --infer_schema \
  --stats_path $TFDV_OUTPUT_PATH/train_stats.tfrecord \
  --schema_path $SCHEMA_PATH \
  --setup_file ./setup.py \
  --save_main_session True \
  --input $train_input \
  --runner PortableRunner \
  --job_endpoint=localhost:8099 \
  --experiments=worker_threads=$threads \
  $sdk \
  --environment_type=DOCKER \
  --environment_config=$image

EVAL_JOB_ID=$JOB_ID-eval

# Compute stats for eval data and validate stats against the schema.
python tfdv_analyze_and_validate.py \
  --for_eval \
  --schema_path $SCHEMA_PATH \
  --validate_stats \
  --stats_path $TFDV_OUTPUT_PATH/eval_stats.tfrecord \
  --anomalies_path $TFDV_OUTPUT_PATH/anomalies.pbtxt \
  --setup_file ./setup.py \
  --save_main_session True \
  --input $eval_input \
  --experiments=beam_fn_api \
  --runner PortableRunner \
  --job_endpoint=localhost:8099 \
  --experiments=worker_threads=$threads \
  $sdk \
  --environment_type=DOCKER \
  --environment_config=$image


echo
echo
echo "  TFDV_OUTPUT_PATH=$TFDV_OUTPUT_PATH"
echo "  SCHEMA_PATH=$SCHEMA_PATH"
echo
