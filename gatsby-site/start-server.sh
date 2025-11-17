#!/bin/bash
set -e

# Create a simple hello-world Node.js server
# cat > /app/server.js << 'EOF'
# const http = require('http');
# const os = require('os');

# const hostname = '0.0.0.0';
# const port = 8000;

# const server = http.createServer((req, res) => {
#   res.statusCode = 200;
#   res.setHeader('Content-Type', 'text/html');
#   res.end(`
#     <html>
#       <head><title>Hello World</title></head>
#       <body>
#         <h1>Hello World from Node.js!</h1>
#         <p>Hostname: ${os.hostname()}</p>
#         <p>Platform: ${os.platform()}</p>
#         <p>Time: ${new Date().toISOString()}</p>
#         <p>Request URL: ${req.url}</p>
#         <p>Request Method: ${req.method}</p>
#       </body>
#     </html>
#   `);
# });

# server.listen(port, hostname, () => {
#   console.log(`Server running at http://${hostname}:${port}/`);
#   console.log(`Pod hostname: ${os.hostname()}`);
# });
# EOF

# Set content root path from parameter or default to /app/content
CONTENT_ROOT=${1:-$(cd "$(dirname "$0")" && pwd)/build}

for arg in "$@"; do
  case $arg in
    --content-root=*)
      CONTENT_ROOT="${arg#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

mkdir -p "$CONTENT_ROOT"

cd "$CONTENT_ROOT"
npx -y gatsby new integration-jam-in-a-box \
  https://github.com/carbon-design-system/gatsby-starter-carbon-theme \
  --json --verbose

cd integration-jam-in-a-box
npm run dev
