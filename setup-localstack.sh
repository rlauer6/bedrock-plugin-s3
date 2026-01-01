#!/usr/bin/env bash
#-*- mode: sh; -*-

set -oeu pipefail

# LocalStack sets the endpoint internally, no need for localhost flags
awslocal s3 mb s3://test-bucket
