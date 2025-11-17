'use strict';

class UA {

  #config = {};
  #errors = [];
  #host = undefined;
  #ready = false;

  get config() {
    return this.#config;
  }

  set config(newConfig) {
    this.#config = newConfig;

    const select = $(`<select name="host" />`);
    select.append('<option value="" disabled selected>Select host...</option>');
    for (const hostIdx in this.config.hosts) {
      const host = this.config.hosts[hostIdx];
      const n = `${host.student} - ${host.origin}`;
      const option = $(`<option value="${hostIdx}">${n}</option>`);
      select.append(option);
    }
    $('label[for="host"]').after(select);
    select.on('change', event => {
      this.host = this.config.hosts[select.val()];
    });

    // TODO I'd like to use each part of this.config.hostSelectors as a
    // dimension
    // for (const s of this.config.hostSelectors) {
    //   let selector = s(`<select name="${s}"/>`)
    //   $('#host-selectors').append(selector);
    // }

    // for (const s of this.hosts) {
    //   for (const key of Object.keys(s)) {
        
    //   }
    // }

    $('select[name=method]').on('change', event => {
      this.uiState_requestBody();
    });

    // setup title
    if (this.config.app.title) {
      $('title').text(this.config.app.title);
      $('h1.headline').text(this.config.app.title);
    }

    // setup links
    const linkGroups = $('.links .link-groups');
    let currentLinkGroup = undefined;
    const linkGroup = (title) => {
      if (title || title === '') {
        currentLinkGroup = undefined;
      }
      if (currentLinkGroup === undefined) {
        if (title) {
          linkGroups.append($(`<h3>${title}</h3>`));
        }
        currentLinkGroup = $('<ul></ul>');
        linkGroups.append(currentLinkGroup);
      }
      return currentLinkGroup;
    }
    for (const link of this.config.links) {
      if (link.group || link.group === '') {
        linkGroup(link.group);
      } else if (link.title) {
        const li = $('<li></li>');
        if (link.href) {
          const a = $(
            `<a href="${link.href}" target="_blank">${link.title}</a>`
          );
          li.append(a);
        } else {
          li.text(link.title);
        }
        if (link.moreInfo) {
          let moreInfoDl = null;
          for (const info of link.moreInfo) {
            if (info.name) {
              if (!moreInfoDl) {
                moreInfoDl = $('<dl class="more-info"></dl>');
                li.append(moreInfoDl);
              }
              const dt = $(`<dt></dt>`);
              dt.text(info.name);
              moreInfoDl.append(dt);
              const dd = $(`<dd></dd>`);
              let ddSpan;
              let showText = info.value;
              if (info.monospace) {
                ddSpan = $(`<code></code>`);
              } else {
                ddSpan = $(`<span></span>`);
              }
              dd.append(ddSpan);
              if (info.isPassword) {
                dd.addClass('password');
                showText = info.value.substring(0, 3) +
                  "\u2022\u2022\u2022\u2022\u2022".substring(
                    0,
                    Math.min(5, Math.max(0, info.value.length - 3))
                  );
                dd.attr('data-password-visible', 'false');
                dd.attr('data-password', info.value);
              }
              ddSpan.text(showText);
              if (info.clipboard) {
                dd.addClass('clipboard');
                dd.on('click', function() {
                  let textToCopy = info.value;
                  navigator.clipboard.writeText(textToCopy).then(() => {
                    console.log('Copied to clipboard:', textToCopy);
                  }).catch(err => {
                    console.error('Failed to copy to clipboard:', err);
                  });
                  ddSpan.text('Copied!');
                  setTimeout(() => {
                    ddSpan.text(showText);
                  }, 1000);
                });
              }
              moreInfoDl.append(dd);
            } else {
              let textElem = $('<div></div>');
              if (info.monospace) {
                let codeElem = $(`<code></code>`).text(info.value);
                codeElem.addClass('more-info');
                textElem.append(codeElem);
              } else {
                textElem.text(info.value);
              }
              if (info.italic) {
                textElem.addClass('italic');
              }
              textElem.text(info.value);
              textElem.addClass('more-info');
              li.append(textElem);
            }
          }
        }
        linkGroup().append(li);
      }
    }
  }

  get host() {
    return this.#host;
  }

