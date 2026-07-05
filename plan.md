# DEX Backend Plan

## Summary

Build a production-first TypeScript backend for the DEX.ai platform inside `DEX-Backend`. The backend will run as the order venue for the platform: all user orders and market-maker bot orders are created and managed in this system, and fills are produced by the platform matching engine when incoming orders cross resting liquidity or the bot's spot inventory. The stack should use NestJS on Fastify, PostgreSQL + Prisma, Redis for cache/queues/pub-sub, and an optional load balancer in front of two EC2 instances.

The backend must support:
- authenticated user/account flows
- wallet-based login with no email/password flow
- on-chain wallet funding verification
- trading APIs
- TradingView-based chart and market data delivery
- a spot-only market-maker bot that places market orders only
- scalable order matching and fill processing for around 20,000 concurrent users

## Key Changes

- Create a modular backend with clear bounded areas:
  - wallet auth and user/session management
  - market data and TradingView integration
  - order entry, matching, fills, positions, balances, and portfolio services
  - bot management and execution
  - P2P, copy-trade, support, and admin foundations

- Treat the wallet address as the primary login identity.
  - when a user connects a supported wallet, create or load the platform user record for that wallet address
  - no email/password signup or password reset flows
  - session ownership should be tied to the connected wallet and signed proof-of-ownership flow

- Make the API layer stateless so both EC2 nodes can serve traffic behind the load balancer.

- Use Redis for:
  - API response caching for hot market data
  - rate limiting
  - websocket/pub-sub fanout
  - background job queues
  - ephemeral order-routing and bot execution coordination

- Use PostgreSQL for durable trading records:
  - users
  - wallet identities and session claims
  - wallets and balances
  - orders
  - matching events and fills
  - bot configs and execution logs
  - audit logs and analytics

- Build a platform-owned matching engine:
  - all user orders are placed on the platform order book
  - all market-maker bot orders are also placed on the platform order book
  - limit orders may rest on the book
  - market orders match against available resting liquidity
  - if the best available liquidity is the market-maker bot, the bot is the counterparty and the trade is executed
  - no order bypasses the platform matching and fill pipeline

- Add an on-chain funding verification pipeline:
  - users initiate a deposit from a connected wallet into a platform-controlled wallet or deposit address
  - deposits are only credited after blockchain confirmation and transaction verification
  - the backend must verify transfer status using online trackers / chain explorers such as Etherscan or equivalent RPC/indexer sources
  - each deposit should store transaction hash, chain, sender, recipient, amount, confirmation count, and verification status
  - withdrawals should be tracked and reconciled similarly, even if the application later executes them off-chain

- Integrate TradingView through a backend data-feed layer:
  - normalized OHLCV candle API
  - symbol metadata API
  - backend caching so users do not fetch TradingView independently
  - websocket or SSE updates for live UI refresh

- Implement the market-maker bot as a dedicated worker/service:
  - spot only
  - market orders only
  - no limit-order placement path
  - inventory-aware quoting logic
  - risk checks before every order
  - circuit breakers, max position size, max notional per symbol, max daily loss, and kill switch
  - all bot activity routes through the same order and fill systems as user activity

- Prepare for 20,000 concurrent users by designing around:
  - stateless HTTP APIs
  - websocket scaling via Redis pub-sub
  - aggressive caching
  - async job execution
  - read/write separation in service design
  - health checks and graceful shutdown
  - partitioned order processing by market/symbol if needed
  - fast wallet-session verification and deposit-reconciliation workers

## Architecture

- `8 GB` EC2: primary API, websocket gateway, order processor, and bot workers if load is moderate
- `2 GB` EC2: secondary API/websocket node and lightweight worker capacity
- Load balancer: enabled if websocket/API concurrency or failover requirements justify it
- Database: hosted PostgreSQL
- Cache/queue: hosted Redis
- Storage: object storage for logs, exports, snapshots, and audit archives

## Delivery Phases

1. Foundation
   - repo scaffold, environment config, logging, validation, error handling, health endpoints
   - Prisma schema and migrations
   - wallet auth/session primitives and RBAC
   - request tracing and audit logging

2. Market Data
   - TradingView data-feed service
   - candle cache and symbol registry
   - live ticker/quote stream
   - market status and instrument metadata

3. Trading Core
   - account ledger
   - order lifecycle
   - platform matching engine
   - fills, positions, and PnL
   - risk checks and audit trail
   - websocket order-book and trade-stream updates
   - deposit verification and funding ledger reconciliation

4. Bot System
   - spot market-maker bot worker
   - config API for enable/disable, symbol selection, inventory limits, spread logic, and kill switch
   - market-order execution only
   - bot orders submitted into the same platform order book as user orders

5. Scale/Hardening
   - Redis-backed queues and pub-sub
   - rate limiting, observability, alerts
   - load tests and failure-mode testing
   - deployment runbooks
   - concurrency tuning for 20k-user load

## Test Plan

- Unit tests for:
  - order validation
  - matching engine rules
  - bot risk checks
  - candle normalization
  - wallet auth/permission guards
  - deposit verification logic

- Integration tests for:
  - TradingView data-feed endpoints
  - order placement and state transitions
  - matching engine fills for user-to-user and user-to-bot cases
  - Redis queue processing
  - bot execution with market-only enforcement
  - blockchain deposit verification and confirmation handling

- Load tests for:
  - 20k concurrent read users on market/chart endpoints
  - websocket fanout under burst traffic
  - order-book write bursts and fill processing
  - bot job throughput and failure recovery
  - wallet login bursts and deposit-reconciliation throughput

- Resilience tests for:
  - Redis unavailability
  - DB failover/restart
  - node restart during active bot execution
  - kill-switch behavior

## Assumptions

- Use Postgres + Prisma.
- Use an internal market-maker bot only, not a plugin framework.
- Scope is the full platform backend, not just trading endpoints.
- TradingView is treated as the source for charting and market-data integration in the backend plan, with server-side caching and normalization to avoid per-user direct fetches.
- The current `DEX-Backend` folder is the backend workspace and can be used as the implementation root.
