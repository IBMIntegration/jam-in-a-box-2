'use strict';
import { promises as fs } from 'fs';
import path from 'path';
import MarkdownIt from 'markdown-it';
// TOC plugin for automatic table of contents
import markdownItTocDoneRight from 'markdown-it-toc-done-right';

const INCLUDES_DIR = path.join('/shared-includes', 'includes');
const INCLUDES = ['header', 'footer', 'head'];

/**
 * Reads a file from the include directory
 * @param {string} filename the name of the file without the `.html` extension
 * @returns {Promise<string>} the content of the include file
 */
async function includeHtml(filename) {
  if (!INCLUDES.includes(filename)) {
    throw new Error(`Include file "${filename}" is not recognized.`);
  }
  const filePath = path.join(INCLUDES_DIR, filename+'.html');
  try {
    return await fs.readFile(filePath, 'utf-8');
  } catch (error) {
    throw new Error(`Failed to read include file "${filename}": ${error.message}`);
  }
}


// Initialize markdown-it with default options
const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: true,
  xhtmlOut: true
});

// Add TOC plugin
md.use(markdownItTocDoneRight, {
  containerClass: 'table-of-contents',
  listType: 'ul',
  level: [1, 2, 3, 4, 5, 6],
  includeLevel: [1, 2, 3, 4, 5, 6],
  listClass: 'toc-list',
  itemClass: 'toc-item',
  linkClass: 'toc-link'
});

// Add custom heading renderer for automatic IDs
md.renderer.rules.heading_open = function (tokens, idx, options, env, renderer) {
  const token = tokens[idx];
  const level = token.tag;
  
  // Get the heading text from the next token (which should be inline)
  let headingText = '';
  if (tokens[idx + 1] && tokens[idx + 1].type === 'inline') {
    headingText = tokens[idx + 1].content;
  }
  
  // Generate slug from heading text
  const slug = generateSlug(headingText);
  
  // Add id attribute
  token.attrPush(['id', slug]);
  
  return renderer.renderToken(tokens, idx, options);
};

/**
 * Generates a URL-friendly slug from text
 * @param {string} text - The text to convert to a slug
 * @returns {string} URL-friendly slug
 */
function generateSlug(text) {
  return text
    .toLowerCase()                    // Convert to lowercase
    .trim()                          // Remove leading/trailing whitespace
    .replace(/[^\w\s-]/g, '')        // Remove special characters except spaces and hyphens
    .replace(/\s+/g, '-')            // Replace spaces with hyphens
    .replace(/-+/g, '-')             // Replace multiple hyphens with single hyphen
    .replace(/^-+|-+$/g, '');        // Remove leading/trailing hyphens
}

// Default template configuration
const defaultTemplateConfig = {
  variables: {
    title: "Document",
    author: "Unknown",
    date: new Date().toLocaleDateString(),
    version: "1.0.0",
    organization: "Your Organization"
  }
};

let templateConfig = { ...defaultTemplateConfig };

/**
 * Updates the template configuration (called from admin module)
 * @param {Object} config - New template configuration
 */
function updateTemplateConfig(config) {
  templateConfig = { ...defaultTemplateConfig, ...config };
}

/**
 * Gets the current template configuration
 * @returns {Object} Current template configuration
 */
function getTemplateConfig() {
  return templateConfig;
}

/**
 * Parses template variables from markdown content
 * Format: {{ name | default }} or {{ name }}
 * @param {string} content - Content with template variables
 * @returns {string} Content with variables replaced
 */
