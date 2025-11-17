'use strict';

/**
 * URL Assistant - A configurable HTTP proxy server for educational environments
 * 
 * This server provides a proxy service that allows students to access backend services
 * through a unified interface. It supports:
 * 
 * - Multi-tenant routing based on student and origin identifiers
 * - Static file serving for the web interface
 * - Configuration-based backend URL mapping
 * - Header forwarding and authentication passthrough
 * - HTTPS backend support with certificate validation disabled
 * 
 * Configuration:
 * - Reads from CONFIG environment variable or 'public/config.json'
 * - Expected format: { hosts: [{ student, origin, baseUrl }, ...] }
 * 
 * Usage:
 * - Start with: node index.js
 * - Access UI at: http://localhost:3000/
 * - Proxy format: http://localhost:3000/proxy/{student}/{origin}/{path}
 * - Shutdown: GET http://localhost:3000/exit
 */

import fs from 'fs';
import https from 'https';
import http from 'http';
import path from 'path';

console.log('URL Assistant starting up:', process.argv);

// HTTPS agent that accepts self-signed certificates for development environments
const agent = new https.Agent({
  rejectUnauthorized: false
});

// Load configuration file (defaults to ./config.json)
const configFile = process.env.CONFIG || '/app/config.json';

// Parse the configuration containing host mappings
const config = JSON.parse(fs.readFileSync(configFile).toString());

/**
 * Serves as a proxy server that forwards requests to configured backend hosts.
 * 
 * Route format: /proxy/{student}/{origin}/{path}
 * - student: Identifier for the student/user
 * - origin: The backend service origin identifier
 * - path: The actual path to be proxied (optional, defaults to '/')
 * 
 * Features:
 * - URL mapping based on student and origin from config.hosts
 * - Header forwarding via x-proxy-headers (base64 encoded JSON)
 * - Basic authentication support
 * - Request body proxying for POST/PUT requests
 * - Response header and status code forwarding
 * - HTTPS agent with disabled certificate validation
 * 
 * @param {http.IncomingMessage} req - The incoming HTTP request
 * @param {http.ServerResponse} res - The HTTP response object
 * @returns {Promise<string>} A promise that resolves to a status string
 */
function serveProxy(req, res) {
	return new Promise((resolve, reject) => {
	  const method = req.method;
  	const urlMatch = req.url.match(new RegExp('/proxy/([^/]*)/([^/]*)(/.*)?$'));
	  const end = () => {
  		res.end();
  		resolve(`${res.statusCode} ${req.method} ${req.url}`);
	  }
  	if (!urlMatch) {
    	res.statusCode=400;
    	end();
    	return;
  	}
	  const student = urlMatch[1];
  	const origin = urlMatch[2];
  	const pathname = urlMatch[3] || '/';
  	const baseUrl = config.hosts.find(h => {
    	return (h.student === student) && (h.origin === origin);
	  })?.baseUrl;
  	if (!baseUrl) {
    	res.statusCode=400;
    	end();
  	  return;
	  }

	  const urlObj = new URL(baseUrl);

  	const headersHeader = req.headers['x-proxy-headers'];
	  const headers = headersHeader
	    ? JSON.parse(Buffer.from(headersHeader, 'base64').toString())
  	  : {};
  	const options = {
	    agent,
    	headers,
	    host: urlObj.host,
  	  method,
    	path: (urlObj.pathname === '/' ? '' : urlObj.pathname) + '/' +
      	(pathname.startsWith('/') ? pathname.slice(1) : pathname)
	  };
  	if (urlObj.username) {
    	if (urlObj.password) {
      	options.auth = `${urlObj.username}:${urlObj.password}`;
	    } else {
  	    options.auth = `${urlObj.username}:`;
    	}
  	}
	  if (urlObj.port) {
  	  options.port = urlObj.port;
  	}
  	options.headers.Host = urlObj.host;

	  const requestBodyChunks = [];
  	const requestBodyPromise = new Promise(r => {
    	req.on('data', d => {
      	requestBodyChunks.push(d.toString());
	    });
  	  req.on('end', () => {
    	  r();
    	});  
  	});

	  // proxied req
  	const preq = {http,https}[urlObj.protocol.replace(':','')].request(
    	options,
 	   (pres) => { // proxied res
  	    const chunks = [];
    	  pres.on('data', chunk => {
      	  chunks.push(chunk);
	      });
  	    pres.on('end', () => {
          res.headers ||= {};
    	    res.setHeader(
            'x-proxy-headers',
            Buffer.from(JSON.stringify(pres.headers)).toString('base64')
          );
          res.setHeader(
            'x-proxy-status',
            `${pres.statusCode} ${pres.statusMessage}`
          );
	        chunks.forEach(chunk => {
  	        res.write(chunk);
    	    });
		  	  end();
	      });
  	  });
	  preq.on('error', (e) => {
  	  res.status = 502;
    	console.log('Error in backend request:', e.message);
  	  end();
	  });

	  requestBodyPromise.then(() => {
  	  requestBodyChunks.forEach(c => {
    	  preq.write(c);
    	});
  	  preq.end();
	  });
	});
}

