# TMS — Translation Management System

A team-based translation tool for i18n files (Laravel, Vue, Symfony, Go, React, Angular, Flutter).

**Version:** 1.0.0

## Features

- **Project & File Management:** Multi-project support. Upload `.php`, `.json`, `.js`, `.yaml`, etc.
- **Supported Formats:** Laravel PHP arrays, Vue i18n JSON, Vue i18n JS (export default).
- **Bulk Upload:** Upload multiple files at once. Supports "Overwrite" to update source keys while keeping existing translations.
- **Roles:** Admin, Project Admin, Lead Translator, Translator.
- **Workflow:** Submit -> Review -> Approve/Reject (requires 2 approvals, at least one admin). Revisions are immutable.
- **Translation Editor:**
  - Paginated view (handles 2,000+ keys efficiently).
  - **AI Translation:** Translate single keys or the whole file (LibreTranslate).
  - **Translation Memory:** Suggests past human translations from the same project.
  - **Tag Validator:** Warns if HTML tags or placeholders (like `{name}`) are missing.
  - **Optimistic Locking:** Prevents overwriting concurrent edits (safe saves).
- **History & Accounting:**
  - Full per-key history (translated, corrected, validated).
  - Word counts split by translated / corrected / self-edits.
  - Anti-cheat rules (reverts and self-edits don't count).
- **Dashboard & Profile:**
  - Personal assigned/reviewable files.
  - Lifetime word stats.
  - Dark mode.
- **Notifications:** In-app notifications with per-user preferences.

## Tech Stack

- **Backend:** Perl + Mojolicious + PostgreSQL
- **Frontend:** Vue 3 + Vite + Pinia
- **AI:** LibreTranslate (self-hosted) + Gemini (optional)
- **Auth:** Server-side sessions + CSRF tokens

---

## Prerequisites

Before you begin, ensure you have the following installed:

- **Perl** (>= 5.30)
- **Carton** (`cpanm Carton`)
- **Node.js** (>= 18) and `npm`
- **PostgreSQL** (>= 14)
- **Python 3** (>= 3.8, for LibreTranslate without Docker)

---

## Quick Start

### 1. Backend (Perl)

Clone the repository and install the Perl dependencies:

```bash
# Create environment file
cp .env.example .env

# Edit .env with your database credentials and a random secret
# Example:
#   TMS_SECRET=your_random_64_char_hex
#   DATABASE_URL=postgres://tms:tms@localhost:5432/tms
#   TMS_DEV_ADMIN_EMAIL=admin@example.com
#   TMS_DEV_ADMIN_PASSWORD=ChangeMeStrong!

# Install dependencies into local/
carton install

# Reset the database, run migrations, and create the first admin user
carton exec -- perl script/reset_db.pl

# Start the backend server
carton exec -- morbo script/tms
# Server running at http://127.0.0.1:3000
```

### 2. Frontend (Vue)

Open a new terminal window:

```bash
cd frontend
npm install
npm run dev
# Frontend running at http://localhost:5173
```

The frontend automatically proxies `/api` requests to the backend on port `3000`.

---

## AI Translation Setup (LibreTranslate)

The system uses LibreTranslate for AI translations. You can run it with Docker (easier) or directly with Python (no Docker required).

### Option A: Using Docker (Recommended)

```bash
docker run -d --name libretranslate \
  -p 5000:5000 \
  -e LT_LOAD_ONLY=en,fr,de,ar,es \
  libretranslate/libretranslate
```

### Option B: Without Docker (Python)

If you don't have Docker, you can install LibreTranslate using `pip`.

```bash
# 1. Create an isolated virtual environment
python3 -m venv ~/.venvs/libretranslate
source ~/.venvs/libretranslate/bin/activate

# 2. Install LibreTranslate
pip install libretranslate

# 3. Start the server (only load the languages you need to save RAM)
libretranslate --host 127.0.0.1 --port 5000 --load-only en,fr,de,ar,es
```

*Note: The first start will download the language models, which may take a few minutes.*

### Configure TMS to use LibreTranslate

Whether you used Docker or Python, add this line to your `.env` file:

```dotenv
LIBRETRANSLATE_URL=http://localhost:5000
```

Restart the backend (`morbo script/tms`) for the changes to take effect. You should see `[info] AI engine enabled: LibreTranslate` in the logs.

---

## Running the Tests

The test suite uses an isolated database (`tms_test`) to avoid modifying your development data.

```bash
# Create and seed the test database
carton exec -- perl script/test_db.pl

# Run all tests
carton exec -- perl prove -l t
```

---

## Database Management

- **`script/migrate.pl`**: Applies new migration files from `sql/` in lexical order. Refuses to run if a previously applied file was modified.
- **`script/reset_db.pl`**: Drops the database, recreates it, runs all migrations, and seeds the admin user (only works in development mode).
- **`script/test_db.pl`**: Recreates `tms_test`, runs migrations, and seeds the admin.
- **`script/seed_admin.pl`**: Manually creates or updates an admin user.

---

## Roles & Workflow

- **admin** — Full access. Can manage users, projects, and settings. Final approval authority.
- **lead_translator** — Can review translations and approve/reject files.
- **translator** — Can only see and translate files assigned to them.

### Approval Rules

A file is only considered **approved** when:
1. It receives at least **2 approvals**.
2. At least **1 of those approvals** is from a global **admin**.
3. The assigned translator cannot approve their own work.

If a file is rejected, a **new revision** is opened automatically. Old translations are preserved in history, and the translator can continue working.

---

## License

MIT
