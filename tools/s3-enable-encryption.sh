#!/usr/bin/env bash

### Please change the AWS Profile name if it differs
export AWS_PROFILE="ma-sb"
export AWS_PAGER=

### Update the alias if a CMK defined for S3 buckets encryption
KMS_KEY_ALIAS="alias/aws/s3"

### The bucket list that should NOT be encrypted
# EXCLUDE_BUCKETS="s3-public-bucket-1 s3-public-bucket-2"

# For all buckets (except EXCLUDE_BUCKETS), leave this variable empty
BUCKETS_PREFIX="mass-encryption-test-bucket"


if [[ -z ${BUCKETS_PREFIX} ]]; then
  S3_BUCKETS=$(aws s3 ls | awk -F' ' '{print $3}')
else
  S3_BUCKETS=$(aws s3 ls | awk -F' ' '{print $3}' | grep ${BUCKETS_PREFIX})
fi

KMS_KEY_ID=$(aws kms describe-key --key-id ${KMS_KEY_ALIAS} --query "KeyMetadata.KeyId" --output text)

echo
echo "**************  STARTING S3 BUCKETS ENCRYPTION  **************"
echo
echo "The KMS Key to set default encryption on all S3 buckets:"
echo "  - KMS Key Alias = '${KMS_KEY_ALIAS}'"
echo "  - KMS Key ID    = '${KMS_KEY_ID}'"
echo
echo

for BUCKET in ${S3_BUCKETS}
do

  SKIP_BUCKET=false
  for ITEM in ${EXCLUDE_BUCKETS}
  do
    if [ "${ITEM}" == "${BUCKET}" ]; then
      SKIP_BUCKET=true
    fi
  done

  if [[ ${SKIP_BUCKET} = false ]]; then
    echo "==> Enabling default encryption on the bucket  -- ${BUCKET} --"

    aws s3api put-bucket-encryption \
        --bucket ${BUCKET} \
        --server-side-encryption-configuration '{"Rules":
        [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms", "KMSMasterKeyID":
        "'${KMS_KEY_ALIAS}'"}}]}'

    if [[ "${?}" -ne 0 ]]
      then
          echo "!!!!! Error in the operation of the bucket  ---  ${BUCKET}  --- !!!!!"
        else
          echo "*** Successfully updated ***"
      fi
  else
    echo "--> NOT enabling encryption on the bucket  -- ${BUCKET} --"
    echo "--- The bucket EXCLUDED ---"
  fi
  echo
done
