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
| *pending — JP (T-19)* | | | | | | | | |
