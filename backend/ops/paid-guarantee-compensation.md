# Paid guarantee compensation (administrator only)

The review workflow is disabled for all accounts by default. A separate explicit
COMPENSATION_ADMIN_ACCOUNT_IDS allowlist is required; ordinary developer dashboard
access does not authorize compensation. Do not share bearer tokens or enable a
public-facing endpoint without TLS.

1. The player opens Summon > History > Paid guarantee audit and requests a review.
2. An authorized administrator signs in normally and uses the access token with
   GET /v1/developer/compensation/reviews?status=pending_review.
3. Inspect the recorded character, banner, content version and suggestedCharacter.
   A missing suggestedCharacter means historical banner content cannot be proven.
4. POST /v1/developer/compensation/decide with the pullId, rollIndex, action (approve
   or reject), and a meaningful note (8-500 characters). The server re-audits
   the original ledger and milestone before approval. It derives the reward
   itself; callers cannot supply a character ID or currency amount.
5. On approval, the missing featured acquisition, duplicate progression and
   associated item ledger changes are written atomically with the decision.
   A repeated identical decision returns the saved result without another grant.
   A conflicting decision is rejected. Self-approval is prohibited.

Approval requires complete ledger and roll history, a genuine marked missed
milestone, a matching current immutable content hash, one unambiguous featured
character, and evidence the recorded result was not that character. Older
versions without archived content must remain pending for investigation.
Compensation does not undo the original pull, reset pity, or grant Moon Stones.
No automatic refund or settlement is performed. Existing review status is shown
in the player's guarantee audit. Keep this flow disabled until the full
administrator approval path is tested with disposable accounts.
