# Baseline validation checklist

- [ ] Production project explicitly targeted; staging excluded during extraction
- [ ] Schema-only extraction; no rows, Auth users, Storage files, secrets, keys, or credential strings
- [ ] Managed schemas, extensions, application objects, constraints, indexes, functions, triggers, RLS, policies, jobs, URLs, grants, and ownership reviewed
- [ ] Candidate remains outside the migration directory
- [ ] PostgreSQL parser, statement inventory, security review, and human approval completed
- [ ] Staging-only execution authorized separately
- [ ] Migration 001 excluded; production mutation prohibited
