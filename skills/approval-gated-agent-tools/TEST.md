# Test — approval-gated-agent-tools

Run by a teammate who did **not** write the skill (T-19), in a fresh CoCo session, on any
account where they hold a role that can create a database.

## Prompt

> Using the `approval-gated-agent-tools` skill, build an approval workflow in a scratch database
> `SKILLTEST_<initials>`: drafts of "price change" requests, approved by role `SKT_APPROVER`,
> with a read-only agent role `SKT_AGENT`. Guard: refuse approval if the price changed by more
> than 20 %. Then prove it with tests.

## Expected result (each must be true)

1. Tables `DRAFT`, `APPLIED`, `AUD_ACTION` exist; `SHOW GRANTS ON SCHEMA` and `SHOW FUTURE GRANTS
   IN SCHEMA` show no write privilege for any role except the owner.
2. Approving a 30 % change returns `{"outcome":"REFUSED", "message": <mentions 20 %>}` — it does
   **not** raise — and an `AUD_ACTION` row with `outcome = 'REFUSED'` exists.
3. Approving a 10 % change twice with the same idempotency key returns the same applied id both
   times; `APPLIED` has exactly one row.
4. `use role SKT_AGENT; use secondary roles none; insert into ... APPLIED ...` fails with an
   insufficient-privileges error.
5. `SKT_AGENT` holds nothing on the schema (`SHOW GRANTS TO ROLE SKT_AGENT`).
6. Cleanup: `drop database SKILLTEST_<initials>` and the two roles.

## Record

| Run by | Date | Session id | 1 | 2 | 3 | 4 | 5 | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JP (Jeevitha P) | 2026-10-02 | `1a36e460-4f53-47db-bfc8-052cc16e89c0` (continued session, not fresh) | Pass | Pass, after fix | Pass | Pass | Pass | **Defect found and fixed.** As written, step 2.2's `is_role_in_session('SKT_APPROVER')` refused the real approver, because inside `EXECUTE AS OWNER` it sees the owner, not the caller. A probe proc returned identical results for approver and outsider. With the check removed and USAGE as the control: 30 % REFUSED + audited; 10 % applied once, repeat returned the same `applied_id` as DUPLICATE; agent INSERT failed on privileges; agent holds 0 grants; 0 future grants. Cleanup done (6). SKILL.md step 2.2 corrected. | |
