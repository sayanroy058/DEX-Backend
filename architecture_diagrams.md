# DEX Backend — Architecture Diagrams

Mermaid diagrams for each major feature area, derived from `plan.md`, `api_requirements.md`, and `services.md`.

## 1. Overall System Architecture

```mermaid
flowchart TB
    subgraph Client
        FE[Frontend / Wallet UI]
    end

    subgraph AWS_Edge["Edge"]
        R53[Route 53 DNS]
        ACM[Certificate Manager TLS]
        ALB[Load Balancer]
    end

    subgraph EC2_A["EC2 16GB - Primary"]
        API1[NestJS API]
        WS1[Websocket Gateway]
        ME[Matching Engine]
    end

    subgraph EC2_B["EC2 8GB - Secondary"]
        API2[NestJS API secondary]
        WS2[Websocket Gateway secondary]
        BOT[Bot Worker]
        JOBS[Background Job Processor]
    end

    subgraph Data["Data Layer"]
        PG[(PostgreSQL - RDS)]
        REDIS[(Redis - ElastiCache)]
        S3[(S3 - logs/exports/archives)]
    end

    subgraph Chain["Blockchain"]
        RPC[RPC Provider]
        EXPLORER[Block Explorer API]
    end

    subgraph Custody["Custody"]
        MPC[MPC/HSM Signer]
        MULTISIG[Cold Multisig Treasury]
        SIGNER[Isolated Signing Worker]
    end

    TV[TradingView Data Feed]

    FE --> R53 --> ALB
    ACM --> ALB
    ALB --> API1
    ALB --> API2
    ALB --> WS1
    ALB --> WS2

    API1 <--> PG
    API2 <--> PG
    ME <--> PG
    BOT <--> PG

    API1 <--> REDIS
    API2 <--> REDIS
    WS1 <--> REDIS
    WS2 <--> REDIS
    ME <--> REDIS
    BOT <--> REDIS
    JOBS <--> REDIS

    BOT --> ME
    API1 --> ME
    API2 -.routes via Redis.-> ME

    API1 --> TV
    JOBS --> RPC
    JOBS --> EXPLORER

    JOBS --> SIGNER
    SIGNER --> MPC
    MPC --> MULTISIG

    JOBS --> S3
    API1 --> S3
```

## 2. Wallet Auth Flow (no email/password)

```mermaid
sequenceDiagram
    participant U as User Wallet
    participant API as Auth API
    participant DB as PostgreSQL

    U->>API: POST /auth/nonce (wallet_address)
    API->>DB: create nonce, expiry
    API-->>U: nonce

    U->>U: sign nonce with wallet
    U->>API: POST /auth/verify (address, signature, chain, nonce)
    API->>DB: validate nonce not expired/consumed
    API->>API: verify signature matches address
    alt first login
        API->>DB: create user record
    end
    API->>DB: consume nonce, create session
    API-->>U: session token

    U->>API: GET /auth/session (with token)
    API->>DB: validate session not revoked/expired
    API-->>U: identity + status

    U->>API: POST /auth/logout
    API->>DB: revoke session
```

## 3. Deposit Verification Flow

```mermaid
flowchart LR
    A[User initiates deposit] --> B[POST /wallet/deposit/request]
    B --> C[Return deposit address + request id]
    C --> D[User sends funds on-chain]
    D --> E[POST /wallet/deposit/verify - tx_hash]
    E --> F{Verify via RPC/Explorer}
    F -->|sender/recipient/amount/chain match| G{Confirmations >= policy threshold}
    F -->|mismatch| H[Reject deposit]
    G -->|yes| I[Credit wallet_balances]
    G -->|no| J[Status: confirming - poll again]
    I --> K[Ledger entry: deposit]
    I --> L[Audit log]
```

## 4. Withdrawal Flow (custody-aware)

```mermaid
flowchart LR
    A[POST /wallet/withdraw/request] --> B[Risk check: limits/velocity/balance]
    B -->|fail| Z[Reject]
    B -->|pass| C[Lock balance, status=pending]
    C --> D[Require second wallet signature]
    D --> E[POST /wallet/withdraw/confirm]
    E --> F[Status=queued]
    F --> G[Isolated Signing Worker picks up]
    G --> H{Within per-tx and daily cap?}
    H -->|no| Y[Reject / hold for manual approval]
    H -->|yes| I[Request signature from MPC/HSM]
    I --> J[Broadcast transaction]
    J --> K[Status=broadcast]
    K --> L[Confirm on-chain]
    L --> M[Status=confirmed, ledger entry, audit log]
```

## 5. Order Entry + Matching Engine Flow

