# Subpath Scanner

AST-based scanner for detecting absolute path issues in SPAs deployed to subpaths.

## Problem

When deploying SPAs to subpaths (e.g., `/my-app/` instead of `/`), hardcoded absolute paths break:
- `fetch('/api/data')` → tries to load from `/api/data` instead of `/my-app/api/data`
- `queryKey: ['/api/stats']` → React Query keys become incorrect
- `queryKey.join('/')` → Architectural issue where keys are used as URLs

## Solution

This scanner uses AST parsing to detect these issues before deployment.

## Installation

```bash
cd subpath-scanner
npm install
npm run build
```

## Usage

```bash
# Scan current directory
npm run scan

# Scan specific directory
node dist/cli.js scan --dir=/path/to/your/app

# JSON output
node dist/cli.js scan --format=json
```

## Detected Patterns

### 1. absolute-fetch-url (Error)
Detects `fetch('/api/...')` calls with absolute paths.

**Example:**
```typescript
fetch('/api/sessions')  // ❌ Will break in subpath deployment
fetch(apiUrl('/api/sessions'))  // ✅ Correct
```

### 2. query-key-absolute-path (Error)
Detects React Query keys with absolute paths.

**Example:**
```typescript
queryKey: ['/api/stats']  // ❌ Will break
queryKey: ['api', 'stats']  // ✅ Correct
```

### 3. query-fn-url-join (Critical)
Detects the architectural anti-pattern of using `queryKey.join('/')` to construct URLs.

**Example:**
```typescript
// ❌ CRITICAL: queryKey used as URL path
queryFn: ({ queryKey }) => fetch(queryKey.join('/'))

// ✅ Correct: Separate keys from URL construction
queryFn: ({ queryKey }) => {
  const [, id] = queryKey;
  return fetch(apiUrl(`/api/resource/${id}`));
}
```

## Integration with Deployment

Add to your pre-deploy validation:

```bash
if command -v node &> /dev/null; then
    if [ -d "/home/ubuntu/src/deploy-portal/subpath-scanner" ]; then
        cd /home/ubuntu/src/deploy-portal/subpath-scanner
        node dist/cli.js scan --dir="$APP_DIR"
    fi
fi
```

## Exit Codes

- `0` - No issues found
- `1` - Issues detected

## Output Example

```
═══════════════════════════════════════════════════════════
  Subpath Deployment Scanner v0.1.0
═══════════════════════════════════════════════════════════

CRITICAL ISSUES (1)

  ✖✖ query-fn-url-join
    File: client/src/lib/queryClient.ts:32:18

    queryKey.join('/') used to construct URL - ARCHITECTURAL ISSUE

    Fix: Refactor to separate query keys from URL construction
    Auto-fixable: No

ERRORS (7)

  ✖ absolute-fetch-url
    File: client/src/components/live-transcription.tsx:124

    fetch() uses absolute path '/api/sessions'

    Fix: Wrap with base URL helper: fetch(apiUrl('/api/sessions'))
    Auto-fixable: Yes (Phase 2)

SUMMARY
  Files scanned: 127
  Issues found: 8 (Critical: 1, Errors: 7, Warnings: 0)
  Auto-fixable: 7 (Phase 2 feature)
```

## Roadmap

- [x] Phase 1: Core scanner with fetch and query-key detection
- [ ] Phase 2: Auto-fix capabilities
- [ ] Phase 3: Framework-specific detection (Vite, Wouter, React Router)
- [ ] Phase 4: Full deployment kit integration

## License

MIT
