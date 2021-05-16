#!/usr/bin/env bash

# Please change the AWS Profile
export AWS_PROFILE="ma-sb"
export AWS_PAGER=

INVENTORY_ENABLED="true" # or "false"
OUTPUT_FORMAT="CSV" # or "ORC" or "Parquet"
FREQUENCY="Daily" # or "Weekly"

# For all buckets, leave it empty
BUCKETS_PREFIX="mass-encryption-test-bucket"

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --p ${AWS_PROFILE})

if [[ -z $(aws s3 ls | awk -F' ' '{print $3}' | grep "${AWS_PROFILE}-inventory-list") ]]; then
  INVENTORY_BUCKET="${AWS_PROFILE}-inventory-list-$(openssl rand -hex 4)"
  aws s3 mb s3://${INVENTORY_BUCKET} > /dev/null
else
  INVENTORY_BUCKET=$(aws s3 ls | awk -F' ' '{print $3}' | grep "${AWS_PROFILE}-inventory-list" | head -1)
fi

INVENTORY_BUCKET_POLICY='{"Version":"2012-10-17","Statement":[{"Sid":"InventoryAccessPolicy","Effect":"Allow","Principal":{"Service":"s3.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::'${INVENTORY_BUCKET}'\/*","Condition":{"StringEquals":{"aws:SourceAccount":"'${ACCOUNT_ID}'","s3:x-amz-acl":"bucket-owner-full-control"},"ArnLike":{"aws:SourceArn":"arn:aws:s3:::*"}}}]}'
aws s3api put-bucket-policy --bucket ${INVENTORY_BUCKET} --policy "${INVENTORY_BUCKET_POLICY}"


if [[ -z ${BUCKETS_PREFIX} ]]; then
  S3_BUCKETS=$(aws s3 ls | awk -F' ' '{print $3}')
else
  S3_BUCKETS=$(aws s3 ls | awk -F' ' '{print $3}' | grep ${BUCKETS_PREFIX})
fi

echo
echo "**************  STARTING INVENTORY LIST SCRIPT  **************"
echo
echo "Parameters of the script:"
echo "  - AWS PROFILE       = ${AWS_PROFILE}"
echo "  - ACCOUNT ID        = ${ACCOUNT_ID}"
echo "  - INVENTORY BUCKET  = ${INVENTORY_BUCKET}"
echo "  - INVENTORY ENABLED = ${INVENTORY_ENABLED}"
echo "  - OUTPUT FORMAT     = ${OUTPUT_FORMAT}"
echo "  - FREQUENCY         = ${FREQUENCY}"
echo
echo

for BUCKET in ${S3_BUCKETS}
do
  echo "==> Enabling/updating Inventory List on the bucket  -- ${BUCKET} --"

  aws s3api put-bucket-inventory-configuration \
      --bucket ${BUCKET} \
      --id 1 \
      --inventory-configuration '{"Destination": { "S3BucketDestination":
      { "AccountId": "'${ACCOUNT_ID}'", "Bucket": "arn:aws:s3:::'${INVENTORY_BUCKET}'", "Format": "'${OUTPUT_FORMAT}'" }},
      "IsEnabled": '${INVENTORY_ENABLED}', "Id": "1", "IncludedObjectVersions": "Current", "Schedule": { "Frequency": "'${FREQUENCY}'" }}'

  if [[ "${?}" -ne 0 ]]
    then
        echo "!!!!! Error in the operation of the bucket  ---  ${BUCKET}  --- !!!!!"
      else
        echo "*** Successfully updated ***"
    fi
  echo
done