```mermaid
flowchart TB
    A[POST /orders] --> B{Idempotency key seen?}
    B -->|yes, duplicate| C[Return existing order result]
    B -->|no| D[Validate: symbol exists, auth, balance/margin, size/notional limits]
    D -->|fail| E[Reject + order_event: rejected]
    D -->|pass| F[Persist order, status=accepted]
    F --> G[Route to symbol-owning matching worker via Redis]
    G --> H{Order type}
    H -->|limit| I[Rest on order book]
    H -->|market| J[Match against resting liquidity]
    J --> K{Bot is best counterparty?}
    K -->|yes| L[Bot risk check]
    L -->|fail| M[Skip bot, use next liquidity or reject]
    L -->|pass| N[Bot fills as counterparty]
    K -->|no| O[Match against user resting orders]
    N --> P[Create fill record]
    O --> P
    I --> Q[order_event: accepted]
    P --> R[order_event: matched/partial_fill/full_fill]
    P --> S[Update positions]
    P --> T[Update balances/ledger]
    P --> U[Emit websocket: fill stream, order status stream]
    P --> V[Audit log]
```

## 6. Market-Maker Bot Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: POST /bots
    Created --> Disabled: default state
    Disabled --> Enabled: POST /bots/:id/enable
    Enabled --> Disabled: POST /bots/:id/disable
    Enabled --> Quoting: worker loop - inventory-aware quote
    Quoting --> RiskCheck: before every order
    RiskCheck --> OrderPlaced: within max_position/max_notional/max_daily_loss
    RiskCheck --> Skipped: risk limit breached - log risk_event
    OrderPlaced --> Quoting: loop continues
    Enabled --> Killed: POST /bots/:id/kill-switch
    Disabled --> Killed: POST /bots/:id/kill-switch
    Killed --> [*]: cannot re-enable without admin/code change

    note right of Killed
        cancels pending activity
        immediately, audit logged
    end note
```

## 7. Bot Order Routing (shares pipeline with users)

```mermaid
flowchart LR
    BOT[Bot Worker] --> RC[Risk Check: max position/notional/daily loss]
    RC -->|pass| MO[Submit market order]
    RC -->|fail| KILL{Breach severity}
    KILL -->|soft| SKIP[Skip this cycle]
    KILL -->|hard| KS[Trigger kill-switch]
    MO --> SAME[Same order/matching/fill pipeline as user orders]
    SAME --> LEDGER[Bot internal ledger balance updated]
    SAME --> AUDIT[bot_audit_events + audit_logs]
```

## 8. Market Data / TradingView Integration

```mermaid
flowchart LR
    TV[TradingView Source] --> ADAPTER[Market-Data Adapter]
    ADAPTER --> NORM[Normalize OHLCV/symbol metadata]
    NORM --> CACHE[(Redis Cache)]
    CACHE --> API[GET /markets, /candles, /ticker, /orderbook, /trades]
    NORM --> WSFEED[Websocket/SSE: ticker + candle stream]
    WSFEED --> REDISPUBSUB[(Redis Pub/Sub fanout)]
    REDISPUBSUB --> CLIENTS[Connected clients across instances]
```

## 9. Data Model Relationship Overview

```mermaid
erDiagram
    USERS ||--o{ SESSIONS : has
    USERS ||--o{ WALLET_BALANCES : has
    USERS ||--o{ DEPOSITS : makes
    USERS ||--o{ WITHDRAWALS : requests
    USERS ||--o{ ORDERS : places
    USERS ||--o{ POSITIONS : holds
    USERS ||--o{ LEDGER_ENTRIES : owns

    MARKETS ||--o{ ORDERS : traded_on
    MARKETS ||--o{ BOTS : assigned_to
    MARKETS ||--o{ POSITIONS : tracked_on

    ORDERS ||--o{ ORDER_EVENTS : emits
    ORDERS ||--o{ FILLS : produces

    BOTS ||--o{ ORDERS : places
    BOTS ||--o{ POSITIONS : holds
    BOTS ||--o{ BOT_LEDGER_BALANCES : funded_by
    BOTS ||--o{ BOT_AUDIT_EVENTS : logs

    TOKENS ||--o{ TOKEN_SUPPLY_EVENTS : records

    USERS ||--o{ P2P_OFFERS : creates
    P2P_OFFERS ||--o{ P2P_ORDERS : generates

    USERS ||--o{ SUPPORT_TICKETS : opens
    SUPPORT_TICKETS ||--o{ SUPPORT_MESSAGES : contains

    USERS ||--o{ RISK_LIMITS : constrained_by
    BOTS ||--o{ RISK_LIMITS : constrained_by
```

## 10. Delivery Phases (roadmap)

```mermaid
flowchart LR
    P1[Phase 1: Foundation<br/>schema, auth, RBAC, logging] --> P2[Phase 2: Market Data<br/>TradingView feed, candles, ticker]
    P2 --> P3[Phase 3: Trading Core<br/>ledger, orders, matching, fills, positions]
    P3 --> P4[Phase 4: Bot System<br/>market-maker worker, config API, kill switch]
    P4 --> P5[Phase 5: Scale/Hardening<br/>Redis queues, rate limits, load tests]
```
