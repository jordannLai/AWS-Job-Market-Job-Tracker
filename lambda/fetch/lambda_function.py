"""
AWS Lambda version of fetch_jobs.py.

Runs on a schedule, pulls job postings from the Adzuna API, and writes the raw
results to S3 at:  s3://<BUCKET_NAME>/raw/dt=YYYY-MM-DD/<search_term>.json

The dt= folder naming lets Athena treat each day as a partition later.

Setup this function expects:
  - Environment variable BUCKET_NAME (your S3 bucket name)
  - SSM Parameter Store SecureStrings:
        /jobtracker/adzuna_app_id
        /jobtracker/adzuna_app_key
  - Execution role allowed to: ssm:GetParameter on /jobtracker/*
                                s3:PutObject on <bucket>/raw/*

Uses only the Python standard library + boto3 (built into Lambda),
so there is nothing extra to package.
"""

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

import boto3

# --- Settings -------------------------------------------------------------

SEARCH_TERMS = [
    "cloud engineer",
    "data engineer",
    "software engineer",
]

COUNTRY = "us"
RESULTS_PER_PAGE = 50
PAGES_PER_QUERY = 2       # 3 terms x 2 pages = 6 API calls per run
MAX_DAYS_OLD = 7

BASE_URL = f"https://api.adzuna.com/v1/api/jobs/{COUNTRY}/search"
PARAM_PREFIX = "/jobtracker"

# Created once per Lambda container and reused across invocations.
s3 = boto3.client("s3")
ssm = boto3.client("ssm")


# --- Helpers --------------------------------------------------------------

def get_credentials():
    """Read the Adzuna keys from SSM Parameter Store (decrypted)."""
    response = ssm.get_parameters(
        Names=[f"{PARAM_PREFIX}/adzuna_app_id", f"{PARAM_PREFIX}/adzuna_app_key"],
        WithDecryption=True,
    )
    if response["InvalidParameters"]:
        raise RuntimeError(f"Missing SSM parameters: {response['InvalidParameters']}")
    values = {p["Name"].rsplit("/", 1)[-1]: p["Value"] for p in response["Parameters"]}
    return values["adzuna_app_id"], values["adzuna_app_key"]


def fetch_page(app_id, app_key, search_term, page):
    """Call the Adzuna search endpoint for one page of results."""
    params = urllib.parse.urlencode({
        "app_id": app_id,
        "app_key": app_key,
        "what": search_term,
        "results_per_page": RESULTS_PER_PAGE,
        "max_days_old": MAX_DAYS_OLD,
        "content-type": "application/json",
    })
    url = f"{BASE_URL}/{page}?{params}"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as err:
        # Don't include the URL in the error: it contains the API key.
        raise RuntimeError(f"Adzuna returned HTTP {err.code} for '{search_term}' page {page}") from None


def fetch_term(app_id, app_key, search_term, run_date):
    """Fetch all configured pages for one search term."""
    all_results = []
    total_available = 0

    for page in range(1, PAGES_PER_QUERY + 1):
        data = fetch_page(app_id, app_key, search_term, page)
        results = data.get("results", [])
        total_available = data.get("count", total_available)
        all_results.extend(results)

        if len(results) < RESULTS_PER_PAGE:
            break
        time.sleep(1)

    return {
        "search_term": search_term,
        "fetched_on": run_date,
        "total_available": total_available,
        "results": all_results,
    }


def save_raw(bucket, payload):
    """Write one search term's results to S3 and return the object key."""
    filename = payload["search_term"].replace(" ", "_") + ".json"
    key = f"raw/dt={payload['fetched_on']}/{filename}"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(payload).encode("utf-8"),
        ContentType="application/json",
    )
    return key


# --- Entry point ----------------------------------------------------------

def lambda_handler(event, context):
    bucket = os.environ["BUCKET_NAME"]
    run_date = datetime.now(timezone.utc).date().isoformat()
    app_id, app_key = get_credentials()

    summary = []
    for term in SEARCH_TERMS:
        payload = fetch_term(app_id, app_key, term, run_date)
        key = save_raw(bucket, payload)
        print(f"Saved {len(payload['results'])} postings for '{term}' -> s3://{bucket}/{key}")
        summary.append({"search_term": term, "postings": len(payload["results"]), "s3_key": key})

    return {"status": "ok", "date": run_date, "files": summary}
