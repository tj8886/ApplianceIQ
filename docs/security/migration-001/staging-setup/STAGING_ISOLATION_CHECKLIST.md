# Staging isolation checklist

- [x] Staging project active
- [x] Staging reference and host verified
- [x] Production reference and host excluded from the read-only connection
- [x] No credential printed or committed
- [x] Local environment-file patterns are ignored by Git
- [x] No production data, users, or secrets copied
- [x] No migration, schema mutation, data mutation, or deployment occurred
- [x] Migration inventory completed
- [x] Synthetic-data policy documented
- [ ] Approved baseline strategy for incomplete migration history
- [ ] Controlled staging bootstrap authorization
