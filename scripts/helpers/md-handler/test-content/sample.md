# {{ title | Sample Document }}

**Author:** {{ author | Anonymous }}  
**Date:** {{ date }}  
**Version:** {{ version | 1.0.0 }}  
**Organization:** {{ organization | Default Organization }}

---

## Introduction

This is a {{ document_type | technical }} document that demonstrates the template variable substitution feature. 

The document was created on {{ date }} by {{ author | an unknown author }}.

## Features

### Basic Variables

- Title: {{ title }}
- Author: {{ author }}
- Missing variable: {{ undefined_var }}

### Variables with Defaults

- Description: {{ description | This is a sample document with template variables }}
- Status: {{ status | Draft }}
- Priority: {{ priority | Normal }}

### Complex Defaults

Code example: {{ code_example | function hello() \{ console.log("Hello World!"); \} }}

Multi-line content:
{{ multi_line | Line 1
Line 2
  Indented line
    More indentation }}

### Whitespace Tests

Compact: {{compact_var|compact value}}
Spaced: {{ spaced_var | spaced value }}
Multi-line variable:
{{
  multi_line_var
  |
  Multi-line default value
}}

## Configuration

This document uses the following template variables:

- `title`: {{ title | Document Title }}
- `author`: {{ author | Document Author }}
- `date`: {{ date | Today's Date }}
- `version`: {{ version | 1.0.0 }}
- `organization`: {{ organization | Your Organization }}

Variables without defaults that aren't in config will show as errors: {{ missing_var }}

## Special Characters

Testing special characters in defaults:

- HTML: {{ html_example | <div class="example">Content</div> }}
- Symbols: {{ symbols | !@#$%^&*()_+-=[]{}|;:,.<>? }}
- Quotes: {{ quotes | "Single 'and' double quotes" }}

---

*Generated on {{ date }} by {{ organization }}*
