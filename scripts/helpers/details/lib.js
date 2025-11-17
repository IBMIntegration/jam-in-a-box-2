'use strict';

// standard kubernetes kind synonyms
const kindSynonyms = {
  pod: ['po'],
  service: ['svc'],
  configmap: ['cm'],
  deployment: ['deploy'],
  namespace: ['ns'],
  persistentvolume: ['pv'],
  persistentvolumeclaim: ['pvc'],
  serviceaccount: ['sa'],
  ingress: ['ing'],
  node: ['no'],
  replicaset: ['rs'],
  daemonset: ['ds'],
  statefulset: ['sts'],
  cronjob: ['cj'],
  horizontalpodautoscaler: ['hpa'],
  networkpolicy: ['netpol'],
  endpoints: ['ep']
};

function normalizeKind(kind) {
  if (!kind) return null;
  
  // Step 1: Convert to lowercase
  let normalizedKind = kind.toLowerCase();
  
  // Step 2: Remove dot and everything after it
  if (normalizedKind.includes('.')) {
    normalizedKind = normalizedKind.split('.')[0];
  }
  
  // Step 3: Check if it's a key in kindSynonyms
  if (kindSynonyms.hasOwnProperty(normalizedKind)) {
    normalizedKind =
      normalizedKind.charAt(0).toUpperCase() + normalizedKind.slice(1);
  }
  
  // Step 4: Check if it's a value in kindSynonyms (find the key)
  for (const [standardKind, synonyms] of Object.entries(kindSynonyms)) {
    if (synonyms.includes(normalizedKind)) {
      normalizedKind =
        standardKind.charAt(0).toUpperCase() + standardKind.slice(1);
    }
  }
  
  // Step 5: Check if it ends with 's' and drop the 's'
  if (normalizedKind.endsWith('s') && normalizedKind.length > 1) {
    const withoutS = normalizedKind.slice(0, -1);
    
    // Check if the version without 's' is a key in kindSynonyms
    if (kindSynonyms.hasOwnProperty(withoutS)) {
      normalizedKind = withoutS.charAt(0).toUpperCase() + withoutS.slice(1);
    }
    
    // Check if the version without 's' is a value in kindSynonyms
    for (const [standardKind, synonyms] of Object.entries(kindSynonyms)) {
      if (synonyms.includes(withoutS)) {
        normalizedKind =
          standardKind.charAt(0).toUpperCase() + standardKind.slice(1);
      }
    }
  }
  
  return normalizedKind;
}

export function searchDetail(config, kind, namespace, selector) {
  kind = normalizeKind(kind);
  if (!config || !Array.isArray(config)) return null;
  return config.find(
    (item) => {
      if (typeof selector === 'string') {
        return normalizeKind(item.kind) === kind &&
          (namespace ? item.metadata?.namespace === namespace : true) &&
          (selector ? item.metadata?.name === selector : true)
      } else if (typeof selector === 'object' && selector !== null) {
        // selector is an object of labels
        const labels = item.metadata?.labels || {};
        const allMatch = Object.entries(selector).every(
          ([key, value]) => labels[key] === value
        );
        return normalizeKind(item.kind) === kind &&
          (namespace ? item.metadata?.namespace === namespace : true) &&
          allMatch;
      }
    }
  ) || null;
}
