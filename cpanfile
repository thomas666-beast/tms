# ============================================================
# TMS — Perl dependencies
# ============================================================
# Rule: a module is listed here only when a task actively uses it.
# ============================================================

requires 'perl', '5.030';

# --- Web framework ---
requires 'Mojolicious';
requires 'Mojolicious::Plugin::Config';

# --- Database ---
requires 'Mojo::Pg';

# --- Auth / sessions / security ---
requires 'Mojolicious::Plugin::CSRFProtect';
requires 'Authen::Passphrase';
requires 'Crypt::Eksblowfish';   # bcrypt backend
requires 'Crypt::URandom';

# --- JSON ---
requires 'JSON::XS';

# --- ENV ---
requires 'Dotenv';

# --- dev / test ---
on 'develop' => sub {
    requires 'Test::More';
    requires 'Test::Mojo';
    requires 'Perl::Tidy';
    requires 'DBD::Pg';   # needed for Mojo::Pg to talk to Postgres
};
