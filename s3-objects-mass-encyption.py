#!/usr/bin/env python3

import logging
import boto3
from pprint import pprint
import os
import json
import datetime
from io import BytesIO
import gzip
import csv
from io import StringIO
from datetime import datetime
import re

# Update the name of AWS PROFILE
aws_profile = "ma-sb"

# Update the alias if a CMK defined for S3 objects encryption
kms_key_alias="alias/aws/s3"

# List of the buckets NOT to be encrypted
buckets_excluded = []

# Execute the scriot on the DRY-RUN mode
dry_run = True

##################

# Global variables
startTime = datetime.now()
total_cnt=0

# Create Log directory
log_dir_name = 'logs'
current_dir = os.getcwd()
log_dir = os.path.join(current_dir, log_dir_name)
if not os.path.exists(log_dir):
   os.makedirs(log_dir)

# Setup Logger
logger = logging.getLogger('s3-mass-encryption')
logger.setLevel(logging.DEBUG)
f_handler = logging.FileHandler('{}/log_{}.log'.format(log_dir_name,'s3-mass-encryption'))
f_format = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
f_handler.setFormatter(f_format)
logger.addHandler(f_handler)


def open_csv(csv_filename):
    fieldnames = ['Bucket','Object','Encryption-Status','SSE-Encryption']
    csvfile = open(csv_filename, 'w')
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    return csvfile, writer

def close_csv(csvfile):
    csvfile.close()

def get_bucket_list(s3):
    response = s3.list_buckets()
    buckets_all = [bucket['Name'] for bucket in response['Buckets']]
    buckets_filtered = [bucket for bucket in buckets_all if bucket not in buckets_excluded]
    return buckets_filtered

def read_gz(data):
    gzipfile = BytesIO(data)
    gzipfile = gzip.GzipFile(fileobj=gzipfile)
    content = gzipfile.read()
    return content

def fix_unicode_chars(string):
    unicode = { '%2B' : '+',
                '%24' : '$',
                '%3D' : '='}
    for char in unicode.keys():
        #string = string.replace(char, unicode[char])
        string = re.sub(char, unicode[char], string, flags=re.IGNORECASE)
    return string

def get_inventory_list(s3, bucket):
    no_inventory = False
    try:
        s3.list_bucket_inventory_configurations(Bucket=bucket)['InventoryConfigurationList']
    except:
        no_inventory = True
    if no_inventory:
        logger.error("Inventory list was NOT generated for the bucket " + bucket)
        return None
    else:
        invent_id     = s3.list_bucket_inventory_configurations(Bucket=bucket)['InventoryConfigurationList'][0]['Id']
        invent_bucket = s3.list_bucket_inventory_configurations(Bucket=bucket)['InventoryConfigurationList'][0]['Destination']['S3BucketDestination']['Bucket'].split(":")[-1]
        invent_format = s3.list_bucket_inventory_configurations(Bucket=bucket)['InventoryConfigurationList'][0]['Destination']['S3BucketDestination']['Format']
        if invent_format != 'CSV':
            logger.error("Unsupported format of the inventory list for the bucket '{}'. Only CSV format is currently supported.".format(bucket))
            return None
        invent_objs = s3.list_objects(Bucket=invent_bucket, Prefix="{}/{}/data/".format(bucket,invent_id))
        invent_date = 0
        if len(invent_objs['Contents']) == 1:
            logger.warning("No inventory list found for the bucket '{}'! Either the bucket is empty or no inventory list generated yet.".format(bucket))
            return None
        for obj in invent_objs['Contents']:
            if obj['Key'][-1] == '/':
                continue
            if invent_date == 0:
                invent_date = obj['LastModified']
            if obj['LastModified'] >= invent_date:
                invent_date = obj['LastModified']
                invent_obj  = obj['Key']
        invent_data = s3.get_object(Bucket=invent_bucket, Key=invent_obj)['Body'].read()
        invent_content = read_gz(invent_data).decode("utf-8")
        invent_csv = csv.reader(invent_content.split('\n'), delimiter=',')
        return invent_csv

def encrypt_invent_list(s3, bucket, invent_csv):
    print("... Starting objects encryption through the bucket {}".format(bucket))
    csv_filename = '{}/s3_encryption_report__bucket_{}.csv'.format(log_dir_name,bucket)
    csvfile, writer = open_csv(csv_filename)
    global total_cnt
    bucket_cnt = 0

    for obj_row in invent_csv:
        if len(obj_row) == 0:
            logger.info("An empty row found in the inventory list of the bucket " + bucket)
            continue

        obj_bucket = obj_row[0]
        obj_key = fix_unicode_chars(obj_row[1])

        try:
            if dry_run:
                obj_return = {'ServerSideEncryption' : 'aws:test'}
                logger.info("The script is running on DRY-RUN mode. No impact on real objects.")
            else:
                obj_return = s3.copy_object(Bucket=obj_bucket, CopySource={'Bucket': obj_bucket, 'Key': obj_key}, Key=obj_key,
                    ServerSideEncryption='aws:kms', SSEKMSKeyId=kms_key_alias, MetadataDirective='COPY', TaggingDirective='COPY')
            logger.info("The S3 object '{}' in the bucket '{}' encrypted.".format(obj_key, obj_bucket))
            writer.writerow({'Bucket': obj_bucket,'Object': obj_key,'Encryption-Status': 'OK','SSE-Encryption': obj_return['ServerSideEncryption']})
            bucket_cnt += 1
            total_cnt += 1
        except s3.exceptions.ClientError as e:
            logger.error('Error: S3 Object {} in the bucket {} failed to be encrypted! '.format(obj_key, obj_bucket) + str(e))
            writer.writerow({'Bucket': obj_bucket,'Object': obj_key,'Encryption-Status': 'FAILED','SSE-Encryption': 'NA'})
    logger.info("Statistic: The number of encrypted objects in the bucket {} is '{}'".format(bucket, bucket_cnt))
    print("* The number of encrypted objects in the bucket {} is '{}'".format(bucket, bucket_cnt))
    print("------------------------------------------------------------------------------------------------------")
    close_csv(csvfile)

def main():
    session = boto3.session.Session(profile_name=aws_profile)
    s3 = session.client("s3")
    buckets = get_bucket_list(s3)
    for bucket in buckets:
        invent_csv = get_inventory_list(s3, bucket)
        if invent_csv is None:
            continue
        else:
            encrypt_invent_list(s3,bucket,invent_csv)
    logger.info("Statistic: The number of encrypted objects in all buckets is '{}'".format(total_cnt))
    logger.info("The script completed in " + str(datetime.now() - startTime))
    print("* The number of encrypted objects in all buckets is '{}'".format(total_cnt))
    print("The script completed in " + str(datetime.now() - startTime))

if __name__ == "__main__":
    main()
