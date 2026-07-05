# DEX Backend Plan

  ## Summary

  Build a TypeScript backend for the DEX.ai platform in DEX-Backend using a production-first architecture: NestJS on Fastify, PostgreSQL + Prisma,
  Redis for cache/queues/pub-sub, and an
  optional load balancer in front of two EC2 instances. The backend will support trading APIs, authenticated user/account flows, TradingView-based
  chart and market data delivery, and a
  spot-only market-maker bot that executes market orders only.

  ## Key Changes

  - Stand up a modular backend with clear bounded areas:
      - Auth and user/session management
      - Market data and TradingView integration
      - Orders, positions, balances, and portfolio services
      - Bot management and execution
      - P2P/copy-trade/support/admin foundations for the rest of the platform

  - Make the backend stateless at the API layer so both EC2 nodes can serve traffic behind the load balancer.
  - Use Redis for:
      - API response caching for hot market data
      - rate limiting
      - websocket/pub-sub fanout
      - background job queues

  - Use PostgreSQL for durable trading records, users, orders, bot configs, audit logs, and analytics.
  - Integrate TradingView through a backend data-feed layer:
      - normalized OHLCV candle API
      - symbol metadata API
      - server-side caching so users do not hit TradingView individually
      - websocket or SSE updates for live UI refresh

  - Implement the market-maker bot as a dedicated worker/service:
      - spot only
      - market orders only
      - no limit-order placement path
      - risk checks before every order
      - circuit breakers, max position size, max notional per symbol, max daily loss, and kill switch

  - Prepare for 20,000 concurrent users by designing around:
      - stateless HTTP APIs
      - websocket scaling via Redis pub-sub
      - aggressive caching
      - async job execution
      - read/write separation in service design
      - health checks and graceful shutdown

  ## Architecture

  - 8 GB EC2: primary API + websocket gateway + bot workers if load is moderate
  - 2 GB EC2: secondary API/websocket node and/or lightweight worker node
  - Load balancer: enabled if websocket/API concurrency or failover requirements justify it
  - Database: hosted PostgreSQL
  - Cache/queue: hosted Redis
  - Storage: object storage for logs, exports, and optional market snapshots

  ## Delivery Phases

  1. Foundation
      - repo scaffold, environment config, logging, validation, error handling, health endpoints
      - Prisma schema and migrations
      - auth/session primitives and RBAC

  2. Market Data
      - TradingView data-feed service
      - candle cache and symbol registry
      - live ticker/quote stream

  3. Trading Core
      - account ledger
      - order lifecycle
      - positions and PnL
      - risk checks and audit trail

  4. Bot System
      - spot market-maker bot worker
      - config UI/API for enable/disable, symbol selection, inventory limits, spreads, and kill switch
      - market-order execution only

  5. Scale/Hardening
      - Redis-backed queues and pub-sub
      - rate limiting, observability, alerts
      - load tests and failure-mode testing
      - deployment runbooks

  ## Test Plan

  - Unit tests for:
      - order validation
      - bot risk checks
      - candle normalization
      - auth/permission guards

  - Integration tests for:
      - TradingView data-feed endpoints
      - order placement and state transitions
      - Redis queue processing
      - bot execution with market-only enforcement

  - Load tests for:
      - 20k concurrent read users on market/chart endpoints
      - websocket fanout under burst traffic
      - bot job throughput and failure recovery

  - Resilience tests for:
      - Redis unavailability
      - DB failover/restart
      - node restart during active bot execution
      - kill-switch behavior

  ## Assumptions

  - Use Postgres + Prisma.
  - Use an internal market-maker bot only, not a plugin framework.

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  - Scope is the full platform backend, not just trading endpoints.

• I cannot write the file yet in this mode, but this is the exact plan.md content to place in DEX-Backend/plan.md.
  - TradingView is treated as the source for charting/market-data integration in the backend plan, with server-side caching and normalization to
  avoid per-user direct fetches.

  - The current DEX-Backend folder is empty, so this plan assumes a greenfield backend implementation.
  If you want, next I can turn this plan into an implementation-ready backend scaffold with:


