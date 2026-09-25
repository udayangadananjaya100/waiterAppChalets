# Waiter app UX and bug audit

Date: 2026-09-25. App baseline: `6dab876`.

Scope: Flutter source, existing backend route contracts, six practice-flow screenshots, interaction/contract tests, and isolated local reproduction tests. No live writes, physical-device camera tests, production login, or RLS authorization verification were performed. The findings below were addressed in the app after the audit unless a limitation is stated.

Priority: P1 = address before staff rollout; P2 = address in the next usability/reliability pass.

## Confirmed bugs and workflow gaps

### B1 — P1: Shared inventory can be oversold within one draft

**Fixed in app:** draft and submission validation now aggregate demand by inventory item and batch. Concurrent-device atomic stock enforcement still requires a future backend transaction.

- Evidence: `lib/data/live_repository.dart:353` checks each cart line separately against the full batch quantity (`:367`). Cart identity is menu item plus batch, not shared inventory plus batch.
- Reproduction: two menu items reference the same inventory batch with stock 5; add 4 units of each. Both lines pass validation and the submit endpoint is called with total demand 8. Confirmed by an isolated repository test.
- Impact: the existing backend subtracts quantities sequentially and does not reject negative stock. An accepted order can exceed available inventory.
- Fix: aggregate draft demand by warehouse/inventory/batch before submission. Atomic server-side stock enforcement is also needed for concurrent devices; client checks alone cannot solve that race.

### B2 — P1: Hiding a menu item prevents serving an existing inventoried order line

**Fixed:** existing batch-linked order lines retain direct-service behavior even if the current menu hides the item.

- Evidence: `lib/data/live_repository.dart:287` removes unavailable menu items; `:448` decides whether an ordered item is directly serveable from this filtered menu. `lib/ui/order_screen.dart:416` uses the same inference for its ready state.
- Reproduction: order an inventoried drink, then set menu availability false while its kitchen status remains pending. `serve()` reports “No additional portions are ready yet.” Confirmed by an isolated repository test.
- Impact: already ordered drinks cannot be marked served even when physically ready.
- Fix: classify historical order lines using stable item metadata, independent of the current sellable menu.

### B3 — P1: Table handover has no claim action

**Contained:** the unsupported release control was removed so waiters cannot create an unclaimable handover state. A complete transfer feature still requires an authorized backend claim/transfer endpoint.

- Evidence: `lib/ui/order_screen.dart:123` offers release and promises another waiter can take over. `lib/data/live_repository.dart:469` permits releasing billed orders. `_guard()` requires the assigned waiter for serving and cashier handoff; the repository has no claim operation.
- Reproduction: release an open order that requires no additional items. The next waiter cannot mark items served or send its bill. Ownership is assigned only when submitting additional items through the current backend. A released billed order cannot even use that route through the app because additions are blocked.
- Impact: normal shift handover needs cashier/admin intervention or an unnecessary new item.
- Fix: introduce an explicit, authorized claim/transfer operation. Until available, restrict release and accurately explain the recovery path, particularly for billed orders.

### B4 — P1: An uncertain action can be unlocked without a post-action refresh

**Fixed:** the app persists the uncertain-action timestamp and only unlocks after a successful, newer refresh.

- Evidence: `lib/state/app_controller.dart:236` only requires `lastSync` to be less than 15 seconds old; it does not compare it with the uncertain action timestamp.
- Reproduction: sync, immediately encounter an ambiguous action failure, and select “I’ve checked” before another sync. The uncertainty marker is cleared. Confirmed by an isolated controller test.
- Impact: the operator can add the same items again without having fetched the result of the previous action.
- Fix: persist an operation timestamp/identifier and require a successful refresh after that operation; retain the operation payload for comparison.

### B5 — P2: Unsent drafts disappear after process death or restart

**Fixed:** drafts are persisted per server, waiter and table, restored only when ownership/order identity still matches, and revalidated against current price and stock.

- Evidence: `lib/state/app_controller.dart:17` stores drafts only in memory. Persistence saves uncertain table IDs, not the draft contents.
- Reproduction: add items and recreate the controller/process. The draft is empty. Confirmed by an isolated controller test.
- Impact: lost guest orders if Android reclaims the app. After an uncertain submission and restart, the instruction to compare the live order with the draft is impossible because the draft is gone.
- Fix: persist drafts per server/user/table with timestamps and the expected order ID; revalidate prices, stock and ownership on restore. Keep unresolved action details until reconciled.

