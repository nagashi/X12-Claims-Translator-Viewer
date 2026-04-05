# Database Configuration Change — Test Environment

**Project:** ClaimViewer (Phoenix) **Date:** April 5, 2026 **File Changed:** `config/test.exs`

## Problem

The application's dev configuration (`config/dev.exs`) reads PostgreSQL connection details from environment variables (`PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT`, `PGDATABASE`), allowing it to programmatically point to the correct database.

The test configuration (`config/test.exs`) had all connection values hardcoded, meaning tests — including property tests that hit the database — would not connect to the same database as the running application.

## Change Summary

Updated `config/test.exs` to read the same `PG*` environment variables as `config/dev.exs`, with identical fallback defaults.

### Before

```elixir
config :claim_viewer, ClaimViewer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    "claim_viewer_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

### After

```elixir
config :claim_viewer, ClaimViewer.Repo,
  username: System.get_env("PGUSER") || "postgres",
  password: System.get_env("PGPASSWORD") || "postgres",
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  database: System.get_env("PGDATABASE") ||
        "claim_viewer_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

## Note

Because the fallback defaults are identical to the previously hardcoded values, users who clone the repo with a standard local PostgreSQL setup will get the exact same behavior without setting any environment variables. Users who customize their environment via `PG*` variables will have tests automatically run against the same database their application is configured to use, ensuring consistency between dev and test environments.

## Verification

All property tests passed after the change:

- **69 properties, 15 tests, 0 failures**
- Completed in 22.5 seconds
