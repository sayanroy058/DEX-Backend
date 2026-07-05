# API Requirements

This document defines the backend API surface required for the DEX platform.

The API must support:
- wallet-only login
- wallet funding and on-chain verification
- market data and charting
- order entry and matching
- positions, balances, and portfolio views
- market-maker bot control
- token and coin management
- P2P and supporting platform services

## 1. Core API Principles

- All APIs must be versioned, starting with `/api/v1`.
- All authenticated requests must be stateless and session-based.
- All trading actions must be audit logged.
- All money movement actions must have idempotency protection.
- All order placement and fill-related actions must pass through the platform matching engine.
- All wallet funding actions must be verifiable on-chain.
- All responses must use a consistent JSON envelope and predictable error format.

## 2. Authentication and Wallet Login APIs

No email/password login is allowed.

### Required endpoints

- `POST /api/v1/auth/nonce`
  - returns a unique nonce for the wallet address
  - used to prove wallet ownership

- `POST /api/v1/auth/verify`
  - accepts wallet address, signed message, chain, and nonce
  - verifies the signature
  - creates a new user record if the wallet has never logged in before
  - returns session tokens / session cookie data

- `POST /api/v1/auth/logout`
  - invalidates the current session

- `GET /api/v1/auth/session`
  - returns current authenticated wallet identity and session status

- `GET /api/v1/auth/me`
  - returns the current user profile and wallet-linked account summary

### Required behavior

- The wallet address is the primary identity.
- A user account is created on first successful login.
- One wallet can map to one primary platform identity unless multi-wallet linking is later added.
- Nonces must expire.
- Replay protection is required.
- Sessions must be revocable.
- `POST /api/v1/auth/nonce` is unauthenticated by nature and is a wallet-enumeration/spam target: rate limit per IP and per wallet address, and cap outstanding unexpired nonces per wallet.

## 3. Wallet and Funding APIs

### Required endpoints

- `GET /api/v1/wallet/balances`
  - returns all user balances
  - includes available, locked, and pending balances

- `GET /api/v1/wallet/addresses`
  - returns platform deposit addresses or funding destinations by chain/asset

- `POST /api/v1/wallet/deposit/request`
  - creates a deposit intent or funding request
  - returns destination address, network, memo/tag if applicable, and request id

- `POST /api/v1/wallet/deposit/verify`
  - verifies a submitted transaction hash
  - validates sender, recipient, chain, asset, and amount
  - should be safe to call repeatedly

- `GET /api/v1/wallet/deposits`
  - returns deposit history and status

- `POST /api/v1/wallet/withdraw/request`
  - creates a withdrawal request
  - validates risk checks (limits, velocity, balance)
  - requires a second wallet signature (re-sign the withdrawal payload with the same connected wallet) as the second factor, since no email/password/TOTP channel exists on this platform

- `POST /api/v1/wallet/withdraw/confirm`
  - confirms a pending withdrawal by submitting the second signature
  - request is queued for the isolated signing worker (see plan.md Custody and Key Management) once confirmed; API layer never signs or broadcasts directly

- `GET /api/v1/wallet/withdrawals`
  - returns withdrawal history and status

- `GET /api/v1/wallet/transactions`
  - returns deposits, withdrawals, internal transfers, fees, and settlement events

### Required behavior

- Every deposit must be linked to a blockchain transaction hash.
- Deposits are only credited after verification and confirmation policy is satisfied.
- Withdrawals must remain pending until approved, signed, broadcast, and confirmed.
- Internal ledger movements must be tracked separately from on-chain movements.

## 4. Market Data APIs

TradingView is the market/chart source.

### Required endpoints

- `GET /api/v1/markets`
  - returns the full instrument list
  - includes symbol, asset type, market type, price, volume, funding, and metadata

- `GET /api/v1/markets/:symbol`
  - returns single market details

- `GET /api/v1/markets/:symbol/ticker`
  - returns live price, change, and liquidity summary

- `GET /api/v1/markets/:symbol/candles`
  - returns normalized OHLCV candles
  - supports resolution, from, to, and count parameters

- `GET /api/v1/markets/:symbol/orderbook`
  - returns current aggregated bid/ask depth

- `GET /api/v1/markets/:symbol/trades`
  - returns recent public trades

- `GET /api/v1/markets/trending`
  - returns trending instruments

- `GET /api/v1/markets/gainers`
  - returns top gainers

- `GET /api/v1/markets/losers`
  - returns top losers

