# LiveFilter Demo

Interactive filter explorer demonstrating all LiveFilter filter types with a Phoenix LiveView interface.

## Prerequisites

- Elixir 1.15+
- PostgreSQL
- Node.js (for asset compilation)

## Setup

```bash
mix setup
```

This runs:
- `mix deps.get` — fetch dependencies
- `mix ecto.setup` — create database, run migrations, seed data
- `mix assets.setup` — install Tailwind and esbuild
- `mix assets.build` — compile assets

## Running

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000)

## Development

Reset database with fresh seed data:

```bash
mix ecto.reset
```

Run tests:

```bash
mix test
```
