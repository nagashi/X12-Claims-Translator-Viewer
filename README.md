
# Claim Viewer

A Phoenix/Elixir web application for viewing and searching healthcare claims in structured JSON format derived from X12 837P files.

## Project Context

This application is part of the **X12 837P Translator and Claims Viewer Program**. The complete system translates EDI-formatted healthcare claims into JSON and provides a user-friendly web interface for viewing and searching claim data.

**Project Components:**
- **X12 to JSON Translation** - Python tool using PyX12 library (separate component)
- **Claim Viewer** - This Phoenix/Elixir application for storing, searching, and displaying JSON claims with a structured user interface

## Features

✅ **JSON File Upload** - One-click file upload with automatic processing  
✅ **Persistent Storage** - PostgreSQL database storing both raw JSON and extracted searchable fields  
✅ **Advanced Multi-Criteria Search** - Search by patient name, payer, providers, claim number, and service date range  
✅ **Structured Display** - Clean, organized view of all claim sections in form-like layout (not raw JSON)  
✅ **Service Lines Table** - Dedicated table view for line-item charges with procedure codes, dates, and amounts  
✅ **Search Results Table** - Interactive results grid showing patient, payer, and claim information  
✅ **Modern Dark Theme UI** - Professional interface with cyan/green color scheme  
✅ **Case-Insensitive Search** - ILIKE queries for flexible text matching  
✅ **Date Range Filtering** - Filter claims by service date period  
✅ **Automatic Field Extraction** - Searchable fields automatically extracted from uploaded JSON

## Requirements

- Elixir 1.19+
- Erlang/OTP 28+
- Phoenix Framework 1.8+
- PostgreSQL 17+
- Ecto
- Jason

## Installation

```bash
# Clone the repository
git clone <your-repository-url>
cd claim_viewer

# Install dependencies
mix deps.get

# Configure database
# Edit config/dev.exs with your PostgreSQL credentials

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Start Phoenix server
mix phx.server
```

Visit **http://localhost:4000** in your browser.

## Usage

### Uploading Claims

1. Click the **Upload JSON** button on the home page
2. Select a JSON file containing X12 837P claim data
3. The file is automatically processed, fields are extracted, and the claim is stored in the database

### Searching for Claims

The search form supports multiple criteria that can be used individually or combined:

- **Patient first name** - Partial match, case-insensitive
- **Patient last name** - Partial match, case-insensitive
- **Payer name** - Insurance company name search
- **Billing provider** - Provider organization name
- **Rendering provider NPI** - Individual provider NPI number
- **Claim #** - Clearinghouse claim number
- **Service date range** - Filter by date range (from date and to date)

Click **Search** to view matching results or **Clear** to reset all fields.

### Viewing Claim Details

- Search results are displayed in a table with patient name, payer, and claim number
- Click on any patient name (blue underlined link) to view full claim details
- Full claim view displays data in a **structured, organized layout** with sections:
  - Transaction information
  - Submitter details
  - Receiver information
  - Billing Provider
  - Pay-To Provider
  - Subscriber (Patient) information
  - Payer details
  - Claim information
  - Diagnosis codes
  - Rendering Provider
  - Service Facility
  - Service Lines (displayed as a table)

All data is presented in an easy-to-read format with labeled fields, not as raw JSON.

## Database Schema

### Claims Table

The `claims` table stores complete claim information:

```elixir
schema "claims" do
  field :raw_json, {:array, :map}          # Complete JSON claim data
  
  # Searchable fields automatically extracted during upload
  field :patient_first_name, :string
  field :patient_last_name, :string
  field :patient_dob, :date
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

Three migrations define the database structure:

1. **create_claims.exs** - Initial claims table with raw_json field
2. **add_search_fields_to_claims.exs** - Adds searchable text fields
3. **add_date_of_service_to_claims.exs** - Adds date filtering capability

## Project Structure

```
lib/
├── claim_viewer/
│   ├── claims.ex                          # Context module for field extraction
│   └── claims/
│       └── claim.ex                       # Ecto schema definition
├── claim_viewer_web/
│   ├── controllers/
│   │   └── page_controller.ex             # Handles upload, search, and display
│   └── controllers/page_html/
│       ├── home.html.heex                 # Main UI with search form and results
│       └── claim.html.heex                # Individual claim detail view
priv/
└── repo/
    └── migrations/
        ├── *_create_claims.exs
        ├── *_add_search_fields_to_claims.exs
        └── *_add_date_of_service_to_claims.exs