- `GET /api/v1/markets/search?q=`
  - searches markets by symbol, base asset, or metadata

### Required behavior

- Candle data must be normalized into a consistent schema for the frontend charting library.
- Market data should be heavily cached.
- The backend should expose websocket/SSE updates for live ticker and trade feed changes.
- TradingView integration should be isolated behind a market-data adapter so it can be replaced later if needed.

## 5. Order Entry and Matching APIs

This is the core trading surface.

### Required endpoints

- `POST /api/v1/orders`
  - creates a new order
  - supports spot and other approved market types
  - supports market and limit orders if enabled by the platform
  - must enforce idempotency

- `GET /api/v1/orders`
  - returns a list of the user’s orders

- `GET /api/v1/orders/:id`
  - returns order details and lifecycle state

- `POST /api/v1/orders/:id/cancel`
  - cancels an open order if eligible

- `POST /api/v1/orders/bulk-cancel`
  - cancels multiple open orders

- `GET /api/v1/orders/open`
  - returns open working orders

- `GET /api/v1/orders/history`
  - returns historical orders and execution details

- `GET /api/v1/fills`
  - returns fills and partial fills for the user

- `GET /api/v1/positions`
  - returns open positions

- `GET /api/v1/portfolio/summary`
  - returns balances, positions, margin status, and portfolio totals

### Matching engine behavior

- Every submitted order is entered into the platform order venue.
- Matching must occur inside the platform.
- If a market order crosses resting liquidity, it executes against available orders.
- If the market-maker bot is on the opposite side of the trade, it can be filled as counterparty liquidity.
- Order execution events must emit:
  - order accepted
  - order matched
  - partial fill
  - full fill
  - cancel
  - reject
  - expire

### Required order validation

- symbol must exist
- user must be authenticated
- sufficient balance or margin must exist
- order size and notional limits must be checked
- market-maker bot fills must respect bot risk limits
- duplicate requests must be rejected or deduplicated using idempotency keys

## 6. Bot APIs

The market-maker bot is internal and spot-only.

### Required endpoints

- `GET /api/v1/bots`
  - returns bot list and status

- `GET /api/v1/bots/:id`
  - returns bot details, config, and runtime state

- `POST /api/v1/bots`
  - creates a bot configuration

- `PATCH /api/v1/bots/:id`
  - updates bot settings

- `POST /api/v1/bots/:id/enable`
  - enables a bot

- `POST /api/v1/bots/:id/disable`
  - disables a bot

- `POST /api/v1/bots/:id/kill-switch`
  - immediately stops bot trading and cancels pending activity

- `GET /api/v1/bots/:id/executions`
  - returns bot execution history

- `GET /api/v1/bots/:id/risk`
  - returns current inventory, exposure, and risk status

### Required behavior

- bot may only place spot market orders
- bot must never place limit orders
- bot must be able to quote inventory-aware liquidity internally
- bot actions must be audited and replayable
- bot execution must be asynchronous and queue-backed
- bot must share the same matching engine and fill pipeline as users

## 7. Coin and Token APIs

These APIs support the two native coins described in the coin creation plan.

### Required endpoints

- `GET /api/v1/tokens`
  - returns platform token registry

- `GET /api/v1/tokens/:symbol`
  - returns token metadata, chain, contract, decimals, and supply info

- `GET /api/v1/tokens/:symbol/price`
  - returns current platform price

- `GET /api/v1/tokens/:symbol/supply`
  - returns circulating, locked, and max supply

- `POST /api/v1/tokens/:symbol/mint`
  - admin-only

- `POST /api/v1/tokens/:symbol/burn`
  - admin-only

- `POST /api/v1/tokens/:symbol/pause`
  - admin-only

- `POST /api/v1/tokens/:symbol/unpause`
  - admin-only

### Required behavior

- stable coin should show peg status and deviation tracking
- normal coin should show live floating market price
- supply-changing operations must be fully audited

## 8. P2P APIs

### Required endpoints

- `GET /api/v1/p2p/offers`
- `POST /api/v1/p2p/offers`
- `PATCH /api/v1/p2p/offers/:id`
- `POST /api/v1/p2p/offers/:id/pause`
- `POST /api/v1/p2p/offers/:id/resume`
- `GET /api/v1/p2p/orders`
- `POST /api/v1/p2p/orders/:id/accept`
- `POST /api/v1/p2p/orders/:id/release`
- `POST /api/v1/p2p/orders/:id/dispute`
- `POST /api/v1/p2p/orders/:id/cancel`

