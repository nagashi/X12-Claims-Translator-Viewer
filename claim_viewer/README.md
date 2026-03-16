# Claim Viewer

A healthcare claims system that validates, translates, stores, and displays X12 837 EDI claim data through a Phoenix web application.

## Overview

Claim Viewer accepts any file containing valid X12 837 content — regardless of file extension — validates its envelope structure, translates each transaction set to structured JSON via a Python parser, enforces type safety through Elixir structs, validates the output against a HIPAA-compliant JSON Schema using a Rust-backed validator, and persists each claim to PostgreSQL for searching, viewing, and exporting.

A single X12 interchange can contain multiple transaction sets (claims). Each is individually validated and persisted.

## Architecture

### C4 Context Diagram

```mermaid
flowchart TB
    user(["<b>Claims Analyst</b><br/>Uploads X12 files,<br/>searches and views claims"])

    subgraph boundary [" "]
        direction TB
        claimviewer["<b>Claim Viewer</b><br/><i>Phoenix Web App</i><br/>Validates, translates, stores,<br/>and displays 837 claims"]
    end

    postgres[("<b>PostgreSQL</b><br/>Stores structured claim data<br/>and searchable fields")]
    python["<b>Python pyx12</b><br/><i>External Subprocess</i><br/>Parses raw X12 segments<br/>into JSON"]
    rust["<b>ExJsonschema</b><br/><i>Rust NIF</i><br/>High-performance JSON Schema<br/>validator via jsonschema crate"]

    user -->|"Uploads X12 files,<br/>searches, views, exports"| claimviewer
    claimviewer -->|"Reads/writes<br/>claim records"| postgres
    claimviewer -->|"Invokes parser_for_viewer.py<br/>via System.cmd"| python
    claimviewer -->|"Validates JSON output<br/>against 837 5010 schema"| rust

    style user fill:#08427b,color:#fff,stroke:#08427b
    style claimviewer fill:#1168bd,color:#fff,stroke:#0b4884
    style postgres fill:#438dd5,color:#fff,stroke:#2e6295
    style python fill:#999,color:#fff,stroke:#6b6b6b
    style rust fill:#999,color:#fff,stroke:#6b6b6b
```

### C4 Container Diagram

```mermaid
flowchart TB
    user(["<b>Claims Analyst</b>"])

    subgraph phoenix ["Phoenix Application"]
        direction TB
        router["<b>Router</b><br/>Routes HTTP requests<br/>to controller actions"]
        controller["<b>PageController</b><br/>Upload, search, view,<br/>export actions"]
        validator["<b>X12Validator</b><br/>Content-based ISA/GS/ST<br/>envelope validation"]
        translator["<b>X12Translator</b><br/>Calls pyx12 parser<br/>subprocess"]
        structs["<b>X12 Structs</b><br/>Type-safe structs for<br/>all 837 sections"]
        mapper["<b>X12.Mapper</b><br/>Maps raw JSON to typed<br/>structs and back"]
        schema_val["<b>SchemaValidator</b><br/>Validates JSON against<br/>837 5010 schema"]
        claims["<b>Claims Context</b><br/>Extracts searchable fields,<br/>manages Ecto records"]
        templates["<b>HEEx Templates</b><br/>Dashboard, search,<br/>claim detail, exports"]
    end

    db[("<b>PostgreSQL</b><br/>claims table with raw_json<br/>and indexed search fields")]

    user --> router
    router --> controller
    controller --> validator
    controller --> translator
    controller --> mapper
    mapper --> structs
    controller --> schema_val
    controller --> claims
    controller --> templates
    claims --> db

    style user fill:#08427b,color:#fff,stroke:#08427b
    style phoenix fill:#e8e8e8,color:#000,stroke:#999
    style router fill:#438dd5,color:#fff,stroke:#2e6295
    style controller fill:#438dd5,color:#fff,stroke:#2e6295
    style validator fill:#438dd5,color:#fff,stroke:#2e6295
    style translator fill:#438dd5,color:#fff,stroke:#2e6295
    style structs fill:#438dd5,color:#fff,stroke:#2e6295
    style mapper fill:#438dd5,color:#fff,stroke:#2e6295
    style schema_val fill:#438dd5,color:#fff,stroke:#2e6295
    style claims fill:#438dd5,color:#fff,stroke:#2e6295
    style templates fill:#438dd5,color:#fff,stroke:#2e6295
    style db fill:#438dd5,color:#fff,stroke:#2e6295
```

