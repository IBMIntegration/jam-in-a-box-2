'use strict';

import { searchDetail } from "./lib.js";

export default function OpenShiftConsole(config) {
  const route = searchDetail(
    config,
    'Route',
    'openshift-console',
    'console'
  );
  return {
    openShiftConsole: {
      url: route?.spec?.host ? `https://${route.spec.host}` : null
    }
  }
}
