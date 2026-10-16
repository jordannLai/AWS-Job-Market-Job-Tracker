"""
Transform Lambda for the AWS Job Market Tracker.

Reads one day of raw Adzuna responses from S3, flattens them into one row per
job posting, tags each posting with the skills it mentions, and writes the
result as JSON Lines (one JSON object per line) for Athena to query.

    Input:  s3://<BUCKET_NAME>/raw/dt=YYYY-MM-DD/*.json
    Output: s3://<BUCKET_NAME>/processed/postings/dt=YYYY-MM-DD/postings.jsonl

By default it processes today's date (UTC). To reprocess an earlier day
(a "backfill"), invoke it with an event like:  {"date": "2026-10-08"}

Setup this function expects:
  - Environment variable BUCKET_NAME
  - Execution role allowed to: s3:ListBucket on the bucket (raw/ prefix)
                                s3:GetObject on <bucket>/raw/*
                                s3:PutObject on <bucket>/processed/*
"""

import json
import os
import re
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

# Skill name -> phrases that count as a mention (case-insensitive, whole words).
SKILLS = {
    # Cloud
    "AWS": ["aws", "amazon web services"],
    "Azure": ["azure"],
    "GCP": ["gcp", "google cloud"],
    # Languages
    "Python": ["python"],
    "SQL": ["sql"],
    "Java": ["java"],
    "JavaScript": ["javascript", "node.js", "nodejs"],
    "TypeScript": ["typescript"],
    "Go": ["golang"],
    "C++": ["c++"],
    "C#": ["c#"],
    "Scala": ["scala"],
    "Rust": ["rust"],
    # Infrastructure / DevOps
    "Docker": ["docker"],
    "Kubernetes": ["kubernetes", "k8s"],
    "Terraform": ["terraform"],
    "CI/CD": ["ci/cd", "cicd", "continuous integration"],
    "Linux": ["linux"],
    "Git": ["git", "github", "gitlab"],
    # Data
    "Spark": ["spark", "pyspark"],
    "Kafka": ["kafka"],
    "Airflow": ["airflow"],
    "Snowflake": ["snowflake"],
    "Databricks": ["databricks"],
    "dbt": ["dbt"],
    "PostgreSQL": ["postgresql", "postgres"],
    "MongoDB": ["mongodb"],
    # AI / ML
    "Machine Learning": ["machine learning"],
    "AI / LLMs": ["llm", "llms", "generative ai", "genai"],
}

# Compiled once per Lambda container. Custom boundaries handle C++, C#, CI/CD.
PATTERNS = {
    skill: re.compile(
        rf"(?<![a-z0-9])(?:{'|'.join(re.escape(p) for p in phrases)})(?![a-z0-9])",
        re.IGNORECASE,
    )
    for skill, phrases in SKILLS.items()
}


def find_skills(text):
    return [skill for skill, pattern in PATTERNS.items() if pattern.search(text)]


def to_number(value):
    """Adzuna sometimes sends numbers as strings; return a float or None."""
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def flatten(job, search_term, run_date):
    """Turn one nested Adzuna posting into a flat row for Athena."""
    location = job.get("location") or {}
    area = location.get("area") or []  # e.g. ["US", "California", "San Francisco"]
    text = f"{job.get('title', '')} {job.get('description', '')}"

    return {
        "id": str(job.get("id")),
        "search_term": search_term,
        "title": job.get("title"),
        "company": (job.get("company") or {}).get("display_name"),
        "location": location.get("display_name"),
        "state": area[1] if len(area) > 1 else None,
        "category": (job.get("category") or {}).get("label"),
        "contract_type": job.get("contract_type"),
        "contract_time": job.get("contract_time"),
        "created": job.get("created"),
        "salary_min": to_number(job.get("salary_min")),
        "salary_max": to_number(job.get("salary_max")),
        "salary_is_predicted": str(job.get("salary_is_predicted")) == "1",
        "skills": find_skills(text),
        "fetched_on": run_date,
    }


def list_raw_files(bucket, run_date):
    prefix = f"raw/dt={run_date}/"
    response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    return [obj["Key"] for obj in response.get("Contents", []) if obj["Key"].endswith(".json")]


def lambda_handler(event, context):
    bucket = os.environ["BUCKET_NAME"]
    run_date = (event or {}).get("date") or datetime.now(timezone.utc).date().isoformat()

    keys = list_raw_files(bucket, run_date)
    if not keys:
        raise RuntimeError(f"No raw files found under raw/dt={run_date}/")

    rows = []
    for key in keys:
        payload = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
        search_term = payload["search_term"]
        seen = set()
        for job in payload.get("results", []):
            job_id = str(job.get("id"))
            if job_id in seen:
                continue  # skip duplicates within the same file
            seen.add(job_id)
            rows.append(flatten(job, search_term, run_date))

    out_key = f"processed/postings/dt={run_date}/postings.jsonl"
    body = "\n".join(json.dumps(row) for row in rows) + "\n"
    s3.put_object(Bucket=bucket, Key=out_key, Body=body.encode("utf-8"),
                  ContentType="application/x-ndjson")

    print(f"Processed {len(rows)} postings from {len(keys)} files -> s3://{bucket}/{out_key}")
    return {"status": "ok", "date": run_date, "postings": len(rows), "output": out_key}