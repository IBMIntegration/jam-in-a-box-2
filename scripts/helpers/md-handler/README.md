# MD Handler

A Node.js HTTP server that serves markdown files with template variable processing.

## Quick Start

```bash
# Install dependencies
npm install

# Start both servers (main + admin)
npm start
```

**Servers:**

- **Main Server**: <http://localhost:8080> - Serves markdown files with template processing
- **Admin Server**: <http://localhost:8081> - Web interface for template configuration

## Commands

```bash
npm start              # Start both servers
npm test               # Run all tests
npm run test:unit      # Run unit tests only
npm run test:integration # Run integration tests only
npm run admin          # Start admin server only
```

## Template Variables

Use `{{ variable | default }}` syntax in your markdown files:

```markdown
# Hello {{ name | World }}!

This is a {{ type | demo }} file.
```

Configure variables via:

- Admin web interface: <http://localhost:8081>
- Direct config file: `template-config.json`
- Environment variables

## Configuration

**Server options (run from md-handler directory):**

```bash
node src/index.js --port 8080 --base-path ./test-content --host 0.0.0.0
```

**Or with absolute paths:**

```bash
node src/index.js --port 8080 --base-path /full/path/to/content --host 0.0.0.0
```

**Environment variables:**

- `PORT` - Main server port (default: 8080)
- `ADMIN_PORT` - Admin server port (default: 8081)
- `BASE_PATH` - Directory to serve files from
- `HOST` - Host to bind to (default: 0.0.0.0)

## Project Structure

```text
src/
├── index.js           # Main entry point
├── file-handler.js    # Core file processing
└── admin.js          # Admin server

test/
├── test-templates.js  # Unit tests
├── test-integration.js # Integration tests
└── run-tests.js      # Test runner
```

## Health Checks

- Main: <http://localhost:8080/health>
- Admin: <http://localhost:8081/health>

## Testing

```bash
# Test markdown to HTML conversion
curl http://localhost:8080/sample.html  # Converts test-content/sample.md to HTML

# Test direct markdown
curl http://localhost:8080/sample.md    # Returns raw markdown with template processing

# Health check
curl http://localhost:8080/health       # Returns "OK"
```

## Troubleshooting

**404 File not found**: Ensure the `--base-path` points to the directory containing your files, and run the command from the md-handler directory or use absolute paths.

**Module not found**: Make sure you're in the md-handler directory when running `node src/index.js`, or use the absolute path to the file.
