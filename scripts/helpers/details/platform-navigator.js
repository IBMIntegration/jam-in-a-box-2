'use strict';

import { searchDetail } from "./lib.js";

export default function platformNavigator(config) {
  const route = searchDetail(
    config,
    'Route',
    'tools',
    'cp4i-navigator-pn'
  );
  const secret = searchDetail(
    config,
    'Secret',
    'ibm-common-services',
    'integration-admin-initial-temporary-credentials'
  );
  return {
    platformNavigator: {
      url: route?.spec?.host ? `https://${route.spec.host}` : null,
      username: secret?.data?.username || null,
      password: secret?.data?.password || null
    }
  }
}
