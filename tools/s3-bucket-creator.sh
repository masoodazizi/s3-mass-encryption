#!/usr/bin/env bash

### Create random buckets to apply tests

export AWS_PROFILE="ma-sb"

BUCKETS_PREFIX="mass-encryption-test-bucket"
BUCKETS_NUM=10

FILES_PREFIX="dummy-file"
FILES_NUM=100
FILES_SIZE=100 # in KB

DUMMY_DIR=".dummy_dir"
mkdir ${DUMMY_DIR}
cd ${DUMMY_DIR}
for F_CNT in $(seq 1 ${FILES_NUM})
do
  FILE_NAME="${FILES_PREFIX}-${F_CNT}.bin"
  FILES_SIZE_BYTE=$(( ${FILES_SIZE}*1000 ))
  head -c ${FILES_SIZE_BYTE} /dev/urandom > ${FILE_NAME}
done

for B_CNT in $(seq 1 ${BUCKETS_NUM})
do
  BUCKET_POSTFIX=$(openssl rand -hex 4)
  BUCKET_NAME="${BUCKETS_PREFIX}-${B_CNT}-${BUCKET_POSTFIX}"

  aws s3 mb s3://${BUCKET_NAME} > /dev/null
  if [[ ${?} -ne 0 ]]; then
    echo "ERROR: (${B_CNT}) Create S3 Bucket FAILED: ${BUCKET_NAME}"
  else
    echo "INFO:  (${B_CNT}) S3 Bucket Created: ${BUCKET_NAME}"
  fi

  aws s3 cp ./ s3://${BUCKET_NAME} --recursive > /dev/null
  if [[ ${?} -ne 0 ]]; then
    echo "ERROR: (${B_CNT}) Copy Random Files to S3 Bucket FAILED!"
  else
    echo "INFO:  (${B_CNT}) ${FILES_NUM} Random Files Copied to S3 Bucket: ${BUCKET_NAME}"
  fi
done

cd ..
rm -rf ${DUMMY_DIR}
