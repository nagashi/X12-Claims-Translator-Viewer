Claim Viewer

A web-based claim viewer application for storing, searching, and inspecting healthcare claim data.

This project is designed to work with parsed claim data in JSON format (for example, JSON output generated from an X12 837P to JSON translation step). The application stores the full claim JSON in a PostgreSQL database and provides a user-friendly interface for searching and viewing claims.

Features

Upload parsed claim JSON files

Store complete claim data as JSON in PostgreSQL

Extract and persist searchable claim fields

Search claims by:

Patient first name

Patient last name

Payer name

Billing provider

Rendering provider NPI

Claim number

Date of service range

View full claim details grouped by logical sections

Simple web interface for browsing and inspecting claims

Tech Stack

Elixir

Phoenix Framework

Ecto

PostgreSQL

HEEx templates (HTML)

How It Works

Parsed claim JSON files are uploaded through the web interface

The full JSON payload is stored in the database

Key fields (patient, provider, payer, dates, claim number) are extracted into database columns to enable efficient searching

Users can search for claims using multiple criteria

Selecting a claim displays the full claim content grouped by section

Expected Input Format

The application expects structured JSON organized by sections, for example:

[
  {
    "section": "transaction",
    "data": { }
  },
  {
    "section": "subscriber",
    "data": { }
  },
  {
    "section": "payer",
    "data": { }
  },
  {
    "section": "claim",
    "data": { }
  },
  {
    "section": "service_Lines",
    "data": [ ]
  }
]


The viewer does not parse raw X12 files directly. It assumes that the X12-to-JSON translation step has already been completed.

Search Behavior

Date of Service is derived from the service lines in the claim

Start and end date filters operate on the stored date_of_service field

Searches can be combined across multiple fields

Project Structure
claim_viewer/
├── lib/
│   ├── claim_viewer/
│   │   ├── claims/
│   │   │   └── claim.ex
│   │   └── claims.ex
│   ├── claim_viewer_web/
│   │   ├── controllers/
│   │   └── templates/
├── priv/
│   └── repo/
│       └── migrations/
├── README.md

Database

PostgreSQL

Stores:

Full claim JSON payload

Extracted searchable fields

Date of service for range queries

Status

This project is under active development and serves as a foundation for integrating parsed healthcare claim data with a searchable web-based viewer.

Author

Irini