### Required behavior

- P2P orders must be tracked in the same user ledger.
- If escrow is used, it must be represented in internal balances and audit logs.

## 9. Portfolio and Account APIs

### Required endpoints

- `GET /api/v1/account/overview`
- `GET /api/v1/account/ledger`
- `GET /api/v1/account/performance`
- `GET /api/v1/account/fees`
- `GET /api/v1/account/alerts`
- `GET /api/v1/account/activity`

### Required behavior

- portfolio summaries must be derived from ledger and fill data
- realized and unrealized PnL must be computable from fills and marks

## 10. Admin APIs

### Required endpoints

- `GET /api/v1/admin/users`
- `GET /api/v1/admin/users/:id`
- `PATCH /api/v1/admin/users/:id/status`
- `GET /api/v1/admin/orders`
- `GET /api/v1/admin/fills`
- `GET /api/v1/admin/bots`
- `POST /api/v1/admin/bots/:id/stop`
- `GET /api/v1/admin/risk-events`
- `GET /api/v1/admin/audit-logs`

### Required behavior

- all admin actions require elevated permissions
- all admin actions must be audited
- bot kill-switch and market halts must be immediately visible here

## 11. Support and Notification APIs

### Required endpoints

- `POST /api/v1/support/tickets`
- `GET /api/v1/support/tickets`
- `GET /api/v1/support/tickets/:id`
- `POST /api/v1/support/tickets/:id/messages`
- `GET /api/v1/notifications`
- `POST /api/v1/notifications/read`

### Required behavior

- support tickets should attach account context, wallet, order ids, or tx hashes where relevant
- notification delivery should support in-app and future push channels

## 12. Websocket / Streaming APIs

### Required channels

- market ticker stream
- candle update stream
- order book stream
- trade print stream
- order status stream
- fill stream
- bot status stream
- deposit confirmation stream

### Required behavior

- streams must be scalable across multiple app instances
- Redis pub/sub or equivalent must be used for fanout
- clients must be able to resubscribe after reconnect

## 13. Risk and Safety APIs

### Required endpoints

- `GET /api/v1/risk/limits`
- `GET /api/v1/risk/status`
- `POST /api/v1/risk/limits`
- `POST /api/v1/risk/kill-switch`

### Required behavior

- user-level and bot-level risk must be separable
- global trading halts must be possible
- deposits, withdrawals, and bot orders must all respect configured limits

## 14. Required Cross-Cutting Concerns

### Authentication

- signed wallet proof-of-ownership
- nonce expiration
- replay prevention
- session revocation

### Authorization

- RBAC for admin vs normal user vs bot service accounts

### Idempotency

- required for:
  - login verification
  - deposits
  - withdrawals
  - order creation
  - cancel requests
  - bot commands

### Audit logging

- required for:
  - wallet login
  - every order lifecycle event
  - deposit and withdrawal verification
  - bot enable/disable/kill actions
  - token mint/burn/pause actions
  - admin operations

### Validation

- use strict schema validation for every request
- reject unknown or malformed payloads

### Error format

- all errors should return:
  - stable machine-readable error code
  - human-readable message
  - request id
  - optional details object

## 15. Minimum API Set for First Release

If the team needs to phase delivery, the minimum release should include:

1. wallet login and session APIs
2. wallet balances and deposit verification APIs
3. market data and candle APIs
4. order placement, cancel, history, and fills APIs
5. matching engine APIs and streaming updates
6. bot create/enable/disable/kill APIs
7. token registry and pricing APIs
8. admin audit and risk APIs

## 16. Rate Limiting

- Per-endpoint rate limits required, enforced via Redis, tiered by sensitivity:
  - auth endpoints (`/auth/nonce`, `/auth/verify`): strict, per-IP and per-wallet
  - order entry (`POST /orders`, cancel, bulk-cancel): per-user, tuned to prevent order-spam/matching-engine overload
  - market data (`GET /markets/*`): generous, cache-backed, per-IP
  - withdrawal endpoints: strict, per-user, independent of the signing worker's own caps

## 17. Assumptions

- No email/password login exists anywhere in the platform.
- Wallet address is the primary identity.
- The platform owns the order venue and matching pipeline.
- The market-maker bot only places spot market orders.
- TradingView is the source of chart and market-data integration.
- Avalanche is the default chain for the coin project unless changed later.
