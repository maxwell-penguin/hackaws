'use strict';

const { createCoreService } = require('@strapi/strapi').factories;

module.exports = createCoreService('api::delta-event.delta-event');
