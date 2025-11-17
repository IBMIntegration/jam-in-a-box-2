#!/usr/bin/env node

import http from 'http';
import url from 'url';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { updateTemplateConfig } from './file-handler.js';
import { ConfigReader } from './config-reader.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Admin Configuration Manager using shared ConfigReader
 * This handles template-related configuration, separate from the main server config
 */
class AdminConfig extends ConfigReader {
  constructor() {
    super({
      prefix: 'admin-',
      configFileName: 'config.json',
      envPrefix: 'ADMIN_',
      defaults: {
        port: 8082,
        host: '0.0.0.0'
      }
    });
    this.templateConfig = {};
  }

  async load() {
    // Load server configuration from all sources
    await super.load();
    
    return {
      server: this.getAll(),
      template: this.templateConfig
    };
  }

  /**
   * Load environment variables specific to the admin server
   */
  loadFromEnv() {
    const envMapping = {
      'ADMIN_PORT': { key: 'port', type: 'number' },
      'ADMIN_HOST': { key: 'host', type: 'string' }
    };
    this.parseEnv(envMapping);
  }

  /**
   * Load command line arguments specific to the admin server
   */
  loadFromArgs() {
    const argMapping = {
      '--admin-port': { key: 'port', type: 'number' },
      '--admin-host': { key: 'host', type: 'string' },
      '--help': { key: '_help', type: 'boolean' }
    };
    
    this.parseArgs(argMapping);
    
    if (this.get('_help')) {
      this.showHelp();
      process.exit(0);
    }
  }

  showHelp() {
    console.log(`
Admin Server for MD Handler

Usage: node admin.js [options]

Options:
  --admin-port <port>         Admin server port (default: 8082)
  --admin-host <host>         Admin server host (default: 0.0.0.0)
  --help                      Show this help message

Environment Variables:
  ADMIN_PORT                  Admin server port
  ADMIN_HOST                  Admin server host

The admin server manages template variables for markdown processing via REST API.
    `);
  }
}

/**
 * HTTP Admin Server for template configuration management
 */
class AdminServer {
  constructor(config) {
    this.config = config;
    this.server = http.createServer((req, res) => this.handleRequest(req, res));
  }

  async start() {
    return new Promise((resolve, reject) => {
      this.server.listen(this.config.server.port, this.config.server.host, (err) => {
        if (err) {
          reject(err);
        } else {
          console.log(`🔧 Admin server running at http://${this.config.server.host}:${this.config.server.port}`);
          console.log(`📝 Managing template variables via REST API`);
          resolve();
        }
      });
    });
  }

  async handleRequest(req, res) {
    try {
      const parsedUrl = url.parse(req.url, true);
      const pathname = parsedUrl.pathname;
      
      // Set CORS headers
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
      
      // Handle preflight requests
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Route requests
      if (pathname === '/health') {
        this.handleHealth(req, res);
      } else if (pathname === '/config') {
        await this.handleConfig(req, res);
      } else if (pathname === '/') {
        this.handleRoot(req, res);
      } else {
        this.sendResponse(res, 404, { error: 'Not found' });
      }

    } catch (error) {
      console.error('Error handling admin request:', error);
      this.sendResponse(res, 500, { error: 'Internal server error' });
    }
  }

  handleHealth(req, res) {
    this.sendResponse(res, 200, { 
      status: 'healthy', 
      timestamp: new Date().toISOString(),
      server: 'md-handler-admin'
    });
  }

  async handleConfig(req, res) {
    if (req.method === 'GET') {
      // Return current template variables
      this.sendResponse(res, 200, this.config.template);
    } else if (req.method === 'POST' || req.method === 'PUT') {
      // Update template variables in memory
      try {
        const body = await this.getRequestBody(req);
        const newConfig = JSON.parse(body);
        
        // Update the in-memory configuration
        this.config.template = { ...this.config.template, ...newConfig };
        
        // Update the file handler with new template variables
        updateTemplateConfig(this.config.template);
        
        console.log('Template variables updated in memory');
        this.sendResponse(res, 200, { 
          message: 'Template variables updated successfully',
          config: this.config.template 
        });
      } catch (error) {
        console.error('Error updating template variables:', error);
        this.sendResponse(res, 400, { error: 'Invalid template data' });
      }
    } else {
      this.sendResponse(res, 405, { error: 'Method not allowed' });
    }
  }

  handleRoot(req, res) {
    const html = `
<!DOCTYPE html>
<html>
<head>
  <title>MD Handler Admin</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; }
    .endpoint { margin: 20px 0; padding: 15px; border: 1px solid #ddd; }
    code { background: #f5f5f5; padding: 2px 4px; }
  </style>
</head>
<body>
  <h1>MD Handler Admin Server</h1>
  <p>Admin interface for managing template variables in memory.</p>
  
  <div class="endpoint">
    <h3>GET /health</h3>
    <p>Health check endpoint</p>
  </div>
  
  <div class="endpoint">
    <h3>GET /config</h3>
    <p>Get current template variables</p>
  </div>
  
  <div class="endpoint">
    <h3>POST /config</h3>
    <p>Update template variables (in memory only)</p>
  </div>
  
  <p>Template variables are managed in memory and reset on server restart.</p>
</body>
</html>`;
    
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(html);
  }

  async getRequestBody(req) {
    return new Promise((resolve, reject) => {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => resolve(body));
      req.on('error', reject);
    });
  }

  sendResponse(res, status, data) {
    const response = JSON.stringify(data, null, 2);
    res.writeHead(status, { 
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(response)
    });
    res.end(response);
  }

  async stop() {
    if (this.server) {
      return new Promise((resolve) => {
        this.server.close(() => {
          console.log('Admin server stopped');
          resolve();
        });
      });
    }
  }
}

/**
 * Main function
 */
async function main() {
  try {
    // Load configuration
    const adminConfig = new AdminConfig();
    const config = await adminConfig.load();

    // Create and start server
    const server = new AdminServer(config);
    await server.start();

    // Graceful shutdown
    process.on('SIGINT', async () => {
      console.log('\nReceived SIGINT, shutting down admin server gracefully...');
      await server.stop();
      process.exit(0);
    });

    process.on('SIGTERM', async () => {
      console.log('\nReceived SIGTERM, shutting down admin server gracefully...');
      await server.stop();
      process.exit(0);
    });

  } catch (error) {
    console.error('Failed to start admin server:', error);
    process.exit(1);
  }
}

// Start the server if this file is run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(console.error);
}

export { AdminServer, AdminConfig };