function parseTemplateVariables(content) {
  // Regex to match template variables: {{ name | default }} or {{ name }}
  // Handles whitespace and escaped braces in default values

  // we're gonna do this the hard way. Iterate character by character to
  // properly handle spaces, escaping, and braces.

  const outside = 0;
  const insideName = 1;
  const insideDefault = 2;
  let phase = outside;

  // last character if it's unescaped. escaped characters are not stored here.
  // anything in lastChar has not yet been added to output.
  let lastChar = '';
  let output = '';
  let name = null;
  let defaultValue = null;

  // resolve escapes and detect the second character of unescaped `{{` and `}}`
  const deEscape = (char) => {
    const result = { char: null, isDoubleBrace: false };
    if (lastChar === '\\') {
      lastChar = '';
      result.char = char;
    } else if (['{', '}'].includes(char)) {
      if (lastChar === char) {
        lastChar = '';
        result.char = char + char;
        result.isDoubleBrace = true;
      } else {
        result.char = lastChar;
        lastChar = char;
      }
    } else if (char === '\\') {
      result.char = '';
      lastChar = '\\';
    } else {
      result.char = lastChar + char;
      lastChar = '';
    }
    return result;
  }

  const isNil = (val) => val === null || val === undefined;

  const addValue = () => {
    let value = defaultValue === null
      ? {span: `<span class='failed-substitution'>${name}</span>`}
      : defaultValue;

    if (!isNil(templateConfig.variables[name])) {
      value = templateConfig.variables[name];
    }

    if (typeof value === 'object' && 'span' in value) {
      console.warn(`No value found for template variable "${name}"`);
      value = value.span.trim();
    }

    output += value.trim();
  }

  for (let i = 0; i < content.length; i++) {
    const char = content[i];
    let deEscaped;
    switch (phase) {
      case outside:
        deEscaped = deEscape(char);
        if (deEscaped.isDoubleBrace && deEscaped.char === '{{') {
          phase = insideName;
          name = '';
          lastChar = '';
        } else {
          output += deEscaped.char;
        }
        break;
      case insideName:
        // there is no escaping inside name
        if (char === '|') {
          name = name.trim();
          phase = insideDefault;
        } else if (char === '}') {
          // look ahead for second }
          if (i + 1 < content.length && content[i + 1] === '}') {
            name = name.trim();
            addValue();
            i++;
            phase = outside;
            name = null;
            defaultValue = null;
          } else {
            name += char;
          }
        } else {
          name += char;
        }
        break;
      case insideDefault:
        deEscaped = deEscape(char);
        if (deEscaped.isDoubleBrace && deEscaped.char === '}}') {
          defaultValue = defaultValue === null ? '' : defaultValue;
          addValue();
          phase = outside;
          name = null;
          defaultValue = null;
        } else {
          defaultValue =
            (defaultValue === null ? '' : defaultValue) + deEscaped.char;
        }
        break;
    }
  }
  return output;
}

/**
 * Resolves a file path and returns the file content with appropriate HTTP status
 * @param {string} requestPath - The requested path (relative to base directory)
 * @param {string} baseDirectory - The base directory to serve files from
 * @returns {Promise<{status: number, buffer: Buffer, contentType?: string}>}
 */
export async function resolveFile(requestPath, basePath) {
  try {
    // Normalize the request path
    const normalizedPath = path.normalize(requestPath);
    
    // Prevent directory traversal attacks
    if (normalizedPath.includes('..')) {
      return {
        status: 403,
        buffer: Buffer.from('Forbidden: Directory traversal not allowed')
      };
    }

    // Build the full file path
    let fullPath = path.join(basePath, normalizedPath);
    
    // Check if the path exists
    let stats;
    try {
      stats = await fs.stat(fullPath);
    } catch (error) {
      if (error.code === 'ENOENT') {
        // Don't return 404 here - continue to file reading logic which handles HTML->MD conversion
        stats = null;
      } else {
        throw error;
      }
    }

    // If it's a directory, look for index.html
    if (stats && stats.isDirectory()) {
      try {
        await fs.access(path.join(fullPath, 'index.html'));
      } catch (error) {
        if (error.code === 'ENOENT') {
          try {
            await fs.access(path.join(fullPath, 'index.md'));
          } catch (error) {
            if (error.code === 'ENOENT') {
              console.warn(
                'Directory index not found for',
                path.join(fullPath, 'index.[html|md]')
              );
              return {
                status: 404,
                buffer: Buffer.from('Directory index not found')
              };
            } else {
              throw error;
            }
          }
        } else {
          throw error;
        }
      }
      fullPath = path.join(fullPath, 'index.html')
    }

    // Try to read the requested file
    try {
      const fileBuffer = await fs.readFile(fullPath);
      const ext = path.extname(fullPath).toLowerCase();
      
      return {
        status: 200,
        buffer: fileBuffer,
        contentType: getContentType(ext)
      };
    } catch (error) {
      if (error.code === 'ENOENT') {
        // If it's an HTML file that doesn't exist, check for markdown
        if (path.extname(fullPath).toLowerCase() === '.html') {
          const markdownPath = fullPath.replace(/\.html?$/i, '.md');
          
          try {
            const markdownContent = await fs.readFile(markdownPath, 'utf8');
            // Process template variables before converting to HTML
            const processedMarkdown = parseTemplateVariables(markdownContent);
            const htmlContent = await convertMarkdownToHtml(
              processedMarkdown, path.basename(markdownPath, '.md')
            );
            
            return {
              status: 200,
              buffer: Buffer.from(htmlContent),
              contentType: 'text/html; charset=utf-8'
            };
          } catch (mdError) {
            if (mdError.code === 'ENOENT') {
              return {
                status: 404,
                buffer: Buffer.from('File not found')
              };
            }
            throw mdError;
          }
        }
        
        return {
          status: 404,
          buffer: Buffer.from('File not found')
        };
      }
      throw error;
    }
  } catch (error) {
    console.error('Error resolving file:', error);
    return {
      status: 500,
      buffer: Buffer.from('Internal server error')
    };
  }
}