  set host(newHost) {
    console.log('setting host to', newHost);
    this.#host = newHost;
    const getHostSelectedDiv = () => {
      return $('#host-selected').first();
    }
    if (getHostSelectedDiv().length === 0) {
      $('select[name="host"]').after('<div id="host-selected"></div>');
    }
    const hostSelectedDiv = getHostSelectedDiv();
    hostSelectedDiv.text(this.#host?.baseUrl);
    this.uiState();
  }

  set ready(newReadiness) {
    this.#ready = newReadiness;
  }

  addHeaderField() {
    let newHeaderField =
      $('<div class="header-field-wrapper field-wrapper"></div>');
    let textField = $(
      '<input type="text" placeholder="Header: value content"></input>');
    textField.on('blur', () => {
      const value = textField.val();
      if (!value || /^([a-zA-Z0-9-]+):/.test(value)) {
        // non-empty but invalid header
        newHeaderField.removeClass('error');
      } else {
        newHeaderField.addClass('error');
      }
    });
    let removeButton = $('<button class="x">&times</button>');
    removeButton.on('click', () => {      
      newHeaderField.remove();
      this.uiState();
    });
    newHeaderField.append(textField);
    newHeaderField.append(removeButton);
    $('.additional-headers').append(newHeaderField);
  }

  addError(e) {
    this.#errors.push(e.message);
    let errorDiv = $('<div class="form-section error"/>');
    let errorText = typeof e === 'string' ? e : e.message;
    errorDiv.text(errorText);
    let ackButton = $(`<button class="error x">&times;</button>`);
    ackButton.on('click', () => {
      errorDiv.remove();
    });
    errorDiv.append(ackButton);
    $('h1.headline').before(errorDiv);
  }

  getHeaders() {
    let headers = {};
    if (this.isBodyable) {
      headers['Content-Type'] = [$('select[name="contentType"]').val()];
    }
    $('.header-field-wrapper input[type="text"]').each((i, e) => {
      const headerText = $(e).val();
      const header = headerText.replace(/:.*/, '');
      const value = headerText.replace(/^[^:]*:\s+/, '');
      if (headerText) {
        if (!headers[header]) {
          headers[header] = [];
        }
        headers[header].push(value);
      }
    });
    return headers;
  }

  init() {

    var captureRejectionMessages = promises => {
      promises.forEach(p => p && p.catch(e => {
        this.addError(e);
      }));
      return promises;
    };

    let configPromises = captureRejectionMessages([
      this.init_headers(),
      this.init_loadConfig(),
      this.init_controls()
    ]);

    Promise.all(configPromises)
      .then(() => {
        this.uiState();
      });

    // this.addError('Test <error/> message');
    // this.addError('Test <error/> really crazy long error message it was the best of times it was the worst of times it was a dark and stormy night');
  }

  init_controls() {
    $('button[name="send"]').on('click', () => { this.send(); });
  }

  init_headers() {
    $('button[name="add-header"]').on('click', event => {
      this.addHeaderField()
    });
    this.addHeaderField();
  }

  init_loadConfig() {
    return new Promise((resolve, reject) => {
      $.getJSON('/config/config.json')
      .done(data => {
        this.config = data;
        resolve();
      })
      .fail(e => {
        reject({
          code: 'config-fail',
          message: `Failed to load config`,
          detail: e
        });
      });  
    })
  }

  isBodyable() {
    return ['POST', 'PUT', 'PATCH'].includes(
      $('select[name=method]').first().val()
    );
  }

  send() {
    console.log('send');
    const headers = this.getHeaders();
    const requestHeaders = new Headers();
    for (const headername of Object.keys(headers)) {
      for (const value of headers[headername]) {
        requestHeaders.append(headername, value);
      }
    }
    const headersB64 = btoa(JSON.stringify(headers));
    const path = $('input[name="path"]').first().val().replace(/^\//, '');
    const fetchOpts = {
      method: $('select[name=method]').first().val(),
      headers: {
        'x-proxy-headers': headersB64
      },
      mode: 'cors',
      rejectUnauthorized: false
    };
    if (this.isBodyable()) {
      fetchOpts.body = $('textarea[name="body-content"]').first().val();
    }
    console.log('fetchOpts:', fetchOpts);
    const anxietyKiller = $('<span class="anxiety-killer"></span>');
    anxietyKiller.html('&middot;&nbsp;&middot;&nbsp;&middot;');
    $('button[name="send"]').after(anxietyKiller);
    $('.response-section').empty();
    fetch(
      '/proxy/' + this.host.student + '/' + this.host.origin + '/' + path,
      fetchOpts
    )
      .then(async res => {
        let responseString = '';
        console.log(res);
        res.headers.entries().forEach(h => {
          console.log('header', h);
        });
        $('#response-headers').append(
          $(`<p class="status">${res.headers.get('x-proxy-status')}</p>`)
        );
        const headers = JSON.parse(atob(res.headers.get('x-proxy-headers')));
        console.log('decoded headers', headers);
        for (const headerKey of Object.keys(headers)) {
          let v = headers[headerKey];
          if (!Array.isArray(v)) {
            v = [v];
          }
          for (const value of v) {
            const headerLine = $(`<div class="header"><span class="key">${
              headerKey}</span>: <span class="value">${value}</span></div>`);
            $('#response-headers').append(headerLine);
          }
        }
        const responsePre = $('<pre></pre>');
        responsePre.text(await res.text());
        $('#response-body').append(responsePre);
      })
      .catch(e => {
          console.log('exception', e);
        this.addError({
          code: 'fetch-fail',
          message: `Request failed`,
          detail: e
        });
        $('#response-headers').append(
          '<p class="error">Error: No response</p>'
        );
      })
      .finally(() => {
        $('#response-headers').prepend('<h2>Response</h2>');
        anxietyKiller.remove();
      });
  }

  uiState() {
    this.uiState_requestBody();
    this.uiState_sendButton();
  }

  uiState_requestBody() {
    const bodyFields =
      $('#request-body, .field-wrapper:has([name="contentType"])');
    if (this.isBodyable()) {
      bodyFields.show();
    } else {
      bodyFields.hide();
    }
  }

  uiState_sendButton() {
    let enabled=true;
    if (!this.host) {
      enabled=false;
    }
    $('button[name="send"]').prop('disabled', !enabled);
  }

}

const ua = new UA();
$.when($.ready).then(() => ua.init());