• Proposed Plan


  # DEX Backend Plan

  ## Summary

  Build a TypeScript backend for the DEX.ai platform in DEX-Backend using a production-first architecture: NestJS on Fastify, PostgreSQL +
  Prisma, Redis for cache/queues/pub-sub, and an optional load balancer in front of two EC2 instances. The backend will support trading APIs,
  authenticated user/account flows, TradingView-based chart and market data delivery, and a spot-only market-maker bot that executes market
  orders only.

  ## Key Changes

  - Stand up a modular backend with clear bounded areas:
      - Auth and user/session management
      - Market data and TradingView integration
      - Orders, positions, balances, and portfolio services
      - Bot management and execution
      - P2P/copy-trade/support/admin foundations for the rest of the platform

  - Make the backend stateless at the API layer so both EC2 nodes can serve traffic behind the load balancer.
  - Use Redis for:
      - API response caching for hot market data
      - rate limiting
      - websocket/pub-sub fanout
      - background job queues

  - Use PostgreSQL for durable trading records, users, orders, bot configs, audit logs, and analytics.
  - Integrate TradingView through a backend data-feed layer:
      - normalized OHLCV candle API
      - symbol metadata API
      - server-side caching so users do not hit TradingView individually
      - websocket or SSE updates for live UI refresh

  - Implement the market-maker bot as a dedicated worker/service:
      - spot only
      - market orders only
      - no limit-order placement path
      - risk checks before every order
      - circuit breakers, max position size, max notional per symbol, max daily loss, and kill switch

  - Prepare for 20,000 concurrent users by designing around:
      - stateless HTTP APIs
      - websocket scaling via Redis pub-sub
      - aggressive caching
      - async job execution
      - read/write separation in service design
      - health checks and graceful shutdown

  ## Architecture

  - 8 GB EC2: primary API + websocket gateway + bot workers if load is moderate
  - 2 GB EC2: secondary API/websocket node and/or lightweight worker node
  - Load balancer: enabled if websocket/API concurrency or failover requirements justify it
  - Database: hosted PostgreSQL
  - Cache/queue: hosted Redis
  - Storage: object storage for logs, exports, and optional market snapshots

  ## Delivery Phases

  1. Foundation
      - repo scaffold, environment config, logging, validation, error handling, health endpoints
      - Prisma schema and migrations
      - auth/session primitives and RBAC

  2. Market Data
      - TradingView data-feed service
      - candle cache and symbol registry
      - live ticker/quote stream

  3. Trading Core
      - account ledger
      - order lifecycle
      - positions and PnL
      - risk checks and audit trail

  4. Bot System
      - spot market-maker bot worker
      - config UI/API for enable/disable, symbol selection, inventory limits, spreads, and kill switch
      - market-order execution only

  5. Scale/Hardening
      - Redis-backed queues and pub-sub
      - rate limiting, observability, alerts
      - load tests and failure-mode testing
      - deployment runbooks

  ## Test Plan

  - Unit tests for:
      - order validation
      - bot risk checks
      - candle normalization
      - auth/permission guards

  - Integration tests for:
      - Redis queue processing
      - bot execution with market-only enforcement

  - Load tests for:
      - 20k concurrent read users on market/chart endpoints
      - websocket fanout under burst traffic
      - bot job throughput and failure recovery

  - Resilience tests for:
      - Redis unavailability
      - DB failover/restart
      - node restart during active bot execution
      - kill-switch behavior

  ## Assumptions

  - Use Postgres + Prisma.
  - Use an internal market-maker bot only, not a plugin framework.
  - Scope is the full platform backend, not just trading endpoints.
  - TradingView is treated as the source for charting/market-data integration in the backend plan, with server-side caching and normalization to
    avoid per-user direct fetches.

  - The current DEX-Backend folder is empty, so this plan assumes a greenfield backend implementation.