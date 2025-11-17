'use strict';

import { searchDetail } from "./lib.js";

export default function gateway(config) {
  const route = searchDetail(
    config,
    'Route',
    'tools',
    {'jb-purpose': 'datapower-console'}
  );
  const secret = searchDetail(
    config,
    'Secret',
    'tools',
    'apim-demo-gw-admin'
  );
  return {
    datapower: {
      url: route?.spec?.host ? `https://${route.spec.host}` : null,
      username: "admin",
      password: secret?.data?.password || null
    }
  }
}
