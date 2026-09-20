<?php

/**
 * Local development settings, copied into place by scripts/setup.sh.
 *
 * Edit the copy at web/sites/default/settings.local.php, not this template:
 * setup.sh only copies this file when the destination is absent, so local
 * edits survive a re-run of setup.sh.
 */

// Enable local development services (Twig debug on, Twig cache off). See
// assets/development.services.yml, copied to web/sites/development.services.yml.
$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';

// Disable CSS and JS aggregation.
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;

// Disable the render, page, and dynamic page caches for local development.
$settings['cache']['bins']['render'] = 'cache.backend.null';
$settings['cache']['bins']['page'] = 'cache.backend.null';
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

// Skip file system permissions hardening.
$settings['skip_permissions_hardening'] = TRUE;

// Exclude local-only modules from configuration synchronization, so a
// production config import never tries to enable them. See
// recipes/dev_tools/recipe.yml for what installs them locally.
$settings['config_exclude_modules'] = ['devel', 'environment_indicator_toolbar'];

// Environment indicator: local name and colours. Staging and production set
// their own name and colours the same way, in their own settings.local.php
// equivalent; environment_indicator itself is not in config_exclude_modules
// above, so the module stays enabled through the normal config export/import.
$config['environment_indicator.indicator']['name'] = 'Local';
$config['environment_indicator.indicator']['bg_color'] = '#0b6623';
$config['environment_indicator.indicator']['fg_color'] = '#ffffff';
