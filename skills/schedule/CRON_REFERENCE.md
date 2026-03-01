# Cron Expression Reference

5-field format: `minute hour day-of-month month day-of-week`

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, 0=Sunday)
│ │ │ │ │
* * * * *
```

## Common Patterns

| Natural Language | Cron | Human Label |
|---|---|---|
| Every minute | `* * * * *` | Every minute |
| Every 5 minutes | `*/5 * * * *` | Every 5 minutes |
| Every 15 minutes | `*/15 * * * *` | Every 15 minutes |
| Every hour | `0 * * * *` | Every hour |
| Every 2 hours | `0 */2 * * *` | Every 2 hours |
| Daily at 9am | `0 9 * * *` | Daily at 9:00 AM |
| Daily at 6pm | `0 18 * * *` | Daily at 6:00 PM |
| Daily at midnight | `0 0 * * *` | Daily at midnight |
| Weekdays at 9am | `0 9 * * 1-5` | Every weekday at 9:00 AM |
| Weekends at 10am | `0 10 * * 0,6` | Every weekend at 10:00 AM |
| Monday at 9am | `0 9 * * 1` | Every Monday at 9:00 AM |
| Mon/Wed/Fri at 9am | `0 9 * * 1,3,5` | Mon, Wed, Fri at 9:00 AM |
| First of month at 9am | `0 9 1 * *` | 1st of every month at 9:00 AM |
| Every Sunday at 8pm | `0 20 * * 0` | Every Sunday at 8:00 PM |

## Syntax

- `*` — every value
- `*/N` — every N units (e.g., `*/15` = every 15)
- `N` — specific value
- `N,M` — list of values
- `N-M` — range of values
- `N-M/S` — range with step

## Day of Week Numbers

| Day | Number |
|-----|--------|
| Sunday | 0 |
| Monday | 1 |
| Tuesday | 2 |
| Wednesday | 3 |
| Thursday | 4 |
| Friday | 5 |
| Saturday | 6 |
