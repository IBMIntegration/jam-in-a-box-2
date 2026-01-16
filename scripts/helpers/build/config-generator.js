'use strict';

import { promises as fs } from 'fs';

const TITLE = 'Integration Jam In A Box';

const CONFIGFILES = [
  '/config/setup.json',
  '/config/secret.json'
];

async function readConfigFiles() {
  return Promise.all(
    CONFIGFILES.map(async filePath => {
      return JSON.parse(await fs.readFile(filePath, 'utf8'));
    })
  ).then(configs => [].concat(...configs));
}

console.log(JSON.stringify(await readConfigFiles(), null, 3));

async function generateConfigObj() {

  const configEntries = await readConfigFiles();

  const getResource = (kind, name, data) => {
    const resource = configEntries.find(entry => {
      return entry.kind === kind && entry.metadata.name === name;
    });
    let result = resource;

    if (!resource) {
      throw new Error(`Resource not found: ${kind} ${name}`);
    }

    if (data) {
      if (resource.data) {
        result = resource.data[data];
      }
      if (!result) {
        throw new Error(`Data not found: ${kind} ${name} ${data}`);
      }
    }

    return result;
  };

  const monospace = (name, value, isPassword) => {
    let result = {
      name, value, monospace: true, clipboard: true
    };
    if (isPassword) {
      result.isPassword = true;
    }
    return result;
  }
  const text = (value, isItalic) => {
    let result = { value };
    if (isItalic) {
      result.italic = true;
    }
    return result;
  }

  const out = {
    app: { title: TITLE },
    hosts: [],  // hosts for the rest client
    links: []   // links for user apps
  }

  let host, username, password;

  out.links.push({ group: 'Start Here' });

  // This app
  host = getResource('Route', 'integration');
  username = getResource('Secret', 'navigator-credentials', 'username');
  password = getResource('Secret', 'navigator-credentials', 'password');
  out.links.push({
    title: 'Lab Materials',
    href: `https://${host.spec.host}/tracks/`
  })
  out.links.push({
    title: 'This REST and URL Tool',
    href: `https://${host.spec.host}/`,
    moreInfo: [
      monospace('Username', username),
      monospace('Password', password, true)
    ]
  });

  // Platform navigator
  out.links.push({ group: 'Platform Navigator' });
  host = getResource('Route', 'cp4i-navigator-pn');
  username = getResource(
    'Secret', 'integration-admin-initial-temporary-credentials', 'username'
  );
  password = getResource(
    'Secret', 'integration-admin-initial-temporary-credentials', 'password'
  );
  out.links.push({
    title: 'Platform Navigator',
    href: `https://${host.spec.host}/`,
    moreInfo: [
      monospace('Username', username),
      monospace('Password', password, true),
    ]
  });
  // OpenShift Console
  host = getResource('Route', 'console');
  out.links.push({
    title: 'OpenShift Console',
    href: `https://${host.spec.host}/`
  });

  // DataPower Gateway
  out.links.push({ group: 'DataPower Gateway' });
  host = getResource('Route', 'apim-demo-gw-console');
  username = 'admin';
  password = getResource('Secret', 'apim-demo-gw-admin', 'password');
  out.links.push({
    title: 'DataPower Gateway Console',
    href: `https://${host.spec.host}/`,
    moreInfo: [
      monospace('Username', username),
      monospace('Password', password, true)
    ]
  });

  // API Connect
  out.links.push({ group: 'API Connect' });
  host = getResource('Route', 'apim-demo-mgmt-api-manager');
  username = 'admin';
  password = getResource('Secret', 'apim-demo-mgmt-admin-pass', 'password');
  out.links.push({
    title: 'Cloud Manager',
    moreInfo: [
      text('Link through Platform Navigator')
    ]
  });
  out.links.push({
    title: 'API Manager',
    href: `https://${host.spec.host}/`,
    moreInfo: [
      text('Cloud Pak User Registry'),
      text('Log in with Platform Navigator credentials', true)
    ]
  });

  // Supporting Services
  out.links.push({ group: 'Supporting services' });
  const mailpit = 'pipeline-mailpit-demo-output';
  host = getResource('ConfigMap', mailpit, 'mailpit-ui-url');
  username = getResource('ConfigMap', mailpit, 'mailpit-admin-username');
  password = getResource('ConfigMap', mailpit, 'mailpit-admin-password');
  const smtp = getResource('Service', 'mailpit-smtp');
  const smtpPort = 1025;
  const smtpIP = smtp.spec.clusterIP;

  out.links.push({
    title: 'Mailpit Web UI',
    href: host,
    moreInfo: [
      monospace('Username', username),
      monospace('Password', password, true),
      monospace('SMTP', `${smtpIP}:${smtpPort}`)
    ]
  });

  // Lab REST client routes
  let routes = configEntries.filter(entry => {
    return entry.kind === 'Route'
      && entry.metadata.annotations
      && entry.metadata.annotations['com.ibm.jam-in-a-box'] === 'lab';
  });
  if (routes.length > 0) {
    out.hosts = [];
    for (let route of routes) {
      let routeInfo = {
        baseUrl: `https://${route.spec.host}/`
      };
      // the ones used are:
      // name - the name to display in the menu
      // description - a description of the endpoint
      // more may be added later
      for (let annotation in route.metadata.annotations) {
        if (annotation.startsWith('com.ibm.jam-in-a-box.endpoint.')) {
          let key = annotation.replace('com.ibm.jam-in-a-box.endpoint.', '');
          routeInfo[key] = route.metadata.annotations[annotation];
        }
      }
      if (!routeInfo.service) {
        // calculate the service to proxy through if it's not already in the
        // annotations
        if (route.spec.to.kind === 'Service') {
          routeInfo.service = route.spec.to.name || null;
        }
        if (routeInfo.service !== null) {
          routeInfo.service = `${
            routeInfo.service}/${
            route.metadata.namespace}.svc.cluster.local`;
        }
      }
      if (!routeInfo.serviceProtocol) {
        // calculate the service protocol to proxy with if it's not already
        // in the annotations
        routeInfo.serviceProtocol = ['edge', 'passthrough']
          .includes(route.spec.tls?.termination)
            ? 'https'
            : 'http';
      }

      out.hosts.push(routeInfo);
    }
  }

  return out;
}

await fs.writeFile(
  '/config/generated/config.json',
  JSON.stringify(
    await generateConfigObj(),
    null,
    2
  ),
  'utf8'
);
