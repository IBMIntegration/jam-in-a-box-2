#!/bin/sh
set -e

echo "=== Starting htdocs extraction ==="
echo "Current working directory: $(pwd)"
echo "Contents of /archive:"
ls -la /archive/ || echo "No /archive directory found"

# Change to the nginx html directory
echo "Changing to /usr/share/nginx/html"
cd /usr/share/nginx/html
echo "Current directory: $(pwd)"

# Extract archive if it exists
if [ -f /archive/htdocs.tar.gz ]; then
    echo "Found htdocs archive, extracting..."
    echo "Archive size:"
    ls -la /archive/htdocs.tar.gz
    echo "Archive contents (first 10):"
    tar -tzf /archive/htdocs.tar.gz | head -10
    echo "Extracting with --strip-components=1..."
    tar xzf /archive/htdocs.tar.gz --strip-components=1 -v
    echo "Extracted htdocs content successfully"
    echo "Final contents of /usr/share/nginx/html:"
    ls -la /usr/share/nginx/html
else
    echo "No htdocs archive found at /archive/htdocs.tar.gz"
    echo "Available files in /archive:"
    ls -la /archive/ || echo "Cannot list /archive"
    echo "Creating default index.html"
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Start Here App - Debug</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; }
        .container { max-width: 800px; margin: 0 auto; }
        .warning { background: #fff3cd; padding: 15px; border-radius: 5px; }
        .debug { background: #f8f9fa; padding: 15px; border-radius: 5px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Start Here App - Debug Mode</h1>
        <div class="warning">
            <h3>⚠️ No Content Archive Found</h3>
            <p>The htdocs directory was not found during deployment.</p>
            <p>Expected location: <code>start-here-app/htdocs/</code></p>
        </div>
        <div class="debug">
            <h3>Debug Information</h3>
            <p>This page was generated because no htdocs.tar.gz was found.</p>
            <p>Check the init container logs for more details.</p>
        </div>
    </div>
</body>
</html>
EOF
    echo "Created fallback index.html"
fi

echo "Final directory listing:"
ls -la /usr/share/nginx/html
echo "=== htdocs extraction complete ==="