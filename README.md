# Claim Viewer

A healthcare claims system that validates, translates, stores, and displays X12 837 EDI claim data through a Phoenix web application.

## Project Context

This application is part of the **X12 837 Translator and Claims Viewer Program**. The complete system translates EDI-formatted healthcare claims into JSON and provides a user-friendly web interface for viewing and searching claim data.

**Project Components:**
- **X12 to JSON Translation** — Python tool using the PyX12 library (separate component)
- **Claim Viewer** — This Phoenix/Elixir application for storing, searching, and displaying JSON claims with a structured user interface

## Features

✅ **X12 File Upload** — Upload any file; content is validated as X12 837 and automatically translated to JSON  
✅ **Content-Based Validation** — File extensions are irrelevant; ISA/IEA, GS/GE, and ST\*837/SE envelope structure is verified from raw file bytes  
✅ **Multi-Transaction-Set Support** — A single interchange containing multiple claims is split and each is validated independently  
✅ **Type-Safe Structs** — All 837 sections are mapped to enforced Elixir structs for data integrity  
✅ **JSON Schema Validation** — Rust-backed validator enforces HIPAA-compliant 837 5010 schema  
✅ **Persistent Storage** — PostgreSQL database storing both raw JSON and extracted searchable fields  
✅ **Advanced Multi-Criteria Search** — Search by member name, payer, providers, claim number, and service date range
✅ **Structured Display** — Clean, organized view of all claim sections in form-like layout (not raw JSON)  
✅ **Service Lines Table** — Dedicated table view for line-item charges with procedure codes, dates, and amounts  
✅ **Search Results Table** — Interactive results grid showing member, payer, and claim information
✅ **Modern Dark Theme UI** — Professional interface with cyan/green color scheme  
✅ **Case-Insensitive Search** — ILIKE queries for flexible text matching  
✅ **Date Range Filtering** — Filter claims by service date period  
✅ **Automatic Field Extraction** — Searchable fields automatically extracted from uploaded JSON

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

### Validation Pipeline

The upload pipeline enforces data integrity through three sequential validation layers. Each layer targets a different class of errors, ensuring the JSON output faithfully represents the original X12 837 data. A claim must pass all three layers before it is persisted.

```mermaid
flowchart TD
    FILE[/"X12 File Upload"/] --> L1

    subgraph L1 ["Layer 1: Envelope Validation — X12Validator"]
        direction TB
        L1A["ISA header check<br/>(fixed 106-char format)"]
        L1B["Segment terminator<br/>detection (position 105)"]
        L1C["IEA trailer verification"]
        L1D["GS↔GE functional group<br/>envelope matching"]
        L1E["ST↔SE transaction set<br/>envelope matching"]
        L1F["ST*837 transaction<br/>type enforcement"]
        L1A --> L1B --> L1C --> L1D --> L1E --> L1F
    end

    L1 -->|"Valid: N transaction sets"| PARSE["X12Translator<br/>Python pyx12 → JSON"]
    L1 -->|"Invalid"| REJECT1["❌ Rejected with<br/>specific envelope error"]

    PARSE --> L2

    subgraph L2 ["Layer 2: Type-Safe Struct Mapping — X12.Mapper"]
        direction TB
        L2A["from_sections/1<br/>JSON → Claim837 struct"]
        L2B["Guard clauses enforce types<br/>in each struct's from_map/1"]
        L2C["to_validated_sections/1<br/>Claim837 → normalized section maps"]
        L2A --> L2B --> L2C
    end

    L2 -->|"Type-validated sections"| L3
    L2 -->|"Type mismatch"| REJECT2["❌ Struct mapping error"]

    subgraph L3 ["Layer 3: Schema Validation — SchemaValidator"]
        direction TB
        L3A["Encode sections to JSON string"]
        L3B["ExJsonschema Rust NIF<br/>validates against<br/>837_5010_schema.json"]
        L3C["Enforces: required fields,<br/>value types, section names,<br/>nested structures"]
        L3A --> L3B --> L3C
    end

    L3 -->|"Schema-compliant"| SAVE["✅ Extract search fields<br/>and persist to PostgreSQL"]
    L3 -->|"Schema violation"| REJECT3["❌ Schema validation errors"]

    style L1 fill:#1e3a5f,color:#fff,stroke:#2e6295
    style L2 fill:#1e3a5f,color:#fff,stroke:#2e6295
    style L3 fill:#1e3a5f,color:#fff,stroke:#2e6295
    style FILE fill:#08427b,color:#fff,stroke:#08427b
    style PARSE fill:#438dd5,color:#fff,stroke:#2e6295
    style SAVE fill:#166534,color:#fff,stroke:#15803d
    style REJECT1 fill:#991b1b,color:#fff,stroke:#b91c1c
    style REJECT2 fill:#991b1b,color:#fff,stroke:#b91c1c
    style REJECT3 fill:#991b1b,color:#fff,stroke:#b91c1c
```