```

## Routes

| Method | Path | Controller Action | Description |
|--------|------|-------------------|-------------|
| GET | `/` | `PageController.home` | Main search page with form |
| GET | `/claims/:id` | `PageController.show` | Display full claim details by ID |
| POST | `/upload` | `PageController.upload` | Process and store uploaded JSON file |

## Data Flow

**Upload Flow:**
1. User uploads JSON file via form
2. `PageController.upload/2` receives file
3. JSON is decoded using Jason library
4. `Claims.extract_search_fields/1` extracts searchable fields from JSON sections
5. `Claims.extract_date_of_service/1` extracts first service line date
6. New `Claim` record created with both raw JSON and extracted fields
7. Record inserted into PostgreSQL via Ecto
8. User redirected to home page

**Search Flow:**
1. User enters search criteria and submits form
2. `PageController.home/2` receives query parameters
3. Dynamic Ecto query built using `maybe_like/3` and `maybe_date_range/3` helpers
4. Database queried with ILIKE for text fields and range comparison for dates
5. Results rendered in table format on home page

**View Flow:**
1. User clicks patient name in search results
2. `PageController.show/2` loads claim by ID from database
3. Raw JSON passed to template
4. Template iterates through sections and renders structured display
5. Maps displayed as field-value pairs
6. Lists (service lines) displayed as tables

## Technical Implementation

### Field Extraction Logic

The `Claims` context module (`lib/claim_viewer/claims.ex`) contains logic to extract searchable fields from the nested JSON structure:

```elixir
def extract_search_fields(sections) do
  %{
    patient_first_name: get_in_section(sections, "subscriber", ["firstName"]),
    patient_last_name: get_in_section(sections, "subscriber", ["lastName"]),
    patient_dob: get_in_section(sections, "subscriber", ["dob"]),
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

### UI Rendering

The template (`home.html.heex`) handles three display states:
- Empty state: "Please enter search criteria"
- No results: "No results found"
- Results found: Display table with clickable patient names

Full claim view iterates through JSON sections and renders appropriately based on data type (map vs list).

## Claim Sections Displayed

When viewing a full claim, the following sections are displayed:

- **TRANSACTION** - Control number, date, purpose, reference ID, time, type, version
- **SUBMITTER** - Contact information, ID, name
- **RECEIVER** - ID and name
- **BILLING PROVIDER** - Address, name, tax ID
- **PAY TO PROVIDER** - Address, name, tax ID
- **SUBSCRIBER** - Patient address, DOB, first name, group number, ID, last name, plan type, relationship, sex
- **PAYER** - Payer name and payer ID
- **CLAIM** - Clearinghouse claim number, ID, indicators, onset date, place of service, service type, total charge
- **DIAGNOSIS** - Primary diagnosis code, secondary diagnosis codes (if any)
- **RENDERING PROVIDER** - First name, last name, NPI
- **SERVICE FACILITY** - Address, name, tax ID
- **SERVICE LINES** - Table with columns: charge, code qualifier, diagnosis pointer, emergency indicator, line number, procedure code, service date, unit qualifier, units

## Key Features Explained

### Automatic Field Extraction

When a JSON file is uploaded, the system automatically extracts key fields for searching. This is done by navigating the JSON structure using section names and field paths.

### Case-Insensitive Search

All text searches use PostgreSQL's `ILIKE` operator, allowing users to search without worrying about capitalization.

### Date Range Filtering

The date of service is extracted from the first service line item and stored separately, enabling fast date range queries.

### Structured Display vs Raw JSON

Unlike many claim viewers that show raw JSON or XML, this application presents data in a clean, organized format that healthcare professionals can easily read and understand.

## Development Notes

- **Phoenix Framework**: Leverages Phoenix's MVC architecture for clean separation of concerns
- **Ecto**: Uses Ecto for database interactions with type-safe queries
- **Jason Library**: Handles JSON encoding/decoding
- **Inline Styles**: Dark theme implemented with inline styles (future: migrate to CSS/Tailwind)
- **No External UI Libraries**: Pure HTML/Elixir templates without JavaScript frameworks

## Future Enhancements

- Export claims to PDF or CSV format
- Batch file upload (multiple JSON files at once)
- Additional search filters (diagnosis codes, procedure codes, provider specialties)
- Claims comparison view (compare two claims side-by-side)
- Analytics dashboard with claim statistics
- User authentication and multi-user support
- Audit log for tracking uploads and searches
- API endpoints for programmatic access


## Contributors

- **Irini** - Claim Viewer development (Phoenix/Elixir component)
- **X12 to JSON Translation** – separate team component

## Acknowledgments

Special thanks to the team working on the X12 837P Translator and Claims Viewer Program for their collaboration and support.
