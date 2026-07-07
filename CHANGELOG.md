# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

## [0.4.0] - 2026-07-07

### Added

- Realtime WebSocket streaming via the PolyNode API (`Polymarket.Websocket`):
  subscriptions to fills, settlements, trades, prices, wallets, oracle events,
  and more, with filters, automatic reconnection with exponential backoff, and
  gap backfill via the `since` filter.
- `Polymarket.Websocket.Message` for building/decoding PolyNode protocol
  messages.
- Offline WebSocket test suite backed by a local Bandit server.

## [0.3.0] - 2025-12-31

### Added

- Gamma API wrapper (markets, events, tags, sports).
- Data API wrapper (positions, trades, activity, holders, value).
- CLOB API wrapper (read endpoints) and EIP-712 signing for order placement/cancellation.
- Configurable HTTP base URLs and Req options via application env.
- Offline test suite using `Req.Test`.

