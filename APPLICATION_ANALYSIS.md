# Claim Viewer — Application Analysis

## Purpose

Claim Viewer is a two-component healthcare claims system that:

1. **Translates** raw X12 837P EDI files into structured JSON (via a Python parser using the `pyx12` library).
2. **Stores, searches, and displays** the resulting claim data through a Phoenix/Elixir web application backed by PostgreSQL.

The primary workflow is: upload an X12 file → auto-translate to JSON → extract searchable fields → persist to database → search/view/export.

---

## File Input Capabilities

### Accepted File Types

The application **only** accepts X12 EDI claim files. The upload handler (`PageController.upload/2`) restricts by extension:

- `.txt` — standard text-formatted X12
- `.edi` — EDI format
- `.837` — X12 837 format

Any other extension is rejected with an error message. The HTML file input also enforces `accept=".txt,.edi,.837"`.

### Single File Upload Only

The application handles **one file at a time**. There is **no batch upload capability**:

- The upload form (`<input type="file" name="file" .../>`) accepts a single file, not `multiple`.
- `PageController.upload/2` pattern-matches on `%{"file" => %Plug.Upload{...}}` — a single file struct.
- There is no directory scanning, file queuing, or multi-file processing logic anywhere in the codebase.

### JSON Is Not Accepted as Direct Input

The README explicitly states: *"JSON is used internally as an intermediate format for storage and processing. Users should upload X12 files, not JSON files."* The upload handler will reject `.json` files as an unsupported type.

> **Note:** The dashboard's hidden upload form still has `accept=".json,.txt,.edi,.837"` in `dashboard.html.heex`, but the server-side controller rejects `.json` regardless. This is a minor inconsistency.

### X12 Translation Pipeline

When a file is uploaded:

1. The uploaded file is saved to a temp path by Plug.
2. `ClaimViewer.X12Translator.translate_x12_to_json/1` is called.
3. This invokes the Python script `priv/python/parser_for_viewer.py` via `System.cmd/3`, passing the temp file path and a temp output JSON path.
4. The Python parser uses `pyx12.x12file.X12Reader` to iterate over segments and builds a structured JSON array of section objects.
5. The resulting JSON is read back into Elixir and decoded with `Jason`.
6. If the X12 file contains multiple CLM segments (multiple claims), the parser returns an array of section arrays; Elixir flattens nested arrays so only the first claim's sections are stored (see the `case json_data do [first | _] when is_list(first) -> first` logic).

**This means: even if an X12 file contains multiple claims, only the first claim is saved.**

---

## Data Model

### Database Schema (`claims` table)

The raw JSON (the full array of section objects) is stored in `raw_json` (`:array` of `:map`). Additionally, searchable fields are extracted at upload time and stored in dedicated columns:

| Column | Type | Description |
|---|---|---|
| `raw_json` | `jsonb[]` (array of maps) | Complete structured claim JSON |
| `patient_first_name` | `string` | From `subscriber.firstName` |
| `patient_last_name` | `string` | From `subscriber.lastName` |
| `patient_dob` | `date` | From `subscriber.dob` |
| `payer_name` | `string` | From `payer.name` |
| `billing_provider_name` | `string` | From `billing_Provider.name` |
| `billing_provider_npi` | `string` | From schema but NOT extracted by `Claims.extract_search_fields/1` |
| `pay_to_provider_name` | `string` | From `Pay_To_provider.name` |
| `pay_to_provider_npi` | `string` | From schema but NOT extracted by `Claims.extract_search_fields/1` |
| `rendering_provider_name` | `string` | From `renderingProvider.firstName` (note: only first name) |
| `rendering_provider_npi` | `string` | From `renderingProvider.npi` |
| `clearinghouse_claim_number` | `string` | From `claim.clearinghouseClaimNumber` |
| `date_of_service` | `date` | Extracted from first service line's `serviceDate` |

**Gaps in extraction:** `billing_provider_npi` and `pay_to_provider_npi` exist in the schema/migration but are never populated by `Claims.extract_search_fields/1`. They will always be `nil`.

### Database Indexes

Indexes exist on: `patient_last_name`, `patient_first_name`, `patient_dob`, `payer_name`, `billing_provider_name`, `billing_provider_npi`, `rendering_provider_npi`.

