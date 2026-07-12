-- DEX Backend — Full PostgreSQL Schema
-- Single database, one Postgres instance, modular by domain (see plan.md / api_requirements.md).
-- Written as raw SQL; mirror this into prisma/schema.prisma per Foundation phase (plan.md Delivery Phases #1).

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- gen_random_uuid()

-- ============================================================
-- 1. AUTH / USERS / WALLET IDENTITY
-- ============================================================

CREATE TYPE user_status AS ENUM ('active', 'suspended', 'banned');
CREATE TYPE user_role AS ENUM ('user', 'admin', 'bot_service');

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_address TEXT NOT NULL UNIQUE,
  chain         TEXT NOT NULL,
  role          user_role NOT NULL DEFAULT 'user',
  status        user_status NOT NULL DEFAULT 'active',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_wallet_address ON users (wallet_address);

-- nonces issued for wallet signature proof-of-ownership (api_requirements.md #2)
CREATE TABLE auth_nonces (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_address TEXT NOT NULL,
  nonce         TEXT NOT NULL UNIQUE,
  expires_at    TIMESTAMPTZ NOT NULL,
  consumed_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_auth_nonces_wallet ON auth_nonces (wallet_address);
CREATE INDEX idx_auth_nonces_expires ON auth_nonces (expires_at);

CREATE TABLE sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_token TEXT NOT NULL UNIQUE,
  chain         TEXT NOT NULL,
  signed_proof  TEXT NOT NULL,
  issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ NOT NULL,
  revoked_at    TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user ON sessions (user_id);
CREATE INDEX idx_sessions_token ON sessions (session_token);

-- ============================================================
-- 2. WALLETS / BALANCES / FUNDING
-- ============================================================

CREATE TYPE balance_kind AS ENUM ('available', 'locked', 'pending');

CREATE TABLE wallet_balances (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  asset         TEXT NOT NULL,
  kind          balance_kind NOT NULL,
  amount        NUMERIC(38, 18) NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, asset, kind)
);

CREATE INDEX idx_wallet_balances_user ON wallet_balances (user_id);

CREATE TABLE deposit_addresses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chain         TEXT NOT NULL,
  asset         TEXT NOT NULL,
  address       TEXT NOT NULL,
  memo_tag      TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, chain, asset)
);

CREATE TYPE deposit_status AS ENUM ('pending', 'confirming', 'confirmed', 'rejected');

CREATE TABLE deposits (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chain             TEXT NOT NULL,
  asset             TEXT NOT NULL,
  tx_hash           TEXT NOT NULL,
  sender_address    TEXT NOT NULL,
  recipient_address TEXT NOT NULL,
  amount            NUMERIC(38, 18) NOT NULL,
  confirmations     INTEGER NOT NULL DEFAULT 0,
  status            deposit_status NOT NULL DEFAULT 'pending',
  credited_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (chain, tx_hash)
);

CREATE INDEX idx_deposits_user ON deposits (user_id);
CREATE INDEX idx_deposits_status ON deposits (status);

CREATE TYPE withdrawal_status AS ENUM ('pending', 'awaiting_second_signature', 'queued', 'signing', 'broadcast', 'confirmed', 'failed', 'rejected');

