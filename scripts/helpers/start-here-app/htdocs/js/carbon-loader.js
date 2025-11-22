/**
 * Carbon Component Loader Utility
 * Loads Carbon web components from IBM's CDN in parallel using Promise.all
 */

const carbonCDNBase = 'https://1.www.s81c.com/common/carbon/web-components/' +
  'tag/v2/latest/';

class CarbonComponentLoader {
  constructor() {
    this.loadedComponents = new Map();
    this.allOk = true;
  }

  #addHiddenStyle(name, level=0) {

    if (level > 5) {
      console.warn(`Max recursion level reached for adding hidden style: ${name}`);
      return;
    }
    
    const styleHeads = {
      'ui-shell': ['header', 'header-name']
    }
    if (Object.keys(styleHeads).includes(name)) {
      styleHeads[name].forEach(childName => {
        this.#addHiddenStyle(childName, level + 1);
      });
      return;
    }

    const selector = `cds-${name}:not(:defined)`;
    const rule = `${selector} { visibility: hidden; }`;
    
    // Check if style already exists
    const existingStyle = document.querySelector(`style[data-carbon-component="${name}"]`);
    if (existingStyle) {
      return;
    }
    
    const style = document.createElement('style');
    style.setAttribute('data-carbon-component', name);
    style.textContent = rule;
    document.head.appendChild(style);
  }

  /**
   * Load a single Carbon component
   * @param {string} name - The component name (e.g., 'dropdown', 'button')
   * @returns {Promise} Promise that resolves when component is loaded
   */
  #loadComponent(name) {

    // Check if component is already being loaded or has been loaded
    if (this.loadedComponents.has(name)) {
      return this.loadedComponents.get(name);
    }

    const src = this.#resolveSrc(name);

    const promise = new Promise((resolve, reject) => {
      // Add CSS to hide undefined component
      this.#addHiddenStyle(name);
      
      const script = document.createElement('script');
      script.src = src;
      script.type = 'module';
      script.onload = () => {
        resolve();
      };
      script.onerror = (e) => {
        this.allOk = false;
        console.error(`Failed to load component: ${name}:`, e);
        reject(new Error(`Failed to load component: ${name}: ${e.message}`));
      };
      document.head.appendChild(script);
    });

    this.loadedComponents.set(name, promise);
    return promise;
  }

  #resolveSrc(name) {
    return `${carbonCDNBase}${name}.min.js`;
  }

  /**
   * Convenience wrapper for loading a single component
   */
  loadComponent(name, onSuccess, onError) {
    return this.loadComponents(name, onSuccess, onError);
  }

  /**
   * Load multiple Carbon components in parallel
   * @param {string|string[]} components - Component name or array of component
   *  names
   * @param {Function} onSuccess - Callback when all components load successfully
   * @param {Function} onError - Callback when any component fails to load
   * @returns {Promise} Promise that resolves when all components are loaded
   */
  loadComponents(components, onSuccess, onError) {

    if (!Array.isArray(components)) {
      components = [components];
    }

    if (!components || components.length === 0) {
      console.log('No components to load');
      if (onSuccess) onSuccess();
      return Promise.resolve();
    }

    return Promise.all(components.map(name => this.#loadComponent(name)))
      .then(() => {
        console.log('All components loaded successfully!', components);
        if (onSuccess) onSuccess();
      })
      .catch(error => {
        console.error('Failed to load one or more components:', error);
        if (onError) {
          onError(error);
        } else {
          throw error;
        }
      });
  }

}

// Create global instance
window.carbonComponentLoader = new CarbonComponentLoader();

// Convenience function for quick loading
window.loadCarbonComponents = function(components, onSuccess, onError) {
  return window.carbonComponentLoader.loadComponents(
    components, onSuccess, onError
  );
};