---

## Search Capabilities

Search is accessed via `GET /search` and implemented in `PageController.home/2`.

### Searchable Fields

| Field | Input Type | Query Method | Min Length |
|---|---|---|---|
| Patient first name | Text | `ILIKE %value%` | 2 chars |
| Patient last name | Text | `ILIKE %value%` | 2 chars |
| Payer name | Text | `ILIKE %value%` | 2 chars |
| Billing provider | Text | `ILIKE %value%` | 2 chars |
| Rendering provider NPI | Text (10 digits) | Exact match (`==`) | 2 chars |
| Claim # | Text | `ILIKE %value%` | 2 chars |
| Service date from | Date | `>=` comparison | N/A |
| Service date to | Date | `<=` comparison | N/A |
| Status | Select (approved/pending) | Raw SQL `jsonb` fragment | N/A |

### Search Behavior

- All text fields require a minimum of 2 characters (enforced by `valid_search?/1`).
- Text fields use case-insensitive partial matching via PostgreSQL `ILIKE`.
- Rendering provider NPI uses exact match.
- Patient first + last name are combined in a single `AND` clause when both are provided.
- Date range filtering works on the `date_of_service` column.
- Status filtering uses raw PostgreSQL `jsonb` queries to inspect `indicators` within `raw_json`.
- Results are paginated (10 per page).
- A search requires at least one field to have a value; otherwise no query is run.

### Known Bug in Search Logic

In `page_controller.ex` around line 80-81, the `has_search?` boolean has a syntax issue:

```elixir
service_to != ""
status != ""
```

The `status != ""` line is a standalone expression, not combined with `or`. This means `status` alone won't trigger a search. It evaluates as two separate expressions where only `status != ""` becomes the value of `has_search?` (overwriting the previous `or` chain due to the missing `or` operator).

---

## Display / View Capabilities

### Dashboard (`GET /`)

The root route serves a dashboard with aggregate statistics:

- Total claims count
- Claims added this month
- Claims over 30 days old
- Approved vs. pending breakdown (based on `indicators` in `raw_json`)
- Approved revenue total

### Search Results Page (`GET /search`)

- Table with columns: Patient name, Payer, Claim #
- Patient name is a clickable link to full claim view
- Claims inserted in the last 24 hours get a "NEW" badge
- Pagination controls (prev/next, page numbers)

### Full Claim View (`GET /claims/:id`)

When viewing a single claim, the `show/2` action loads it and passes `raw_json` to the template. The template renders:

- **Claim type badge** — Detected from the `version` field in the transaction section:
  - `X222` → 837P (Professional)
  - `X223` → 837I (Institutional)
  - `X224` → 837D (Dental)
  - Otherwise → "UNKNOWN"

- **Claim summary card** — Patient name/DOB, payer, claim #, service date range, total charge, status, rendering provider NPI.

- **All sections rendered** — Each section in `raw_json` is iterated:
  - **Map sections** (transaction, submitter, receiver, billing provider, pay-to provider, subscriber, payer, claim, diagnosis, rendering provider, service facility): Rendered as labeled field-value pairs. Special handling for:
    - `firstName`/`lastName` shown first
    - Address maps rendered inline
    - Phone numbers formatted as `(XXX) XXX-XXXX`
    - `indicators` map rendered as colored badges (green = approved, gray = other)
    - Date fields (`dob`, `onsetDate`, `date`) formatted as "Month DD, YYYY"
  - **List sections** (service lines): Rendered as a table with sortable columns (`lineNumber` first), service dates formatted, and a total charge sum at the bottom.

---

## Export Capabilities

### PDF Export (`GET /claims/:id/export`)

- Generates an HTML document server-side with inline CSS styling.
- Uses `wkhtmltopdf` (via the `pdf_generator` library) to convert HTML → PDF.
- Gracefully degrades: if `wkhtmltopdf` is not installed, returns a flash error instead of crashing.
- Includes claim summary + all sections (maps as field-value divs, lists as HTML tables).

### CSV Export (`GET /claims/:id/export/csv`)