CREATE TABLE withdrawals (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chain             TEXT NOT NULL,
  asset             TEXT NOT NULL,
  destination_address TEXT NOT NULL,
  amount            NUMERIC(38, 18) NOT NULL,
  status            withdrawal_status NOT NULL DEFAULT 'pending',
  first_signature   TEXT NOT NULL,
  second_signature  TEXT,
  tx_hash           TEXT,
  idempotency_key   TEXT NOT NULL UNIQUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_withdrawals_user ON withdrawals (user_id);
CREATE INDEX idx_withdrawals_status ON withdrawals (status);

CREATE TYPE ledger_entry_type AS ENUM ('deposit', 'withdrawal', 'internal_transfer', 'fee', 'trade_settlement', 'bot_allocation');

CREATE TABLE ledger_entries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  bot_id        UUID, -- nullable FK added after bots table exists (see ALTER below)
  entry_type    ledger_entry_type NOT NULL,
  asset         TEXT NOT NULL,
  amount        NUMERIC(38, 18) NOT NULL,
  reference_id  UUID, -- points to deposits.id / withdrawals.id / fills.id depending on entry_type
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ledger_entries_user ON ledger_entries (user_id);
CREATE INDEX idx_ledger_entries_bot ON ledger_entries (bot_id);

-- ============================================================
-- 3. MARKETS / TOKENS
-- ============================================================

CREATE TYPE market_type AS ENUM ('spot');

CREATE TABLE markets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  symbol        TEXT NOT NULL UNIQUE,
  base_asset    TEXT NOT NULL,
  quote_asset   TEXT NOT NULL,
  market_type   market_type NOT NULL DEFAULT 'spot',
  is_active     BOOLEAN NOT NULL DEFAULT true,
  metadata      JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TYPE token_type AS ENUM ('stable', 'floating');

CREATE TABLE tokens (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  symbol            TEXT NOT NULL UNIQUE,
  chain             TEXT NOT NULL,
  contract_address  TEXT,
  decimals          SMALLINT NOT NULL,
  token_type        token_type NOT NULL,
  max_supply        NUMERIC(38, 18),
  circulating_supply NUMERIC(38, 18) NOT NULL DEFAULT 0,
  locked_supply     NUMERIC(38, 18) NOT NULL DEFAULT 0,
  is_paused         BOOLEAN NOT NULL DEFAULT false,
  peg_target        NUMERIC(38, 18), -- for stable coin peg tracking
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TYPE token_supply_action AS ENUM ('mint', 'burn', 'pause', 'unpause');

CREATE TABLE token_supply_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_id      UUID NOT NULL REFERENCES tokens(id) ON DELETE CASCADE,
  action        token_supply_action NOT NULL,
  amount        NUMERIC(38, 18),
  performed_by  UUID NOT NULL REFERENCES users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. ORDERS / MATCHING / FILLS / POSITIONS
-- ============================================================

CREATE TYPE order_side AS ENUM ('buy', 'sell');
CREATE TYPE order_type AS ENUM ('market', 'limit');
CREATE TYPE order_status AS ENUM ('accepted', 'open', 'partially_filled', 'filled', 'cancelled', 'rejected', 'expired');
CREATE TYPE order_owner_type AS ENUM ('user', 'bot');

CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type        order_owner_type NOT NULL,
  user_id           UUID REFERENCES users(id) ON DELETE CASCADE,
  bot_id            UUID, -- FK added after bots table exists
  market_id         UUID NOT NULL REFERENCES markets(id),
  side              order_side NOT NULL,
  order_type        order_type NOT NULL,
  price             NUMERIC(38, 18), -- null for market orders
  size              NUMERIC(38, 18) NOT NULL,
  filled_size       NUMERIC(38, 18) NOT NULL DEFAULT 0,
  status            order_status NOT NULL DEFAULT 'accepted',
  idempotency_key   TEXT NOT NULL UNIQUE,
  rejection_reason  TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_order_owner CHECK (
    (owner_type = 'user' AND user_id IS NOT NULL AND bot_id IS NULL) OR
    (owner_type = 'bot' AND bot_id IS NOT NULL AND user_id IS NULL)
  ),
  CONSTRAINT chk_bot_market_only CHECK (
    owner_type <> 'bot' OR order_type = 'market'
  )
);

CREATE INDEX idx_orders_user ON orders (user_id);
CREATE INDEX idx_orders_bot ON orders (bot_id);
CREATE INDEX idx_orders_market_status ON orders (market_id, status);

CREATE TABLE fills (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  market_id     UUID NOT NULL REFERENCES markets(id),
  taker_order_id UUID NOT NULL REFERENCES orders(id),
  maker_order_id UUID NOT NULL REFERENCES orders(id),
  price         NUMERIC(38, 18) NOT NULL,
  size          NUMERIC(38, 18) NOT NULL,
  taker_side    order_side NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_fills_market ON fills (market_id);
CREATE INDEX idx_fills_taker_order ON fills (taker_order_id);
CREATE INDEX idx_fills_maker_order ON fills (maker_order_id);

CREATE TYPE order_event_type AS ENUM ('accepted', 'matched', 'partial_fill', 'full_fill', 'cancelled', 'rejected', 'expired');

CREATE TABLE order_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  event_type    order_event_type NOT NULL,
  detail        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_events_order ON order_events (order_id);

CREATE TABLE positions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  bot_id        UUID, -- FK added after bots table exists
  market_id     UUID NOT NULL REFERENCES markets(id),
  size          NUMERIC(38, 18) NOT NULL DEFAULT 0, -- signed: positive=long, negative=short
  avg_entry_price NUMERIC(38, 18) NOT NULL DEFAULT 0,
  realized_pnl  NUMERIC(38, 18) NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_position_owner CHECK (
    (user_id IS NOT NULL AND bot_id IS NULL) OR (user_id IS NULL AND bot_id IS NOT NULL)
  ),
  UNIQUE (user_id, market_id),
  UNIQUE (bot_id, market_id)
);

CREATE INDEX idx_positions_user ON positions (user_id);
CREATE INDEX idx_positions_bot ON positions (bot_id);

-- ============================================================
-- 5. MARKET-MAKER BOT
-- ============================================================

CREATE TABLE bots (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  market_id         UUID NOT NULL REFERENCES markets(id),
  max_position_size NUMERIC(38, 18) NOT NULL,
  max_notional      NUMERIC(38, 18) NOT NULL,
  max_daily_loss    NUMERIC(38, 18) NOT NULL,
  spread_bps        NUMERIC(10, 4) NOT NULL DEFAULT 10,
  enabled           BOOLEAN NOT NULL DEFAULT false,
  killed            BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bots_market ON bots (market_id);

-- bot's internal ledger allocation balance (plan.md "Bot Inventory Funding")
CREATE TABLE bot_ledger_balances (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id        UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  asset         TEXT NOT NULL,
  amount        NUMERIC(38, 18) NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (bot_id, asset)
);

CREATE TYPE bot_action AS ENUM ('created', 'updated', 'enabled', 'disabled', 'kill_switch');

CREATE TABLE bot_audit_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id        UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  action        bot_action NOT NULL,
  performed_by  UUID REFERENCES users(id),
  detail        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_bot_audit_events_bot ON bot_audit_events (bot_id);

-- Now that bots exists, wire deferred FKs:
ALTER TABLE ledger_entries  ADD CONSTRAINT fk_ledger_entries_bot  FOREIGN KEY (bot_id) REFERENCES bots(id) ON DELETE CASCADE;
ALTER TABLE orders          ADD CONSTRAINT fk_orders_bot          FOREIGN KEY (bot_id) REFERENCES bots(id) ON DELETE CASCADE;
ALTER TABLE positions       ADD CONSTRAINT fk_positions_bot       FOREIGN KEY (bot_id) REFERENCES bots(id) ON DELETE CASCADE;

-- ============================================================
-- 6. P2P
-- ============================================================

CREATE TYPE p2p_offer_status AS ENUM ('active', 'paused', 'closed');

CREATE TABLE p2p_offers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  asset         TEXT NOT NULL,
  fiat_currency TEXT NOT NULL,
  price         NUMERIC(38, 18) NOT NULL,
  min_amount    NUMERIC(38, 18) NOT NULL,
  max_amount    NUMERIC(38, 18) NOT NULL,
  status        p2p_offer_status NOT NULL DEFAULT 'active',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_p2p_offers_user ON p2p_offers (user_id);

CREATE TYPE p2p_order_status AS ENUM ('pending', 'accepted', 'released', 'disputed', 'cancelled');

CREATE TABLE p2p_orders (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id      UUID NOT NULL REFERENCES p2p_offers(id),
  buyer_id      UUID NOT NULL REFERENCES users(id),
  seller_id     UUID NOT NULL REFERENCES users(id),
  amount        NUMERIC(38, 18) NOT NULL,
  status        p2p_order_status NOT NULL DEFAULT 'pending',
  escrow_ledger_entry_id UUID REFERENCES ledger_entries(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_p2p_orders_buyer ON p2p_orders (buyer_id);
CREATE INDEX idx_p2p_orders_seller ON p2p_orders (seller_id);

-- ============================================================
-- 7. SUPPORT / NOTIFICATIONS
-- ============================================================

CREATE TYPE support_ticket_status AS ENUM ('open', 'pending', 'resolved', 'closed');

CREATE TABLE support_tickets (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject       TEXT NOT NULL,
  status        support_ticket_status NOT NULL DEFAULT 'open',
  related_order_id UUID REFERENCES orders(id),
  related_tx_hash  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_support_tickets_user ON support_tickets (user_id);

CREATE TABLE support_messages (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id     UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  author_id     UUID NOT NULL REFERENCES users(id),
  body          TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_support_messages_ticket ON support_messages (ticket_id);

CREATE TABLE notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  body          TEXT NOT NULL,
  read_at       TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user ON notifications (user_id);

-- ============================================================
-- 8. RISK
-- ============================================================

CREATE TYPE risk_scope AS ENUM ('user', 'bot', 'global');

CREATE TABLE risk_limits (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope         risk_scope NOT NULL,
  user_id       UUID REFERENCES users(id) ON DELETE CASCADE,
  bot_id        UUID REFERENCES bots(id) ON DELETE CASCADE,
  max_order_size NUMERIC(38, 18),
  max_notional   NUMERIC(38, 18),
  max_daily_loss NUMERIC(38, 18),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TYPE risk_event_type AS ENUM ('limit_breach', 'kill_switch', 'global_halt');

CREATE TABLE risk_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type    risk_event_type NOT NULL,
  user_id       UUID REFERENCES users(id),
  bot_id        UUID REFERENCES bots(id),
  detail        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_risk_events_user ON risk_events (user_id);
CREATE INDEX idx_risk_events_bot ON risk_events (bot_id);

-- ============================================================
-- 9. AUDIT LOG (cross-cutting, api_requirements.md #14)
-- ============================================================

CREATE TABLE audit_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES users(id),
  actor_type    order_owner_type, -- reuse: 'user' or 'bot' actor; admin actions still actor_type='user' with role='admin'
  action        TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id   UUID,
  request_id    TEXT,
  detail        JSONB NOT NULL DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_actor ON audit_logs (actor_user_id);
CREATE INDEX idx_audit_logs_resource ON audit_logs (resource_type, resource_id);
CREATE INDEX idx_audit_logs_created ON audit_logs (created_at);

COMMIT;
