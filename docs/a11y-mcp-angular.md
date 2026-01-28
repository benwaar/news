# Accessibility checks for an Angular project (CLI + MCP)

This guide adds **two layers** of accessibility checking to an Angular repo:

1) **Static template linting** (fast feedback in PRs / CI)
2) **Runtime scanning of the rendered app** using an **MCP accessibility scanner** (Playwright + axe-core)

---

## Prerequisites

- Node.js (LTS recommended)
- An Angular CLI app (`ng version` works)
- Your app can be started locally (e.g. `ng serve`)

---

## 1) Add static template a11y linting (Angular ESLint)

Angular ESLint’s template rules include accessibility-focused checks (e.g., `alt-text`).

### Install Angular ESLint (if not already present)

```bash
ng add @angular-eslint/schematics
```

### Ensure template plugin is installed

```bash
npm i -D @angular-eslint/eslint-plugin-template
```

### Enable the accessibility ruleset for Angular templates

In your ESLint config (commonly `.eslintrc.json`), ensure you have an override for `*.html`
templates that extends the **template accessibility** config.

Example:

```json
{
  "overrides": [
    {
      "files": ["*.ts"],
      "extends": ["plugin:@angular-eslint/recommended"]
    },
    {
      "files": ["*.html"],
      "extends": [
        "plugin:@angular-eslint/template/recommended",
        "plugin:@angular-eslint/template/accessibility"
      ],
      "rules": {
        "@angular-eslint/template/alt-text": "error"
      }
    }
  ]
}
```

Run lint:

```bash
npx eslint .
```

> Tip: keep this running in CI (see scripts below). Template linting catches lots of “easy wins”
> before you even boot the app.

---

## 2) Add runtime a11y scanning via an MCP server (richer / best coverage)

For SPAs like Angular, the best coverage comes from scanning the **rendered DOM** after routing,
dialogs, lazy-loaded content, etc. The “richer” approach is:

- **Playwright** drives a real browser
- **axe-core** audits the page
- An **MCP server** exposes “scan” tools you can call from the command line

We’ll use: `mcp-accessibility-scanner` (Playwright + axe-core).

### Install Playwright (recommended)

The scanner will use Playwright. In many environments you’ll want the Playwright browsers installed:

```bash
npx playwright install --with-deps
```

(If you’re on macOS/Windows, `--with-deps` may be unnecessary.)

---

## 3) Run the MCP accessibility scanner server

You can run it without installing globally:

```bash
npx -y mcp-accessibility-scanner
```

This starts an MCP server process that exposes tools like page navigation and accessibility scans.

---

## 4) Call MCP tools from the terminal (two good options)

### Option A (recommended): MCP Inspector CLI

The official MCP Inspector supports a CLI mode, which is convenient for scripting.

**Start the inspector in CLI mode and point it at the accessibility scanner server:**

```bash
npx @modelcontextprotocol/inspector --cli npx -y mcp-accessibility-scanner
```

Then, in the inspector CLI, you can:

- list tools
- call the scan tool with JSON arguments
- save JSON output

Common flow:

1) Start your Angular app (Terminal A):

```bash
npm run start
# or: ng serve --port 4200
```

2) Start the Inspector CLI + MCP scanner (Terminal B):

```bash
npx @modelcontextprotocol/inspector --cli npx -y mcp-accessibility-scanner
```

3) In the inspector CLI:
   - `tools` (list available tools)
   - navigate/open to your running app URL
   - run the accessibility scan tool (usually named something like `scan_page`)

**Example call shape** (tool name can vary by server version; confirm via `tools`):

```json
{
  "url": "http://localhost:4200",
  "tags": ["wcag21aa"]
}
```

If the server supports it, also scan key routes:

- `/`
- `/login`
- `/settings`
- any critical forms / dialogs

> If your app requires auth, use the server’s browser automation tools (navigate, click, fill)
> to log in, then scan.

### Option B: mcptools (interactive shell)

There’s also a dedicated CLI called **mcptools** that can connect to MCP servers and call tools.

- Repo: https://github.com/f/mcptools

Use it if you prefer an interactive shell focused on tool calls.

---

## 5) Add npm scripts (recommended)

Add these to your `package.json`:

```json
{
  "scripts": {
    "lint": "eslint .",
    "a11y:serve": "ng serve --port 4200",
    "a11y:mcp": "npx -y mcp-accessibility-scanner",
    "a11y:inspector": "npx @modelcontextprotocol/inspector --cli npx -y mcp-accessibility-scanner"
  }
}
```

Typical usage:

```bash
npm run lint
npm run a11y:serve
# in another terminal
npm run a11y:inspector
```

---

## 6) CI sketch (GitHub Actions style)

A minimal CI flow usually looks like:

1) `npm ci`
2) `npm run lint`
3) start the app (serve)
4) run your MCP tool calls to scan routes
5) fail the job if violations exceed a threshold

Because MCP tool-calling is a little different per environment, teams often do one of these:

- **Use MCP Inspector CLI** and script tool calls (good when you already have MCP workflows)
- Or run Playwright + axe directly in a Playwright test (simpler CI wiring)

Playwright’s official a11y testing docs (axe integration) can help if you decide to go “pure Playwright”:
https://playwright.dev/docs/accessibility-testing

---

## What you’ll catch (and what you won’t)

✅ Catches:
- missing accessible names (alt, aria-label, etc.)
- color contrast issues (where detectable)
- ARIA misuse
- landmark / heading structure issues
- form label associations

❌ Won’t fully catch:
- whether the *content* of alt text is meaningful
- whether focus order matches visual order in all cases
- UX-level accessibility issues (needs manual review)

---

## Suggested route checklist

Scan at least:

- landing page
- primary navigation states
- forms (create/edit)
- dialog + toast patterns
- error states (validation, 404, etc.)
- keyboard-only navigation for critical flows (manual)

---

## Troubleshooting

- If Playwright can’t launch: run `npx playwright install` (or `--with-deps` on Linux).
- If the scan tool name differs: use `tools` in the Inspector CLI to list the exact tool names and signatures.
- If your app uses a different port: update `http://localhost:4200`.

