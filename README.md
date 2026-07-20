# TabStash

A website for creating, editing, and browsing guitar tabs. Flutter Web frontend,
Node.js Lambda + DynamoDB backend, all AWS resources managed with Terraform.
Architecture doc: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). What's next:
[docs/ROADMAP.md](docs/ROADMAP.md). Agent/contributor guide: [AGENTS.md](AGENTS.md).

- **No login** — an anonymous owner token in localStorage grants edit/delete
  rights to the songs you created; everything is readable by anyone with the link.
- **Standard tab notation** — high e on top, `|` bar lines, technique symbols
  (`h p b / \ x ~ …`), chord names and lyrics anchored to their columns.
  Pasted ASCII tabs import directly.
- **~$0/month** — API Gateway HTTP API + Lambda + DynamoDB on-demand + S3/CloudFront,
  all within free tiers at personal scale.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable, web enabled)
- Node.js ≥ 20 (backend tests)
- Terraform ≥ 1.10 and AWS CLI with credentials (deploy only)

## Quickstart (local, zero AWS)

```sh
make run        # flutter run -d chrome — songs persist in browser localStorage
make test       # backend unit tests (node:test) + flutter test
```

Without `API_URL`, the app uses `LocalStore` (localStorage). Point it at a
deployed backend with:

```sh
make run API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com
```

## Deploy

One-time bootstrap: create the Terraform state bucket by hand (name must match
`infra/main.tf`), then:

```sh
aws s3 mb s3://guitar-tabs-tfstate                    # once, ever
cd infra && terraform init
make deploy       # terraform apply + flutter build web + s3 sync + CF invalidation
make smoke        # curl the deployed API
```

Outputs include `api_url` and `site_url` (the CloudFront domain).

Frontend-only changes: `make deploy-frontend`. Backend/infra changes:
`make deploy-infra` (Lambda code is zipped and deployed by Terraform,
hash-based, so it only updates when `backend/src` changed).

## Repository layout

```
frontend/   Flutter app — lib/{models,storage,screens,widgets}
backend/    Lambda source (src/index.mjs) + unit tests; zero runtime deps
infra/      Terraform — DynamoDB, Lambda, API Gateway, S3+CloudFront, budget alarm
```

## API

| Method & path | Purpose |
|---|---|
| `GET /songs` | List songs (id, title, artist, updatedAt) |
| `POST /songs` | Create song (requires `x-owner-token` header) |
| `GET /songs/{id}` | Full song incl. tab data |
| `PUT /songs/{id}` | Replace song (owner only, 403 otherwise) |
| `DELETE /songs/{id}` | Permanent delete (owner only) |
