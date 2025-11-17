'use strict';

import { searchDetail } from "./lib.js";

export default function apim(config) {
  const route = searchDetail(
    config,
    'Route',
    'tools',
    'apim-demo-mgmt-api-manager'
  );
  const secret = searchDetail(
    config,
    'Secret',
    'tools',
    'apim-demo-mgmt-admin-pass'
  );
  return {
    platformNavigator: {
      url: route?.spec?.host ? `https://${route.spec.host}` : null,
      username: secret?.data?.email || null,
      password: secret?.data?.password || null
    }
  }
}
