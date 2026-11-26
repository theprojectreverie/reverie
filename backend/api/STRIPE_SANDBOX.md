# Reverie Stripe sandbox (PC only)

Checkout is disabled by default. The route rejects production, non-local databases, non-loopback hosts, and live keys. Sandbox currency is a test-only development wallet, not a production entitlement. Do not deploy the development database or enable real payments.

## Setup on the development PC
1. Create or sign into Stripe: https://dashboard.stripe.com/register . Select an isolated sandbox and obtain its test API key at https://dashboard.stripe.com/apikeys . Never paste secrets into chat or commit them.
2. Install the Stripe CLI using https://docs.stripe.com/cli/install and sign in with `stripe login` to the same sandbox.
3. In a dedicated terminal run `stripe listen --events checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.expired,charge.refunded,charge.dispute.created --forward-to http://127.0.0.1:8787/v1/shop/webhook`. Keep it open during tests.
4. In another terminal in `backend/api`, run `powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\configure-stripe-sandbox.ps1` and privately enter the sandbox API key and the CLI signing secret. Do not run the setup interactively in a chat tool. Restart the local API. The shop requires migrations 030 and 032; both have been applied to the local development database.
5. In Reverie sign in, open Summon > Moonstone Shop (test mode). Choose a test package. Use Stripe test card 4242 4242 4242 4242, any future expiry and any 3-digit CVC. Never use a real card. Return to the game and refresh payment status. Only the verified online wallet is credited; the offline story wallet is separate.

Provisional test packages: 120 / EUR 1.20, 600 / EUR 6.00, 1200 / EUR 12.00. These are not approved live prices. At existing summon costs, one paid pull costs EUR 1.20 equivalent and the 100-pull milestone costs EUR 120 equivalent; final odds/price disclosures and legal review are required before production.

## Tests
`node --env-file=.env --import tsx scripts/stripe-sandbox-e2e.mjs` exercises a simulated provider with real signature verification and disposable database accounts. `stripe-shop-godot-e2e.mjs` checks actual Godot UI against a disabled sandbox server. Neither submits a real Stripe payment. A genuine Stripe-hosted sandbox checkout remains to be tested after private configuration.

## Production blockers
Live payments are intentionally blocked. Before release: obtain merchant/provider approval for the monetization model, confirm jurisdictional/consumer and tax obligations, approved pricing and probability disclosures, parental/age and spending controls as applicable, production HTTPS hosting, native platform billing where required, receipts, operational dispute handling and refund reconciliation (spent/partial refunds need manual review), and a clean production database. No conversion of sandbox orders or stones into live purchases.

The three sandbox products and their one-time EUR prices are created in Project Reverie sandbox. The server references those verified Price IDs, not client-provided prices. Use the same sandbox when configuring local credentials.

## Local setup status
Stripe CLI 1.55.15 was installed via WinGet; Windows Application Control currently blocks its execution. Do not bypass or disable the policy. Ask the device administrator to approve the official CLI through the normal application-control process. The private configuration script now validates the supplied test key against the three exact sandbox prices before saving anything; a key for the wrong sandbox is rejected. The Stripe ChatGPT connection does not expose a reusable backend API key.

## Optional manual sandbox verification (no CLI required)
If the official CLI is blocked, the setup script accepts an empty webhook secret and explicitly enables STRIPE_TEST_MANUAL_RECONCILE. This is restricted to development, a loopback API host, a local database and test API keys. No unsigned webhook is accepted. The game checks payment directly against Stripe on Refresh payment status; the server verifies the authenticated order, amount, currency, payment status and account before crediting once. The most recent pending order (or latest credited/refund-review order) is checked on refresh; refunds of older orders need separate reconciliation. This is not a production substitute for webhook delivery.

## Checkout cancellation and recovery
Only one new pending order is permitted per account. Resume retries the original request; Cancel pending checkout asks Stripe to expire an open unpaid session and then records the verified outcome. Completed purchases are credited, never silently cancelled. If the session cannot be recovered or verified, the order remains pending and checkout stays locked. Expired/cancelled sessions share the expired status.

## Refund and dispute review (migration 047_stripe_refund_review_details.sql)
Stripe cumulative refunded cents are retained without decreasing on replay. Partial refunds and disputes require manual review. A full refund can reverse an original credit once only if the purchase ledger entry exists, the wallet has enough stones and no subsequent paid-currency debit makes attribution ambiguous. Once flagged, a credited order stays in review: new top-ups never trigger automatic clawback. A fully refunded order that was never credited can close without wallet changes. Existing older reviews remain conservatively sticky. No automated character removal, account ban or negative wallet is introduced. The shop displays the recorded reason and amount. Real webhook delivery and operator review decisions remain production prerequisites; manual mode checks the latest eligible order, not every historical refund.

## Read-only payment support queue
Local URL: http://127.0.0.1:8787/v1/developer/payments/dashboard. Explicitly configure PAYMENT_REVIEW_ADMIN_ACCOUNT_IDS in the private local API environment with approved account UUIDs. Empty allowlist denies all data access; no general developer role automatically receives payment support access. The dashboard reports review reason, refund amount, dispute flag, current wallet and linked ledger counts. It does not approve refunds or mutate player records. Do not expose it publicly.

## Test purchase records
Select a verified order in Purchase history and click Save test receipt to save a text record. The authenticated server verifies account ownership and the original currency ledger entry. Refund status is a snapshot; refresh and export again for current records. No card data, Stripe session IDs or secrets are included. These records are sandbox-only and are not commercial or tax invoices. Older orders beyond the latest 30 remain accessible through the authenticated receipt endpoint by order ID.

## Audited review decisions (migration 048)
Authorized local reviewers can record Reviewed - no adjustment or Escalate, with a required reason. Decisions are append-only and bind to the exact refund evidence; a change in refund amount, dispute flag or status invalidates the current decision without deleting audit history. Self-review is forbidden. Repeating a request returns the same decision. No action changes order status, balances, characters, or Stripe funds. A reviewed order remains in refund_review; actual monetary resolution requires a separately authorized procedure.

## Optional spending controls (migration 049)
The shop requires explicit confirmation before opening Stripe. Self-managed daily and monthly limits are persisted server-side; blank is unlimited, zero prevents new orders. UTC calendar periods count gross commitments; outstanding orders reserve budget across boundaries, cancelled/expired orders release reservations, and refunded amounts do not restore the spending budget. Existing orders can still be completed or cancelled. Limits are not parental controls and can be changed by their account owner. No default limit has been imposed. Sandbox only.