### B6 — P2: Billing disables serving even when portions remain unserved

**Fixed:** existing items can be marked served while the bill is with the cashier, and the billing confirmation identifies remaining unserved portions.

- Evidence: `lib/data/live_repository.dart:419` checks only that the order is nonempty before billing. `lib/ui/order_screen.dart:90` disables editing for billed orders; `_guard()` also blocks serving billed orders. The cashier confirmation at `:591` does not identify remaining unserved portions.
- Reproduction: send a bill while a dish is preparing or not yet marked served. The waiter cannot subsequently record serving it through the app.
- Impact: early guest bill requests or accidental billing leave service tracking incomplete.
- Fix: agree on the restaurant workflow: either allow serving existing billed lines, or explicitly warn/block when unserved portions remain. Do not silently strand the action.

### B7 — P2: Menu price can disagree with the actual batch price

**Fixed:** menu cards show the one live batch price or a “From” price when eligible batches differ.

- Evidence: `lib/ui/home_screen.dart:819` always displays `dish.price`; the batch picker and cart use `batch.price`.
- Reproduction: configure a batch selling price different from the menu base price. Browse the menu, then select that batch; the quoted price changes.
- Impact: a waiter can tell a guest the wrong price before taking the order.
- Fix: show the actual sellable price, a price range, or “From …” for multiple batch prices; label price differences clearly in the picker.

### B8 — P2: Open bill preview does not update when the cashier changes the bill

**Fixed:** an open bill preview now resolves the latest order and lines from controller updates.

- Evidence: `lib/ui/order_screen.dart:908` receives a fixed `ServiceOrder` and item list. The bottom sheet does not subscribe to controller updates or resolve the order by ID.
- Reproduction: keep a bill preview open while the cashier changes its confirmed total or settles it. Floor polling can update the controller, but the existing sheet still displays the previous values/status.
- Impact: the waiter may show an outdated total to the guest.
- Fix: render the sheet from the current order ID using controller updates; show a clear state if the bill is changed, removed or unavailable.

## UX improvements

### U1 — P2: Ready dishes have no proactive alert

**Improved:** newly ready items now produce a foreground banner and haptic alert without repeating on every poll. Background push notifications remain outside the current backend contract.

The app polls every five seconds (`lib/state/app_controller.dart:128`), but ready portions only update visible counts/tags. There is no dedicated alert when a waiter is taking another table's order, and polling stops in the background. Add an in-app ready-items banner and optional sound/vibration; separately define background notification requirements. Avoid duplicate alerts on every poll.

### U2 — P2: Operational secondary text is very small

**Improved:** core operational descriptions, status tags, availability and table metadata were enlarged. Physical-device acceptance at 200% text scale remains recommended.

Screenshots and styles show many 9–11 logical-pixel labels, including item descriptions, availability, timing and recovery instructions (`lib/ui/home_screen.dart:817`, `lib/ui/order_screen.dart:195`). These are difficult to scan during service. Increase operational text sizes, preserve contrast, and validate at 200% text scale. Existing interaction coverage reaches 130%, so larger-scale accessibility is not verified.

### U3 — P2: Batch selection adds repeated decisions to order taking

**Fixed:** a single eligible batch is selected automatically; the picker remains when the waiter has a meaningful choice.

`lib/ui/order_screen.dart:45` opens “Choose a batch” on every addition of a batch-linked item, even when only one eligible batch exists. Automatically select a single eligible batch; where policy allows, offer the earliest-expiring batch as the default. Keep explicit selection for meaningful price or stock differences.

## Verification and remaining checks

- Automated suite after fixes: **14 passed**, including regressions for shared stock, post-action refresh, draft restoration, hidden-item serving and batch-price display.
- Physical Android checks still needed: camera permission denial/recovery, QR scanning, keyboard/small-screen review sheet, Android process restoration, real network loss, and two-device concurrent ordering.
- Authorization needs separate verification: Supabase requests carry a publishable key rather than the custom waiter session (`lib/data/live_repository.dart:70`). Verify deployed RLS and mutation access in an authorized environment. Client ownership checks are not a server security boundary. This audit does not claim that unauthorized writes are currently possible.
- Remaining priorities: production RLS verification, atomic server-side inventory deduction, a real claim/transfer endpoint, and physical-device acceptance checks.