**Layer 1 — Envelope Validation** (`lib/claim_viewer/x12_validator.ex`)
Operates on raw file bytes before any parsing. Validates the X12 interchange envelope structure: ISA/IEA, GS/GE, and ST/SE pairs must be present and balanced. Every ST segment must declare transaction type `837`. Rejects non-X12 content and non-837 transaction types immediately.

**Layer 2 — Type-Safe Struct Mapping** (`lib/claim_viewer/x12/mapper.ex`)
After the Python parser produces JSON sections, each section is converted into a typed Elixir struct (`Claim837` containing `Transaction`, `Subscriber`, `Payer`, `ClaimInfo`, `ServiceLine`, etc.) via `from_sections/1`. Guard clauses in each struct's `from_map/1` enforce data types. The structs are then converted back to section maps via `to_validated_sections/1`, completing a round-trip that normalizes all values.

**Layer 3 — JSON Schema Validation** (`lib/claim_viewer/x12/schema_validator.ex`)
The normalized sections are validated against a HIPAA-compliant 837 5010 JSON Schema (`priv/schemas/837_5010_schema.json`) using the Rust-backed `ExJsonschema` library. The schema enforces required sections (e.g., `claim` must exist), required fields per section (e.g., `id` and `totalCharge` on claims), correct value types, allowed section names via enum constraint, and nested structures like addresses. The compiled schema is cached in `:persistent_term` for near-instant runtime validation.

All three layers are orchestrated by `process_single_transaction_set/2` in `PageController`. If any layer fails, that transaction set is rejected with a descriptive error while other sets in the same interchange can still succeed.

### Search and Display Flow

```mermaid
flowchart TD
    A[User visits /search] --> B[Enter search criteria]
    B --> C[GET /search with params]
    C --> D{Any field has 2+ chars<br/>or date/status set?}
    D -->|No| E[Show empty state message]
    D -->|Yes| F[Build Ecto query<br/>ILIKE filters, date range, status]
    F --> G[Execute query with pagination]
    G --> H[Render results table<br/>Member, Payer, Claim number]
    H --> I[Click member name]
    I --> J[GET /claims/:id]
    J --> K[Render full claim view:<br/>type badge, summary card,<br/>all sections, service lines]
    K --> L{Export?}
    L -->|PDF| M[Generate HTML then ChromicPDF]
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
        PDF["PDF Generator<br/>(ChromicPDF)"]
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

## Requirements

- Elixir 1.19+
- Erlang/OTP 28+
- Phoenix Framework 1.8+
- PostgreSQL 17+
- Ecto
- Jason
- Python 3 with pyx12 library
- Rust toolchain (see [Rust-Backed JSON Schema Validation](#rust-backed-json-schema-validation) below for details)
- Google Chrome or Chromium (for PDF export via ChromicPDF)

## Getting Started

```bash
# Clone the repository
git clone <your-repository-url>
cd claim_viewer

# Install Python dependencies (required for X12 file processing)
python3 -m pip install pyx12

# macOS note:
# If python3/pip is missing, install Python 3 (e.g., `brew install python` or from python.org),
# then run the command above again.

# Install dependencies
mix deps.get

# Change UName to your user name
export PGUSER=UName

# Change PWD to your password
export PGPASSWORD=PWD

# Set the port to 5432
export PGPORT=5432

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Start Phoenix server
mix phx.server

# Or use the setup alias (installs deps, creates DB, runs migrations, builds assets)
mix setup

