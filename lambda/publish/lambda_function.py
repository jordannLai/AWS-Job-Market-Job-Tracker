"""
Publish Lambda for the AWS Job Market Tracker.

Reads every day of processed postings from the data bucket, computes the
numbers the dashboard shows, and writes them as one small JSON file to the
website bucket:

    Input:  s3://<DATA_BUCKET>/processed/postings/dt=YYYY-MM-DD/postings.jsonl
    Output: s3://<SITE_BUCKET>/data/summary.json

The dashboard (index.html) fetches summary.json in the browser, so the site
itself is fully static: no servers and no database queries on page load.

Setup this function expects:
  - Environment variables DATA_BUCKET and SITE_BUCKET
  - Execution role allowed to: s3:ListBucket on DATA_BUCKET (processed/ prefix)
                                s3:GetObject on DATA_BUCKET/processed/*
                                s3:PutObject on SITE_BUCKET/data/*
"""

import json
import os
import statistics
from collections import defaultdict
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

PROCESSED_PREFIX = "processed/postings/"
PLATFORMS = ["AWS", "Azure", "GCP"]
PLATFORM_ROLE = "cloud engineer"
MIN_SALARY_SAMPLES = 5   # below this, the dashboard says "not enough data"


def load_rows(bucket):
    """Return every processed row, sorted by date (oldest first)."""
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=PROCESSED_PREFIX):
        keys += [obj["Key"] for obj in page.get("Contents", []) if obj["Key"].endswith(".jsonl")]

    rows = []
    for key in sorted(keys):  # dt=YYYY-MM-DD sorts chronologically
        dt = key.split("dt=")[1].split("/")[0]
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode("utf-8")
        for line in body.splitlines():
            if line.strip():
                row = json.loads(line)
                row["dt"] = dt
                rows.append(row)
    return rows


def first_seen(rows):
    """Keep each posting once (its first day), like the postings_unique view in Athena."""
    seen, unique = set(), []
    for row in rows:
        key = (row["search_term"], row["id"])
        if key not in seen:
            seen.add(key)
            unique.append(row)
    return unique


def pct(part, whole):
    return round(100.0 * part / whole, 1) if whole else 0.0


def skills_by_role(unique):
    totals = defaultdict(int)
    counts = defaultdict(lambda: defaultdict(int))
    for row in unique:
        totals[row["search_term"]] += 1
        for skill in row.get("skills") or []:
            counts[row["search_term"]][skill] += 1

    result = {}
    for role, skill_counts in counts.items():
        ranked = sorted(skill_counts.items(), key=lambda kv: (-kv[1], kv[0]))
        result[role] = [
            {"skill": skill, "count": count, "pct": pct(count, totals[role])}
            for skill, count in ranked
        ]
    return result


def platform_share(rows):
    """Share of postings mentioning each cloud platform (overall, deduplicated)."""
    cloud = [r for r in rows if r["search_term"] == PLATFORM_ROLE]
    return {
        "postings": len(cloud),
        "share": {p: pct(sum(p in (r.get("skills") or []) for r in cloud), len(cloud)) for p in PLATFORMS},
    }


def platform_trend(rows):
    """Per day: share of that day's cloud engineer sample mentioning each platform."""
    by_day = defaultdict(list)
    for row in rows:
        if row["search_term"] == PLATFORM_ROLE:
            by_day[row["dt"]].append(row)

    trend = []
    for dt in sorted(by_day):
        day = by_day[dt]
        point = {"date": dt, "postings": len(day)}
        for p in PLATFORMS:
            point[p] = pct(sum(p in (r.get("skills") or []) for r in day), len(day))
        trend.append(point)
    return trend


def salaries(unique):
    """Median midpoint of employer-stated salaries (Adzuna estimates excluded)."""
    mids = defaultdict(list)
    for row in unique:
        low, high = row.get("salary_min"), row.get("salary_max")
        if not row.get("salary_is_predicted") and low and high:
            mids[row["search_term"]].append((low + high) / 2)
    return {
        role: {
            "median": round(statistics.median(values), -3) if len(values) >= MIN_SALARY_SAMPLES else None,
            "n": len(values),
        }
        for role, values in mids.items()
    }


def build_summary(rows):
    unique = first_seen(rows)
    days = sorted({r["dt"] for r in rows})
    roles = sorted({r["search_term"] for r in rows})

    totals = {
        role: {
            "rows": sum(r["search_term"] == role for r in rows),
            "unique": sum(r["search_term"] == role for r in unique),
        }
        for role in roles
    }

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "first_date": days[0],
        "last_date": days[-1],
        "days_collected": len(days),
        "total_rows": len(rows),
        "unique_postings": len(unique),
        "roles": roles,
        "totals": totals,
        "skills": skills_by_role(unique),
        "platforms": platform_share(first_seen([r for r in rows if r["search_term"] == PLATFORM_ROLE])),
        "platform_trend": platform_trend(rows),
        "salaries": salaries(unique),
    }


def lambda_handler(event, context):
    data_bucket = os.environ["DATA_BUCKET"]
    site_bucket = os.environ["SITE_BUCKET"]

    rows = load_rows(data_bucket)
    if not rows:
        raise RuntimeError(f"No processed data found under s3://{data_bucket}/{PROCESSED_PREFIX}")

    summary = build_summary(rows)
    s3.put_object(
        Bucket=site_bucket,
        Key="data/summary.json",
        Body=json.dumps(summary, separators=(",", ":")).encode("utf-8"),
        ContentType="application/json",
        CacheControl="max-age=3600",  # CloudFront and browsers refetch at most hourly
    )

    print(
        f"Published summary: {summary['unique_postings']} unique postings over "
        f"{summary['days_collected']} days -> s3://{site_bucket}/data/summary.json"
    )
    return {
        "status": "ok",
        "unique_postings": summary["unique_postings"],
        "days_collected": summary["days_collected"],
        "last_date": summary["last_date"],
    }