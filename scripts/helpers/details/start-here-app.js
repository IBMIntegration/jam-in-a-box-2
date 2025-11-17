'use strict';

import { searchDetail } from "./lib.js";

export default function startHereApp(config) {
  const route = searchDetail(
    config,
    'Route',
    'tools',
    'jb-start-here'
  );
  const secret = searchDetail(
    config,
    'Secret',
    'tools',
    'jb-start-here-app-credentials'
  );
  return {
    startHereApp: {
      url: route?.spec?.host ? `https://${route.spec.host}` : null,
      username: secret?.data?.username || null,
      password: secret?.data?.password || null
    }
  }
}