# Start inside IEx (interactive Elixir shell)
iex -S mix phx.server
```

Visit **http://localhost:4000** in your browser.

## Usage

### Uploading Claims

The application accepts **any file** as long as its content is a valid X12 837 interchange. **File extensions are irrelevant** — the system reads the raw file bytes and validates the X12 envelope structure (ISA/IEA, GS/GE, ST\*837/SE) before processing.

Click "Upload X12 Claim File" and select your file. The upload pipeline then:

1. **Validates** the file content is a well-formed X12 837 interchange
2. **Translates** the X12 segments to structured JSON via the Python pyx12 parser
3. **Maps** the JSON into type-safe Elixir structs for data integrity
4. **Validates** the resulting JSON against a HIPAA-compliant 837 5010 JSON Schema (Rust-backed)
5. **Persists** each valid claim to PostgreSQL with extracted searchable fields

If the interchange contains multiple transaction sets, each is processed and validated independently. The flash message reports how many succeeded vs. failed (e.g., "3 of 4 claims saved").

> **Note:** JSON is used internally as an intermediate format for storage and processing. Users should upload X12 files, not JSON files.

### Searching Claims

The search form supports multiple criteria that can be used individually or combined:

- **Member first name** — Partial match, case-insensitive
- **Member last name** — Partial match, case-insensitive
- **Payer name** — Insurance company name search
- **Billing provider** — Provider organization name
- **Rendering provider NPI** — Individual provider NPI number
- **Claim #** — Clearinghouse claim number
- **Service date range** — Filter by date range (from date and to date)

Click **Search** to view matching results or **Clear** to reset all fields.

### Viewing Claim Details

Search results are displayed in a table with member name, payer, and claim number. Click any member name to view the full claim, which displays data in a structured layout with sections:

- **Transaction** — Control number, date, purpose, reference ID, time, type, version
- **Submitter** — Contact information, ID, name
- **Receiver** — ID and name
- **Billing Provider** — Address, name, tax ID
- **Pay-To Provider** — Address, name, tax ID
- **Subscriber** — Member address, DOB, name, group number, ID, plan type, relationship, sex
- **Payer** — Payer name and payer ID
- **Claim** — Clearinghouse claim number, ID, indicators, onset date, place of service, service type, total charge
- **Diagnosis** — Primary and secondary diagnosis codes
- **Rendering Provider** — First name, last name, NPI
- **Service Facility** — Address, name, tax ID
- **Service Lines** — Table with charge, code qualifier, diagnosis pointer, emergency indicator, line number, procedure code, service date, unit qualifier, and units

### Exporting Claims

- **PDF** — Full claim report generated via ChromicPDF (Chrome headless)
- **CSV** — Human-readable text report with all sections

## Routes

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| `GET` | `/` | `dashboard` | Dashboard with aggregate statistics |
| `GET` | `/search` | `home` | Search form and paginated results |
| `GET` | `/claims/:id` | `show` | Full claim detail view |
| `GET` | `/claims/:id/export` | `export_pdf` | Download claim as PDF |
| `GET` | `/claims/:id/export/csv` | `export_csv` | Download claim as text report |
| `POST` | `/upload` | `upload` | Upload and process X12 file |

## Database Schema

### Claims Table

The `claims` table stores complete claim information:

```elixir
schema "claims" do
  field :raw_json, {:array, :map}          # Complete JSON claim data

  # Searchable fields automatically extracted during upload
  field :member_first_name, :string
  field :member_last_name, :string
  field :member_dob, :date
  field :payer_name, :string
  field :billing_provider_name, :string
  field :billing_provider_npi, :string
  field :pay_to_provider_name, :string
  field :pay_to_provider_npi, :string
  field :rendering_provider_name, :string
  field :rendering_provider_npi, :string
  field :clearinghouse_claim_number, :string
  field :date_of_service, :date

  timestamps()
end
```

### Migrations

1. **create_claims** — Initial claims table with `raw_json` field
2. **add_search_fields_to_claims** — Adds searchable text fields
3. **add_date_of_service_to_claims** — Adds date filtering capability

## Project Structure

```
lib/
├── claim_viewer/
│   ├── claims.ex                          # Context module for field extraction
│   ├── claims/
│   │   └── claim.ex                       # Ecto schema definition
│   ├── x12_validator.ex                   # Content-based X12 837 file validation
│   ├── x12_translator.ex                  # Calls Python pyx12 parser subprocess
│   ├── pdf.ex                             # PDF generation wrapper
│   └── x12/
│       ├── claim837.ex                    # Top-level Claim837 struct
│       ├── mapper.ex                      # Maps raw JSON ↔ typed structs
│       ├── schema_validator.ex            # Rust-backed 837 JSON Schema validation
│       ├── address.ex                     # Address struct
│       ├── billing_provider.ex            # BillingProvider struct
│       ├── claim_info.ex                  # ClaimInfo struct
│       ├── diagnosis.ex                   # Diagnosis struct
│       ├── pay_to_provider.ex             # PayToProvider struct
│       ├── payer.ex                       # Payer struct
│       ├── receiver.ex                    # Receiver struct
│       ├── rendering_provider.ex          # RenderingProvider struct
│       ├── service_facility.ex            # ServiceFacility struct
│       ├── service_line.ex                # ServiceLine struct
│       ├── submitter.ex                   # Submitter struct
│       ├── subscriber.ex                  # Subscriber struct
│       └── transaction.ex                 # Transaction struct
├── claim_viewer_web/
│   ├── controllers/
│   │   ├── page_controller.ex             # Handles upload, search, and display
│   │   ├── page_html.ex                   # Helper functions
│   │   └── page_html/
│   │       ├── dashboard.html.heex        # Dashboard statistics
│   │       ├── home.html.heex             # Main UI with search form and results
│   │       └── claim.html.heex            # Individual claim detail view
priv/
├── python/
│   └── parser_for_viewer.py               # Python X12-to-JSON parser
├── schemas/
│   └── 837_5010_schema.json               # HIPAA-compliant 837 JSON Schema
└── repo/
    └── migrations/
        ├── *_create_claims.exs
        ├── *_add_search_fields_to_claims.exs
        └── *_add_date_of_service_to_claims.exs