/**
 * Serves static files from the 'public' directory with content type detection.
 * 
 * Features:
 * - Maps root '/' to '/ua.html' 
 * - Supports HTML, JavaScript, and JSON content types
 * - Returns 404 for missing files
 * - Async file reading with promise-based error handling
 * 
 * Supported content types:
 * - .html -> text/html
 * - .js -> application/javascript  
 * - .json -> application/json
 * 
 * @param {http.IncomingMessage} req - The incoming HTTP request
 * @param {http.ServerResponse} res - The HTTP response object
 * @returns {Promise<string>} A promise that resolves to a status string
 */
async function servePublic(req, res) {
  const contentPromise = 
  	fs.promises.readFile(path.join('public', req.url === '/' ? '/ua.html' : req.url))  	
  const ext = req.url.split('.').pop();
  const contentType = {
    html: 'text/html',
    js: 'application/javascript',
    json: 'application/json'
  }[ext];
  if (contentType) {
    res.setHeader('Content-Type', contentType);
  }
  await contentPromise
  	.then(content => {
  		res.statusCode = 200;
  		res.write(content.toString());
  	})
  	.catch(e => {
	  	res.statusCode = 404;
  	});
  res.end();
  return `${res.statusCode} ${req.url}`;
}

/**
 * Redirect mapping for URL aliases.
 * Maps short URLs to their full paths for user convenience.
 */
const redirectMap = {
	'/': '/ua.html',
	'/ua': '/ua.html'
};

/**
 * Main HTTP server request handler that routes incoming requests to appropriate handlers.
 * 
 * Routes:
 * - /proxy/* -> serveProxy() - Proxy requests to backend services
 * - /config -> Returns the loaded configuration as JSON
 * - /exit -> Gracefully shuts down the server (returns 204)
 * - Redirect routes -> 302 redirects based on redirectMap
 * - All other routes -> servePublic() - Serves static files
 * 
 * All requests are logged with their type and result status.
 * 
 * @param {http.IncomingMessage} req - The incoming HTTP request
 * @param {http.ServerResponse} res - The HTTP response object
 */
const server = http.createServer(async (req, res) => {
	const result = []
  if (req.url.startsWith('/proxy/')) {
  	result.push('[ PROXY  ]');
    result.push(await serveProxy(req, res));
	} else if (req.url === '/config') {
		res.setHeader('Content-Type', 'application/json');
		res.write(JSON.stringify(config));
		res.end();
  } else if (Object.keys(redirectMap).includes(req.url)) {
    result.push('[REDIRECT]');
    const newUrl = redirectMap[req.url];
    result.push(`302 ${req.url} -> ${newUrl}`)
    res.writeHead(302, {Location: `${newUrl}`});
    res.end();
  } else if (req.url === '/exit') {
  	res.statusCode = 204;
  	res.end();
  	process.exit(0);
  } else {
    result.push('[ PUBLIC ]');
    result.push(await servePublic(req, res));
  }
  console.log(result.join(' '));
});

server.listen(3000, () => {
	console.log('URL Assistant listening on port 3000');
})
