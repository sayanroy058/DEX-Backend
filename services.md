# Required Services

This backend should be deployed with the following services and managed components.

## Compute

- `AWS EC2`
  - `16 GB` instance for primary API, websocket gateway, and order processing (matching engine may move to a dedicated instance if load testing shows saturation)
  - `8 GB` instance for secondary API/websocket traffic, bot workers, and background job processing
- `AWS Load Balancer` or `ALB`
  - Optional but recommended once traffic grows or you need failover across both EC2 nodes

## Data Layer

- `AWS RDS PostgreSQL`
  - Primary relational database for users, orders, fills, balances, bot configs, and audit logs
- `Redis`
  - Use `AWS ElastiCache for Redis` if available
  - Caching, rate limiting, pub/sub, job queues, and websocket fanout coordination

## Storage

- `AWS S3`
  - Store exports, audit archives, logs, chart snapshots, and other durable blobs

## Networking and Security

- `AWS VPC`
  - Private subnets for database, Redis, and internal workers
- `AWS Security Groups`
  - Restrict public access to only required ingress
- `AWS IAM`
  - Role-based access for services and deployment automation
- `AWS Route 53`
  - DNS for API, websocket, and admin endpoints
- `AWS Certificate Manager`
  - TLS certificates for HTTPS/WSS endpoints

## Observability

- `AWS CloudWatch`
  - Logs, metrics, alarms, and dashboards
- `AWS X-Ray` or equivalent tracing
  - Distributed tracing across API, order engine, and bot workers
- `AWS SNS` or alerting integration
  - Notify on failures, queue backlogs, or risk events

## Messaging and Async Work

- `Redis-backed job queue`
  - Can be implemented with BullMQ or equivalent
- Optional `AWS SQS`
  - Useful if you want a managed queue for non-latency-critical background tasks

## Custody and Signing

- `MPC signing service` (e.g., Fireblocks, or equivalent) or `HSM`
  - Signs hot wallet withdrawal transactions. No raw private keys in application config or database.
- `Multisig wallet` (e.g., Gnosis Safe or chain-equivalent)
  - Holds cold/treasury funds, requires quorum of offline signers.
- Isolated signing worker
  - Runs separate from the public API, enforces independent withdrawal caps.

## Blockchain Verification

- `Blockchain RPC provider`
  - Needed to verify deposits, transaction status, and confirmations on-chain
- `Block explorer APIs`
  - Examples: `Etherscan`, `BscScan`, `Polygonscan`, or chain-equivalent explorers depending on supported networks
- `Indexer or webhook provider`
  - Optional but recommended for faster and more reliable deposit detection than polling alone

## Optional but Recommended

- `AWS ECR`
  - Store backend container images
- `AWS Systems Manager`
  - Parameter Store or Secrets Manager for runtime configuration and secrets
- `AWS Secrets Manager`
  - Database credentials, Redis credentials, API keys, and bot secrets
- `AWS CloudFront`
  - Optional CDN for static assets and cacheable public responses

## External/Platform Dependencies

- `TradingView`
  - Source for chart and market data integration in the backend plan
- `Wallet providers`
  - Login is wallet-based only, no email/password auth
- `Payment / KYC / Wallet providers`
  - Only if you later extend the platform into fiat rails or compliance workflows

## Minimum Viable Production Set

If you want the smallest practical production deployment, start with:

1. `2x AWS EC2`
2. `AWS RDS PostgreSQL`
3. `AWS ElastiCache for Redis`
4. `AWS S3`
5. `AWS ALB`
6. `AWS CloudWatch`
7. `AWS IAM`
8. `AWS Route 53`
9. `AWS Certificate Manager`