```

## Technical Details

### Field Extraction

The `Claims` context module extracts searchable fields from the nested JSON structure during upload:

```elixir
def extract_search_fields(sections) do
  %{
    member_first_name: get_in_section(sections, "subscriber", ["firstName"]),
    member_last_name: get_in_section(sections, "subscriber", ["lastName"]),
    member_dob: get_in_section(sections, "subscriber", ["dob"]),
    payer_name: get_in_section(sections, "payer", ["name"]),
    # ... additional fields
  }
end
```

### Dynamic Query Building

Search queries are built dynamically based on which fields have values:

```elixir
defp maybe_like(query, _field, ""), do: query
defp maybe_like(query, field, value) do
  where(query, [c], ilike(field(c, ^field), ^"%#{value}%"))
end
```

### Rust-Backed JSON Schema Validation

The application uses [`ex_jsonschema`](https://hex.pm/packages/ex_jsonschema) for JSON Schema validation. Under the hood, `ex_jsonschema` is a **Native Implemented Function (NIF)** — it wraps the Rust [`jsonschema`](https://crates.io/crates/jsonschema) crate and compiles it into a shared library that the BEAM loads directly into its process space.

**What the Rust toolchain does:**
- The Rust compiler (`rustc`) and its package manager (`cargo`) compile the `jsonschema` crate and its transitive dependencies into a native shared library (`.so` on Linux, `.dylib` on macOS) during `mix deps.compile`.
- This compiled NIF is loaded by the BEAM at application startup, giving Elixir code direct, zero-overhead access to the Rust validation engine.

**Why this matters for performance:**
- **Native speed** — JSON Schema validation runs as compiled machine code inside the BEAM process, not as interpreted Elixir. For complex schemas like HIPAA 837 5010, this is orders of magnitude faster than a pure-Elixir validator.
- **Schema compiled once** — The JSON Schema is parsed and compiled into an optimized in-memory representation once at startup (cached via `:persistent_term`). Every subsequent validation call reuses this compiled schema, avoiding repeated parsing.
- **No subprocess overhead** — Unlike the Python pyx12 parser (which spawns an OS process via `System.cmd`), the Rust NIF runs in-process with no serialization, no IPC, and no process creation cost.

**Do you need Rust installed?**
- **Usually no.** The `ex_jsonschema` library ships with precompiled binaries for common platforms (macOS arm64/x86_64, Linux x86_64). When you run `mix deps.get`, the precompiled NIF is downloaded automatically.
- **Only if** no precompiled binary exists for your platform will `mix deps.compile` attempt to compile from source, which requires `rustc` and `cargo` (install via [rustup.rs](https://rustup.rs)).

## Technology Stack

- **Web framework:** Phoenix 1.8+
- **Language:** Elixir 1.19+ on Erlang/OTP 28+
- **Database:** PostgreSQL via Ecto
- **X12 parsing:** Python `pyx12` library (called as subprocess)
- **JSON Schema validation:** `ex_jsonschema` (Rust NIF via `jsonschema` crate)
- **PDF generation:** `chromic_pdf` using Chrome headless (DevTools Protocol)
- **Frontend:** Server-rendered HEEx templates with Tailwind CSS dark theme
- **No external UI libraries** — Pure HTML/Elixir templates without JavaScript frameworks

## Development

### Environment Variables

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

## Contributors

<ol type="I">
  <li><b>Irini Gega</b></li>
  <li><b>Le Luo</b></li>
  <li><b>Charles E. O'Riley Jr.</b></li>
  <li><b>Don Fox</b></li>
  <li><b>Verbus M. Counts</b></li>
</ol>

## Acknowledgments

Special thanks to the team working on the X12 837 Translator and Claims Viewer Program for their collaboration and support.
 