# IDOR Protection

IDOR stands for Insecure Direct Object Reference — it's when one account can access another account's data because a query doesn't properly filter by account.

If your SaaS has accounts (or organizations, workspaces, teams, ...) and uses a column like `tenant_id` to keep each account's data separate, IDOR protection ensures every SQL query filters on the correct tenant. Zen analyzes queries at runtime and raises an error if a query is missing that filter or uses the wrong tenant ID, catching mistakes like:

- A `SELECT` that forgets the tenant filter, letting one account read another's orders
- An `UPDATE` or `DELETE` without a tenant filter, letting one account modify another's data
- An `INSERT` that omits the tenant column, creating orphaned or misassigned rows

Zen catches these at runtime so they surface during development and testing, not in production. See [IDOR vulnerability explained](https://www.aikido.dev/blog/idor-vulnerability-explained) for more background.

> [!IMPORTANT]
> IDOR protection always raises an `Aikido::Zen::IDOR::Error` on violations regardless of block/detect mode. A missing filter is a developer bug, not an external attack.

## Setup

### 1. Enable IDOR protection at startup

```ruby
...

Aikido::Zen.config.idor_tenant_column_name = "tenant_id"
Aikido::Zen.config.idor_excluded_table_names = ["users"]
Aikido::Zen.enable_idor_protection

...
```

- `idor_tenant_column_name` — the column name that identifies the tenant in your database tables (e.g. `account_id`, `organization_id`, `team_id`).
- `idor_excluded_table_names` — tables that Zen should skip IDOR checks for, because rows aren't scoped to a single tenant (e.g. a shared `users` table that stores users across all tenants).

### 2. Set the tenant ID per request

Every request must have a tenant ID when IDOR protection is enabled. Call `Aikido::Zen.set_tenant_id` early in your request handler (e.g. in middleware after authentication):

```ruby
Aikido::Zen.set_tenant_id(1)
```

> [!IMPORTANT]
> If `Aikido::Zen.set_tenant_id` is not called for a request, Zen will raise an `Aikido::Zen::IDOR::Error` when a SQL query is executed.

### 3. Bypass for specific queries (optional)

Some queries don't need tenant filtering (e.g. aggregations across all tenants for an admin dashboard). Use `Aikido::Zen.without_idor_protection` to bypass the check for a specific block:

```ruby
...

# IDOR checks are skipped for queries inside this block
result = Aikido::Zen.without_idor_protection do
  db.execute("SELECT count(*) FROM agents WHERE status = 'running'");
end

...
```

## Troubleshooting

<details>
<summary>Missing tenant filter</summary>

```
Zen IDOR protection: query on table 'orders' is missing a filter on column 'tenant_id'
```

This means you have a query like `SELECT * FROM orders WHERE status = 'active'` that doesn't filter on `tenant_id`. The same check applies to `UPDATE` and `DELETE` queries.

</details>

<details>
<summary>Wrong tenant ID value</summary>

```
Zen IDOR protection: query on table 'orders' filters 'tenant_id' with value '456' but tenant ID is '123'
```

This means the query filters on `tenant_id`, but the value doesn't match the tenant ID set via `Aikido::Zen.set_tenant_id`.

</details>

<details>
<summary>Missing tenant column in INSERT</summary>

```
Zen IDOR protection: INSERT on table 'orders' is missing column 'tenant_id'
```

This means an `INSERT` statement doesn't include the tenant column. Every INSERT must include the tenant column with the correct tenant ID value.

</details>

<details>
<summary>Wrong tenant ID in INSERT</summary>

```
Zen IDOR protection: INSERT on table 'orders' sets 'tenant_id' to '456' but tenant ID is '123'
```

This means the INSERT includes the tenant column, but the value doesn't match the tenant ID set via `Aikido::Zen.set_tenant_id`.

</details>

<details>
<summary>Missing Aikido::Zen.set_tenant_id call</summary>

```
Zen IDOR protection: Aikido::Zen.set_tenant_id was not called for this request. Every request must have a tenant ID when IDOR protection is enabled.
```

</details>

## Supported databases

- SQLite (via `sqlite3` Gem)
- PostgreSQL (via `pg` Gem)
- MySQL (via `mysql2` and `trilogy` Gems)

Any ORM or query builder that uses these database packages under the hood is supported (e.g. ActiveRecord). ORMs that use their own database engine are not supported unless configured to use a supported driver adapter.

## Limitations

## Statements that are always allowed

Zen only checks statements that read or modify row data (`SELECT`, `INSERT`, `UPDATE`, `DELETE`). The following statement types are also recognized and never trigger an IDOR error:

- DDL — `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`, ...
- Session commands — `SET`, `SHOW`, ...
- Transactions — `BEGIN`, `COMMIT`, `ROLLBACK`, ...
