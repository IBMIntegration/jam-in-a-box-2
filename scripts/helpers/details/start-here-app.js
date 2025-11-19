'use strict';

import { searchDetail } from "./lib.js";

export default function startHereApp(config) {
  const route = searchDetail(
    config,
    'Route',
    'jam-in-a-box',
    'integration'
  );
  const secret = searchDetail(
    config,
    'Secret',
    'jam-in-a-box',
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
