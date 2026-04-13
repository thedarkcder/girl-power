# Lessons

- Authorization boundaries must be proven on the server for durable state writes. An authenticated caller asserting `is_pro` or an equivalent entitlement flag is never sufficient without a server-verifiable purchase artifact.
- GP-186/TestFlight closure cannot be asserted from local checks alone; acceptance requires an authoritative successful PR-triggered `PR TestFlight` run ID and log markers attached under `docs/test-artifacts/GP-186/`.
