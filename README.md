# AWS Job Market Tracker

![Deploy](https://github.com/jordannLai/AWS-Job-Market-Job-Tracker/actions/workflows/deploy.yml/badge.svg)

A serverless data pipeline on AWS that collects tech job postings every day and tracks which skills employers ask for across cloud, data, and software engineering roles.

**Live dashboard:** [https://d25157ptmfxh2g.cloudfront.net](https://d25157ptmfxh2g.cloudfront.net)

> **Status:** Live. The pipeline runs every morning, the dashboard updates itself, every resource is defined in Terraform, and every push to `main` deploys through GitHub Actions.

## Why I built this

Job postings show what employers want right now. I wanted to answer questions like:

- Which cloud platform appears most in cloud engineering postings: AWS, Azure, or GCP?
- How common is Infrastructure as Code (Terraform) compared with the cloud platforms themselves?
- How do skill requirements differ between cloud, data, and software engineering roles?
- How does demand change over time?

The project also gave me hands-on practice with the AWS services that show up most often in job postings.

## Architecture

```mermaid
flowchart LR
    subgraph Ingest["8:00 AM ET"]
        A[EventBridge Scheduler] --> B[Lambda<br/>jobtracker-fetch]
        C[SSM Parameter Store<br/>API keys, encrypted] --> B
        B --> D[Adzuna Jobs API]
    end
    B --> E[(S3 data bucket<br/>raw/dt=YYYY-MM-DD/)]

    subgraph Transform["8:15 AM ET"]
        F[EventBridge Scheduler] --> G[Lambda<br/>jobtracker-transform]
    end
    E --> G
    G --> H[(S3 data bucket<br/>processed/postings/)]

    H --> I[Glue Data Catalog<br/>+ Athena SQL]

    subgraph Publish["8:30 AM ET"]
        J[EventBridge Scheduler] --> K[Lambda<br/>jobtracker-publish]
    end
    H --> K
    K --> L[(S3 site bucket<br/>data/summary.json)]
    L --> M[CloudFront<br/>HTTPS + caching]
    N[index.html] --> L
    M --> O((Visitors))
```

### How it works

1. **Ingest (8:00 AM ET).** EventBridge Scheduler triggers the fetch Lambda. It reads the Adzuna API credentials from SSM Parameter Store as encrypted SecureStrings, queries the API for each tracked job title, and writes the raw JSON to S3, partitioned by date (`raw/dt=2026-10-16/cloud_engineer.json`).
2. **Transform (8:15 AM ET).** A second Lambda reads that day's raw files, flattens each nested API response into one row per posting, tags each posting with the skills it mentions, and writes the result as JSON Lines to `processed/postings/dt=YYYY-MM-DD/`.
3. **Query.** An Athena table defined in the Glue Data Catalog sits on top of the processed data for ad hoc SQL analysis. Partition projection maps each `dt=` folder to a partition automatically, and a view (`postings_unique`) removes postings that appear on several days.
4. **Publish (8:30 AM ET).** A third Lambda reads the full processed history, computes the dashboard's numbers (skill shares by role, cloud platform trends, median salaries), and writes them as one small `summary.json` file to a separate website bucket.
5. **Serve.** The dashboard is a single static `index.html` that loads `summary.json` in the browser. CloudFront serves both over HTTPS from a private S3 bucket, so there is no server or database query on page load.
6. **Monitoring.** A CloudWatch alarm on each Lambda emails me through SNS if any stage fails. A second alarm acts as a dead man's switch: it fires if the publish step hasn't run at all in 24 hours, which catches a disabled schedule that error alarms would miss.
7. **Deployment.** All infrastructure is defined in Terraform. On a pull request, GitHub Actions checks the Python code and runs `terraform plan` with a read-only role. On a push to `main`, it runs `terraform apply` and refreshes the dashboard in CloudFront. GitHub signs in to AWS with OIDC, so no AWS keys are stored in GitHub.
8. **Security.** IAM follows least privilege at every stage. Each Lambda can read only the stage before it and write only its own output prefix. Each EventBridge schedule has its own role that can invoke only its target function. The website bucket blocks all public access, and CloudFront reads it through Origin Access Control.

## AWS services used

| Service | Purpose |
|---|---|
| Amazon S3 | Data lake (raw and processed zones) and a separate private bucket for the website |
| AWS Lambda | Serverless ingestion, transformation, and publishing (Python) |
| Amazon EventBridge Scheduler | Daily cron triggers for each pipeline stage |
| AWS Systems Manager Parameter Store | Encrypted storage for API credentials |
| AWS Glue Data Catalog | Table and view definitions for the processed data |
| Amazon Athena | Serverless SQL analysis directly on S3 |
| Amazon CloudFront | HTTPS delivery and caching for the dashboard, with Origin Access Control |
| AWS IAM | Least-privilege roles for each component, plus OIDC federation for GitHub Actions |
| Amazon CloudWatch | Logs for every function, and alarms for failures and stalled runs |
| Amazon SNS | Email alerts when an alarm fires |
| Terraform | Infrastructure as Code for every resource, with state stored in S3 |
| GitHub Actions | CI/CD: code checks and `terraform plan` on pull requests, `terraform apply` on `main` |

## Findings so far

From 963 unique postings collected between October 8 and 16, 2026:

- **Azure appeared more often than AWS in cloud engineer postings** (32.2% vs. 25.4%, with GCP at 6.5%). The gap held as the sample grew from one day to a week.
- **Early samples were misleading.** A single day's 100 postings showed Terraform in 21% of cloud engineer postings. Across the full dataset it is 10.5%. This is why the pipeline collects data daily instead of relying on a one-off snapshot.
- **Data engineer postings center on SQL (17.9%), Python (14.0%), and Snowflake (10.7%).**
- **About 26% of daily rows are repeats.** The same posting is often returned on several days, so 1,300 collected rows reduce to 963 unique postings. All findings use deduplicated data.

The [live dashboard](https://YOUR-CLOUDFRONT-URL) shows the current numbers, which update every morning.

## Repository structure

```
├── lambda/
│   ├── fetch/lambda_function.py         # Ingest: Adzuna API -> S3 raw zone
│   ├── transform/lambda_function.py     # Transform: raw JSON -> flat rows with skill tags
│   └── publish/lambda_function.py       # Publish: processed history -> dashboard summary.json
├── dashboard/
│   └── index.html                       # Static dashboard (no dependencies, no build step)
├── athena/
│   ├── setup.sql                        # Database, table (partition projection), dedup view
│   └── queries.sql                      # Analysis queries
├── terraform/
│   ├── main.tf                          # Pipeline stages defined once, used everywhere
│   ├── lambda.tf, scheduler.tf          # Functions, log groups, daily schedules
│   ├── iam.tf                           # Least-privilege roles for each Lambda and the scheduler
│   ├── s3.tf, cloudfront.tf             # Buckets, CloudFront, bucket policy, dashboard page
│   ├── monitoring.tf                    # Failure and stalled-pipeline alarms, SNS email
│   ├── github_actions.tf                # OIDC provider and the plan/deploy roles
│   └── imports.tf, cloudfront_import.tf # How the console-built resources were imported
├── .github/workflows/deploy.yml         # CI/CD pipeline
├── iam/                                 # Original hand-written policies (now in terraform/iam.tf)
├── fetch_jobs.py                        # Local prototype of the ingestion script
├── analyze_skills.py                    # Local prototype of the skill analysis
└── README.md
```

## Example query

Share of unique postings that mention each skill, by role:

```sql
WITH totals AS (
  SELECT search_term, COUNT(*) AS total
  FROM jobtracker.postings_unique
  GROUP BY search_term
)
SELECT p.search_term, s.skill,
       ROUND(100.0 * COUNT(*) / t.total, 1) AS pct
FROM jobtracker.postings_unique p
CROSS JOIN UNNEST(p.skills) AS s(skill)
JOIN totals t ON p.search_term = t.search_term
GROUP BY p.search_term, s.skill, t.total
ORDER BY p.search_term, pct DESC;
```

More queries are in [`athena/queries.sql`](athena/queries.sql).

## Deploying

Every push to `main` deploys automatically. To work locally:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # add your alert email
terraform init
terraform plan                                 # preview changes
```

Changes go live through a pull request: GitHub Actions posts the plan, and merging to `main` applies it.

## Running the prototype locally

The local scripts are the prototype the Lambda functions grew out of.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install requests python-dotenv

# Add your Adzuna credentials to a .env file (never committed):
#   ADZUNA_APP_ID=...
#   ADZUNA_APP_KEY=...

python fetch_jobs.py       # saves postings to data/raw/
python analyze_skills.py   # prints a skills report, writes data/processed/skills_summary.csv
```

## Design decisions

- **Serverless over EC2.** Each stage runs for a few seconds once a day. Lambda costs effectively nothing at this scale and needs no server maintenance.
- **Separate raw and processed zones.** Raw API responses are stored unmodified, so the transformation logic can change later and be re-run over the full history.
- **Idempotent, fault-tolerant ingestion.** The Adzuna API occasionally returns HTTP 503 errors. The fetch function retries with exponential backoff, keeps going if one job title fails, and skips titles already saved for the day. Lambda's automatic retries therefore fetch only what is missing, instead of repeating successful work and wasting API calls.
- **Partition projection over Glue crawlers.** The date partitions follow a predictable pattern, so Athena computes them from the table definition. New days are queryable immediately, with no crawler to schedule or pay for.
- **Precomputed dashboard data.** The publish Lambda computes every number once a day and writes a 3 KB JSON file. The dashboard is fully static, so it loads instantly, costs nothing per visit, and can't be used to run expensive queries.
- **Separate, private website bucket.** The site lives in its own bucket, so the data lake never needs public access. CloudFront reads the site bucket through Origin Access Control, and the bucket itself blocks all public access.
- **Different cache lifetimes for page and data.** `summary.json` is cached for one hour, so the morning update appears quickly. `index.html` is cached for five minutes. CloudFront invalidations are used when a change must appear immediately.
- **Imported, not rebuilt.** The pipeline was first built in the console. Terraform `import` blocks brought every existing resource under management with zero downtime and no data loss, and the first apply reported 0 resources destroyed. CloudFront's config was generated from the live distribution with `terraform plan -generate-config-out`, then cleaned up by hand.
- **Remote state with native locking.** Terraform state lives in a versioned S3 bucket, and S3's native lock file stops two runs (for example, a local apply and a CI deploy) from changing it at the same time.
- **OIDC instead of stored keys.** GitHub Actions gets short-lived AWS credentials by proving which repo and branch it runs from. The trust policy matches GitHub's immutable owner and repo IDs, so renaming the repo can't break deploys, and nobody who later claims the old name can assume the role.
- **Separate plan and deploy roles.** Pull requests get a read-only role that can only run `terraform plan`. The admin-level deploy role can only be assumed from the `main` branch.
- **Secrets stay out of Terraform state.** The Adzuna keys live in Parameter Store and are never read by Terraform. Lambda reads them at runtime, and the alert email is passed in as a GitHub secret.
- **A dead man's switch, not just error alarms.** Error alarms can't fire for a function that never runs, so a separate alarm watches for the publish step not running at all.
- **No WAF on the dashboard.** AWS WAF has a fixed monthly cost, and a read-only static site with no forms or logins gains little from it. CloudFront includes AWS Shield Standard for basic DDoS protection at no extra cost.
- **JSON Lines for processed data.** It is simple to write with the Python standard library and Athena reads it natively. At this data volume, converting to Parquet would add packaging complexity for little benefit. Parquet is the planned format if the dataset grows.
- **Parameter Store over Secrets Manager.** Standard SecureString parameters are free and meet the need here. Secrets Manager adds automatic rotation, which this API key doesn't require.
- **Standard library only.** All three Lambda functions use only the Python standard library and the built-in `boto3`, and the dashboard uses no JavaScript libraries, so nothing needs packaging or a build step.

## Known limitations

- **Truncated descriptions.** The Adzuna API returns only a snippet of each job description, so skill percentages undercount real demand. Comparisons between roles and trends over time are more meaningful than the absolute numbers.
- **Sample per day.** Each run collects the 100 most recent postings per role, not every posting available.
- **Sparse salary data.** Most postings don't state a salary. Adzuna's estimated salaries (`salary_is_predicted = 1`) are excluded from salary analysis.
- **Keyword matching.** Skills are detected by keyword matching, which can miss synonyms or catch unrelated uses of a word.
- **Gaps from API outages.** October 15 is missing data and software engineer postings because of Adzuna errors that occurred before retry logic was added.
- **Athena schema lives in SQL.** The Athena table and view are defined in `athena/setup.sql` instead of Terraform, since the deduplication view is easier to read and change as SQL.

## Roadmap

- [x] Local prototype: data fetching and skill analysis
- [x] Automated daily ingestion on AWS (Lambda, S3, EventBridge, Parameter Store)
- [x] Retry logic and idempotent re-runs for API failures
- [x] Transformation Lambda: raw JSON to flat, skill-tagged rows
- [x] Glue Data Catalog and Athena for SQL analysis, with a deduplicated view
- [x] Public dashboard: publish Lambda, private S3 site bucket, CloudFront
- [x] Infrastructure as Code with Terraform, importing the console-built resources
- [x] CloudWatch alarms and SNS email alerts for failed or stalled runs
- [x] CI/CD with GitHub Actions and OIDC (plan on pull requests, apply on `main`)

Possible next steps: convert processed data to Parquet, track more roles, and add unit tests for the skill-matching logic.

## Data source

<a href="https://www.adzuna.com">Jobs by Adzuna</a>. Job data is provided by the Adzuna API.