- Generates a plain-text CSV-style report (not true comma-delimited CSV — it's a human-readable text format).
- Contains a summary header, then each section's data formatted with labels and values.
- Service lines are rendered per-line with indented fields.
- Dates are formatted as "Month DD YYYY".
- Includes a generation timestamp.

---

## Architectural Notes

### Technology Stack

- **Web framework:** Phoenix 1.8+ (traditional controllers, not LiveView for the main pages)
- **Language:** Elixir 1.15+
- **Database:** PostgreSQL via Ecto
- **Python dependency:** `pyx12` library for X12 parsing (called as a subprocess)
- **PDF generation:** `pdf_generator` hex package wrapping `wkhtmltopdf` (optional runtime dep)
- **Frontend:** Server-rendered HEEx templates with inline styles (dark theme), minimal vanilla JavaScript

### Route Map

| Method | Path | Action | Purpose |
|---|---|---|---|
| `GET` | `/` | `dashboard` | Dashboard with stats |
| `GET` | `/search` | `home` | Search form + results |
| `GET` | `/claims/:id` | `show` | Full claim detail view |
| `GET` | `/claims/:id/export` | `export_pdf` | Download claim as PDF |
| `GET` | `/claims/:id/export/csv` | `export_csv` | Download claim as text report |
| `GET` | `/claim` | `claim` | Appears in router but no matching controller action found |
| `POST` | `/upload` | `upload` | Upload and process X12 file |

### Key Files

| File | Purpose |
|---|---|
| `lib/claim_viewer/x12_translator.ex` | Calls Python parser, reads JSON output |
| `lib/claim_viewer/claims.ex` | Field extraction from structured JSON |
| `lib/claim_viewer/claim.ex` | Ecto schema for the `claims` table |
| `lib/claim_viewer/pdf.ex` | PDF generation with graceful fallback |
| `lib/claim_viewer_web/controllers/page_controller.ex` | All HTTP actions (dashboard, search, show, upload, export) |
| `lib/claim_viewer_web/controllers/page_html.ex` | Helper functions (`human_label`, `format_date`, `format_phone`) |
| `lib/claim_viewer_web/controllers/page_html/home.html.heex` | Main UI: upload, search, results, claim detail view |
| `lib/claim_viewer_web/controllers/page_html/dashboard.html.heex` | Dashboard statistics page |
| `lib/claim_viewer_web/controllers/page_html/claim.html.heex` | Simple raw JSON claim view (appears unused in routing) |
| `priv/python/parser_for_viewer.py` | Python X12-to-JSON parser |

---

## JSON Structure (Internal Format)

Each claim is stored as an array of section objects. Each section has:

```json
{"section": "sectionName", "data": { ... } }
```

Sections: `transaction`, `submitter`, `receiver`, `billing_Provider`, `Pay_To_provider`, `subscriber`, `payer`, `claim`, `diagnosis`, `renderingProvider`, `serviceFacility`, `service_Lines`.

**Note:** Section naming is inconsistent (mix of camelCase, snake_case, and Title_Case). This affects field extraction — the `Claims.extract_search_fields/1` function must use exact section names like `"billing_Provider"`, `"Pay_To_provider"`, etc.

---

## Known Issues and Limitations

1. **Single file upload only** — No batch processing, no directory scanning, no multi-file upload.
2. **Only first claim saved from multi-claim files** — The flattening logic in `handle_x12_upload/3` takes only the first element if the parser returns nested arrays.
3. **Missing field extractions** — `billing_provider_npi` and `pay_to_provider_npi` are never populated despite having schema fields and DB columns.
4. **`has_search?` bug** — Missing `or` before `status != ""` causes the status filter alone not to work correctly as a search trigger.
5. **Inconsistent section naming** — `billing_Provider`, `Pay_To_provider`, `service_Lines` use mixed casing conventions.
6. **Dashboard upload form accepts `.json`** — The `accept` attribute in `dashboard.html.heex` includes `.json`, but the server rejects it.
7. **Dead route** — `GET /claim` maps to `PageController.claim` but no `claim/2` action exists in the controller.
8. **Inline styles** — All styling is inline rather than using Tailwind CSS classes (the README notes this as a future migration target).
9. **Inline `<script>` tags** — The templates use inline JavaScript despite the project rules (AGENTS.md) prohibiting this pattern.
10. **Python command inconsistency** — `x12_translator.ex` finds `python3` but then calls `System.cmd("python", ...)` instead of using the found executable path.