/**
 * Converts markdown content to HTML with basic styling
 * @param {string} markdownContent - The markdown content to convert
 * @param {string} title - The title for the HTML page
 * @returns {string} Complete HTML document
 */
async function convertMarkdownToHtml(markdownContent, title = 'Document') {
  const htmlBody = md.render(markdownContent);
  
  // load these in parallel
  const neededIncludesPromises = {
    head: includeHtml('head'),
    header: includeHtml('header'),
    footer: includeHtml('footer')
  };

  console.log('HEAD:', await neededIncludesPromises.head);
  console.log('HEADER:', await neededIncludesPromises.header);
  console.log('FOOTER:', await neededIncludesPromises.footer);

  return `<!DOCTYPE html>
<html lang="en">
<head>
    ${await neededIncludesPromises.head}
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }
        pre {
            background: #f4f4f4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
        code {
            background: #f4f4f4;
            padding: 2px 4px;
            border-radius: 3px;
            font-family: Monaco, 'Courier New', monospace;
        }
        blockquote {
            border-left: 4px solid #ddd;
            margin: 0;
            padding-left: 20px;
            color: #666;
        }
        table {
            border-collapse: collapse;
            width: 100%;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        .failed-substitution {
            background-color: #ffebee;
            color: #c62828;
            padding: 2px 4px;
            border-radius: 3px;
            font-weight: bold;
            border: 1px solid #ef5350;
        }
        /* Table of Contents styling */
        .table-of-contents {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
            font-size: 0.95em;
        }
        .table-of-contents::before {
            content: "Table of Contents";
            display: block;
            font-weight: bold;
            font-size: 1.1em;
            color: #495057;
            margin-bottom: 15px;
            padding-bottom: 8px;
            border-bottom: 2px solid #dee2e6;
        }
        .toc-list {
            margin: 0;
            padding-left: 0;
            list-style: none;
        }
        .toc-list .toc-list {
            padding-left: 20px;
            margin-top: 5px;
        }
        .toc-item {
            margin: 8px 0;
            line-height: 1.4;
        }
        .toc-link {
            text-decoration: none;
            color: #007bff;
            display: block;
            padding: 4px 8px;
            border-radius: 4px;
            transition: all 0.2s ease;
        }
        .toc-link:hover {
            background-color: #e3f2fd;
            color: #0056b3;
            text-decoration: none;
        }
        /* Heading anchor links */
        h1:hover .header-anchor,
        h2:hover .header-anchor,
        h3:hover .header-anchor,
        h4:hover .header-anchor,
        h5:hover .header-anchor,
        h6:hover .header-anchor {
            opacity: 1;
        }
        .header-anchor {
            opacity: 0;
            transition: opacity 0.2s ease;
            margin-left: 8px;
            text-decoration: none;
            color: #6c757d;
        }
        .header-anchor:hover {
            color: #007bff;
        }
        /* Image styling */
        img {
            max-width: 100%;
            height: auto;
            cursor: pointer;
            transition: opacity 0.3s ease;
        }
        img:hover {
            opacity: 0.8;
        }
        /* Modal styles for image lightbox */
        .image-modal {
            display: none;
            position: fixed;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100%;
            height: 100%;
            background-color: rgba(0, 0, 0, 0.8);
            cursor: pointer;
            align-items: center;
            justify-content: center;
            padding: 2em;
            box-sizing: border-box;
        }
        .image-modal.show {
            display: flex;
        }
        .modal-content {
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
            cursor: pointer;
        }
        .close-modal {
            position: absolute;
            top: 15px;
            right: 35px;
            color: #fff;
            font-size: 40px;
            font-weight: bold;
            cursor: pointer;
            z-index: 1001;
            user-select: none;
            text-shadow: 0 0 10px rgba(0, 0, 0, 0.8);
        }
        .close-modal:hover {
            color: #ccc;
        }
    </style>
    <!-- jQuery CDN -->
    <script src="https://code.jquery.com/jquery-3.7.1.min.js" 
            integrity="sha256-/JqT3SQfawRcv/BIHPThkBvs0OEvtFFmqPF/lYI/Cxo=" 
            crossorigin="anonymous"></script>
</head>
<body>
    ${await neededIncludesPromises.header}
    ${htmlBody}
    
    <!-- Image modal for lightbox -->
    <div id="imageModal" class="image-modal">
        <span class="close-modal">&times;</span>
        <img class="modal-content" id="modalImage">
    </div>
    
    <script>
        $(document).ready(function() {
            // Image handling initialization
            initializeImageHandling();
        });
        
        function initializeImageHandling() {
            // Constrain all images to container width
            $('img').each(function() {
                const $img = $(this);
                
                // Set max-width constraint
                $img.css({
                    'max-width': '100%',
                    'height': 'auto'
                });
                
                // Add click event for lightbox
                $img.on('click', function(e) {
                    e.preventDefault();
                    openImageModal(this.src, this.alt);
                });
                
                // Add error handling
                $img.on('error', function() {
                    $(this).attr('alt', 'Image failed to load: ' + this.src);
                    console.warn('Failed to load image:', this.src);
                });
                
                // Add loading indicator
                $img.on('load', function() {
                    $(this).addClass('loaded');
                });
            });
            
            // Modal close events
            $('.close-modal, #imageModal').on('click', function() {
                closeImageModal();
            });
            
            // Click anywhere in modal to close (including the image)
            $('#modalImage').on('click', function() {
                closeImageModal();
            });
            
            // Keyboard support
            $(document).on('keydown', function(e) {
                if (e.key === 'Escape') {
                    closeImageModal();
                }
            });
        }
        
        function openImageModal(src, alt) {
            const $modal = $('#imageModal');
            const $modalImg = $('#modalImage');
            
            $modalImg.attr('src', src).attr('alt', alt || '');
            $modal.addClass('show');
            
            // Prevent body scroll
            $('body').css('overflow', 'hidden');
        }
        
        function closeImageModal() {
            const $modal = $('#imageModal');
            $modal.removeClass('show');
            
            // Restore body scroll
            $('body').css('overflow', '');
        }
    </script>
    ${await neededIncludesPromises.footer}
</body>
</html>`;
}

/**
 * Gets the appropriate Content-Type header for a file extension
 * @param {string} ext - File extension (including the dot)
 * @returns {string} Content-Type header value
 */
function getContentType(ext) {
  const contentTypes = {
    '.html': 'text/html; charset=utf-8',
    '.htm': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.txt': 'text/plain; charset=utf-8',
    '.md': 'text/markdown; charset=utf-8',
    '.pdf': 'application/pdf',
    '.zip': 'application/zip'
  };
  
  return contentTypes[ext] || 'application/octet-stream';
}

export {
  convertMarkdownToHtml,
  getContentType,
  updateTemplateConfig,
  getTemplateConfig,
  parseTemplateVariables
};