### Upload and Validation Flow

```mermaid
flowchart TD
    A[User selects file] --> B[POST /upload]
    B --> C{X12Validator:<br/>Read file content}
    C -->|Missing ISA header| ERR1[Flash error, redirect /]
    C -->|ISA/IEA mismatch| ERR1
    C -->|GS/GE mismatch| ERR1
    C -->|ST not 837| ERR1
    C -->|Valid X12 837<br/>N transaction sets| D[X12Translator:<br/>Python pyx12 parser]
    D -->|Parse error| ERR2[Flash error, redirect /]
    D -->|JSON sections| E{Multiple<br/>transaction sets?}
    E -->|Single| F1[Process set 1]
    E -->|Multiple| F2[Process each set]

    F1 --> G[X12.Mapper.from_sections<br/>Type-safe Claim837 struct]
    F2 --> G
    G --> H[X12.Mapper.to_validated_sections<br/>Cleaned section maps]
    H --> I[SchemaValidator.validate_837_json<br/>Rust NIF validates against<br/>837 5010 JSON Schema]
    I -->|Valid| J[Extract search fields<br/>and save to PostgreSQL]
    I -->|Invalid| K[Collect error for this set]
    J --> L[Flash: N of M claims saved]
    K --> L
    L --> M[Redirect to dashboard]
```

### Search and Display Flow

```mermaid
flowchart TD
    A[User visits /search] --> B[Enter search criteria]
    B --> C[GET /search with params]
    C --> D{Any field has 2+ chars<br/>or date/status set?}
    D -->|No| E[Show empty state message]
    D -->|Yes| F[Build Ecto query<br/>ILIKE filters, date range, status]
    F --> G[Execute query with pagination]
    G --> H[Render results table<br/>Patient, Payer, Claim number]
    H --> I[Click patient name]
    I --> J[GET /claims/:id]
    J --> K[Render full claim view:<br/>type badge, summary card,<br/>all sections, service lines]
    K --> L{Export?}
    L -->|PDF| M[Generate HTML then wkhtmltopdf]
    L -->|CSV| N[Generate text report]
```

### Internal Module Map

```mermaid
flowchart LR
    subgraph Web["ClaimViewerWeb"]
        Router --> PageController
        PageController --> PageHTML
        PageHTML --> Templates["HEEx Templates<br/>dashboard, home, claim"]
    end

    subgraph Core["ClaimViewer"]
        X12Validator
        X12Translator
        Claims["Claims Context"]
        ClaimSchema["Claims.Claim<br/>Ecto Schema"]
        PDF["PDF Generator"]
    end

    subgraph X12["ClaimViewer.X12"]
        Mapper
        SchemaValidator
        Claim837["Claim837 Struct"]
        Structs["Section Structs<br/>Transaction, Subscriber,<br/>Payer, ClaimInfo, etc."]
    end

    PageController --> X12Validator
    PageController --> X12Translator
    PageController --> Mapper
    PageController --> SchemaValidator
    PageController --> Claims
    PageController --> PDF
    Mapper --> Claim837
    Mapper --> Structs
    Claims --> ClaimSchema
    SchemaValidator -->|Rust NIF| ExJsonschema["ExJsonschema<br/>Rust jsonschema crate"]
    X12Translator -->|subprocess| Python["Python pyx12"]
```

## Getting Started

### Prerequisites

