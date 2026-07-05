# Coin Creation Plan

## Summary

Create two native platform tokens for the DEX ecosystem, with Avalanche as the default chain unless a later decision changes it:

- a stable coin that tracks `USDT` at approximately `1.00`
- a normal utility/market coin whose price moves up and down based on market demand, liquidity, and platform activity

The token system should be designed so both coins can later integrate with trading, deposits/withdrawals, on-chain verification, and in-app balances.

## Token Model

### 1. Stable Coin

- Purpose:
  - act as the platform’s stable settlement asset
  - mirror `USDT` price behavior as closely as possible
  - be usable for trading, funding, and internal transfers
- Price behavior:
  - target price: `1.00`
  - maintain tight peg tolerance
  - support mint/burn or reserve-backed supply logic depending on final treasury design
- Risk controls:
  - supply caps if required
  - treasury backing rules
  - re-peg monitoring
  - emergency pause/blacklist controls if compliance requires them

### 2. Normal Coin

- Purpose:
  - act as the platform’s native growth/utility token
  - be tradable on the platform
  - support market-driven price discovery
- Price behavior:
  - price is not fixed
  - price moves based on demand, liquidity, market maker activity, and exchange order flow
  - can trade against stable coin pairs
- Risk controls:
  - max supply and emission schedule
  - treasury and liquidity management
  - price manipulation monitoring
  - market-maker exposure limits

## Chain Choice

### Default Chain: Avalanche

- Use Avalanche as the primary deployment target for token contracts unless there is a later reason to move to another chain.
- Reasons:
  - fast finality
  - low transaction fees compared with many L1s
  - mature wallet support
  - good fit for trading and frequent transfers

## High-Level Architecture

- Smart contracts for:
  - stable coin
  - normal coin
  - mint/burn or treasury control if needed
  - role-based access control
- Backend services for:
  - token metadata
  - supply tracking
  - wallet balances
  - deposit and withdrawal verification
  - transaction indexing
  - admin controls and monitoring
- Liquidity services for:
  - initial market-making
  - managed spread support
  - pair setup against stable coin

## Stable Coin Plan

1. Define peg mechanism
   - choose between fully reserve-backed, overcollateralized, or treasury-managed mint/burn
   - define the peg target and allowed deviation window

2. Define issuance policy
   - who can mint
   - who can burn
   - under what conditions mint/burn is allowed

3. Define reserve management
   - how reserves are stored and audited
   - how reserve balances are reported
   - how peg deviations are handled

4. Define transfer and settlement usage
   - internal transfers
   - deposits and withdrawals
   - settlement asset for platform trades

## Normal Coin Plan

1. Define supply model
   - fixed supply or capped supply
   - whether tokens are pre-minted or released over time

2. Define distribution
   - treasury allocation
   - team allocation
   - user rewards
   - liquidity allocation
   - ecosystem incentives

3. Define price discovery
   - trading pair against the stable coin
   - market maker support
   - order book liquidity rules

4. Define utility
   - fee discounts
   - staking
   - rewards
   - governance if needed later

## Backend Requirements

- Token registry service
  - token symbol, decimals, chain, contract address, supply status
- Wallet balance service
  - per-user asset balances
  - on-chain balance sync
  - pending vs confirmed balances
- On-chain verification service
  - watch contract events
  - verify transfers using RPC and explorers
  - reconcile deposits and withdrawals
- Market pricing service
  - stable coin pegged pricing
  - normal coin market price updates
  - TradingView integration for chart display

## Security and Governance

- role-based contract control
- admin approval for mint/burn
- multisig treasury control
- emergency pause capability
- audit log for every privileged token action
- anti-abuse checks for large transfers and suspicious activity

## Delivery Phases

1. Token design
   - finalize token names, symbols, decimals, and supply rules
   - choose peg model for the stable coin

2. Contract development
   - implement Avalanche contracts
   - add access control, mint/burn, pause, and event logs

3. Backend integration
   - register tokens in the platform
   - connect wallet balances and on-chain verification
   - support deposits, withdrawals, and internal transfers

4. Liquidity launch
   - seed initial liquidity
   - configure market maker support
   - expose token pairs on the platform

5. Hardening
   - audit contracts
   - test deposit/withdrawal flows
   - load test balance sync and pricing updates

## Test Plan

- Contract tests for:
  - mint
  - burn
  - transfer
  - access control
  - pause/unpause
  - event emission

- Backend tests for:
  - token registry
  - wallet balance sync
  - deposit verification
  - withdrawal reconciliation
  - price updates

- Simulation tests for:
  - stable coin peg behavior
  - normal coin price movement
  - market maker interaction

## Expected Charges

These are rough launch-stage estimates for an in-house build. No outsourcing or external development cost is included. Final costs depend on contract complexity, audit scope, liquidity size, chain activity, and vendor choices for infrastructure or data services.

### One-Time Costs

- Smart contract engineering:
  - internal engineering time only
  - budget impact comes from team salaries, not external vendor fees
- Security audit:
  - if performed internally, budget for engineering review time and test coverage
  - if later sent to a third-party auditor, that would be an additional optional cost not included here
- Legal/compliance review:
  - internal coordination cost only unless later legal counsel is engaged
- Token branding and listing assets:
  - internal design time only

### Chain and Deployment Costs

- Avalanche contract deployment:
  - usually low compared with Ethereum-style deployments
  - expected to be a small one-time network fee rather than a major expense
- Ongoing Avalanche transaction fees:
  - generally low, but depend on usage and network conditions
- Blockchain indexing / RPC provider:
  - `$50 - $500+/month` for light usage
  - more if you need high-throughput event indexing and webhooks

### Liquidity and Market Launch Costs

- Initial liquidity seed for the stable coin pair:
  - depends on target peg depth
  - practical launch range: `$25,000 - $250,000+`
- Initial liquidity seed for the normal coin:
  - practical launch range: `$10,000 - $200,000+`
- Market-maker support capital:
  - should be budgeted separately from the token creation cost
  - amount depends on expected spread control and volatility management

### Backend / Infrastructure Costs

- AWS EC2, RDS PostgreSQL, Redis, load balancer, S3, logging:
  - small launch: `$150 - $800/month`
  - growth phase: `$800 - $3,000+/month`
  - higher if traffic, storage, or websocket load grows quickly

### Practical Launch Budget

- Minimal technical launch:
  - mostly internal engineering cost plus chain and infrastructure fees
- Production launch with liquidity:
  - liquidity capital and ongoing infrastructure become the primary cash expenses
- Well-capitalized launch:
  - larger liquidity reserve, larger infra footprint, and more operational headroom

## Assumptions

- Avalanche is the default chain.
- The stable coin should track `USDT` at roughly `1.00`.
- The normal coin should be freely floating in price.
- Final legal/compliance treatment is out of scope for this first technical plan and should be reviewed before launch.