- **Elixir** ~> 1.15 and **Erlang/OTP** (compatible version)
- **PostgreSQL** running on localhost:5432 (or configure via environment variables)
- **Python 3** with the `pyx12` library installed (`pip3 install pyx12`)
- **Rust toolchain** (for compiling the `ex_jsonschema` NIF, or precompiled binaries will be used automatically)
- **wkhtmltopdf** (optional, for PDF export)

### Setup

```bash
# Install dependencies, create DB, run migrations, build assets
mix setup

# Start the server
mix phx.server

# Or start inside IEx
iex -S mix phx.server
```

Visit [localhost:4000](http://localhost:4000) in your browser.

### Environment Variables (optional)

| Variable | Default | Purpose |
|---|---|---|
| `PGUSER` | `postgres` | Database username |
| `PGPASSWORD` | `postgres` | Database password |
| `PGHOST` | `localhost` | Database host |
| `PGPORT` | `5432` | Database port |
| `PGDATABASE` | `claim_viewer_dev` | Database name |
| `PORT` | `4000` | HTTP server port |

### Running Tests

```bash
mix test
```

### Pre-commit Check

Runs compile (warnings-as-errors), unused deps check, formatting, and tests:

```bash
mix precommit
```

## Upload Pipeline (Detail)

1. **File extension is ignored.** Any file is accepted for upload regardless of its name or extension.
2. **Content validation** (`X12Validator`): The raw file bytes are inspected for:
   - ISA interchange header (fixed 106-character format)
   - Segment terminator auto-detection from ISA position 105
   - IEA interchange trailer
   - GS/GE functional group envelope(s)
   - Every ST segment must be `ST*837` (non-837 types are rejected)
   - ST/SE pairs must be balanced
3. **Translation** (`X12Translator`): The Python `pyx12` library parses the raw X12 segments into a structured JSON array of section objects.
4. **Struct mapping** (`X12.Mapper`): Raw JSON maps are converted into type-safe Elixir structs (`Claim837`, containing `Transaction`, `Subscriber`, `Payer`, `ClaimInfo`, `ServiceLine`, etc.). Guard clauses in each struct's `from_map/1` enforce data types.
5. **Round-trip** (`X12.Mapper.to_validated_sections/1`): Structs are converted back to the section-map format, ensuring all values have been normalized.
6. **Schema validation** (`X12.SchemaValidator`): The JSON is validated against a HIPAA-compliant 837 5010 JSON Schema (`priv/schemas/837_5010_schema.json`) using the Rust-backed `ExJsonschema` library. The schema is compiled once via `:persistent_term` for near-instant runtime validation.
7. **Persistence**: Searchable fields (patient name, payer, NPI, etc.) are extracted and stored alongside the full `raw_json` in PostgreSQL.

If the interchange contains multiple transaction sets, each is processed independently. The flash message reports how many succeeded vs. failed.

## Route Map

| Method | Path | Action | Purpose |
|---|---|---|---|
| `GET` | `/` | `dashboard` | Dashboard with aggregate statistics |
| `GET` | `/search` | `home` | Search form + paginated results |
| `GET` | `/claims/:id` | `show` | Full claim detail view |
| `GET` | `/claims/:id/export` | `export_pdf` | Download claim as PDF |
| `GET` | `/claims/:id/export/csv` | `export_csv` | Download claim as text report |
| `POST` | `/upload` | `upload` | Upload and process X12 file |

## Technology Stack

- **Web framework:** Phoenix 1.8+
- **Language:** Elixir 1.15+ on Erlang/OTP
- **Database:** PostgreSQL via Ecto
- **X12 parsing:** Python `pyx12` library (called as subprocess)
- **JSON Schema validation:** `ex_jsonschema` (Rust NIF via `jsonschema` crate)
- **PDF generation:** `pdf_generator` wrapping `wkhtmltopdf` (optional)
- **Frontend:** Server-rendered HEEx templates with dark theme
