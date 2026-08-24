'use strict';

// ponytail: public find/create/update for the hackathon; lock down with
// real roles/policies before this goes anywhere near prod.
const PUBLIC_ACTIONS = [
  'api::item.item.find',
  'api::item.item.findOne',
  'api::item.item.create',
  'api::item.item.update',
  'api::delta-event.delta-event.find',
  'api::delta-event.delta-event.findOne',
  'api::delta-event.delta-event.create',
  'api::delta-event.delta-event.update',
  'plugin::upload.content-api.upload',
];

module.exports = {
  register(/*{ strapi }*/) {},

  async bootstrap({ strapi }) {
    const publicRole = await strapi
      .query('plugin::users-permissions.role')
      .findOne({ where: { type: 'public' } });

    if (!publicRole) return;

    for (const action of PUBLIC_ACTIONS) {
      const existing = await strapi
        .query('plugin::users-permissions.permission')
        .findOne({ where: { action, role: publicRole.id } });

      if (!existing) {
        await strapi.query('plugin::users-permissions.permission').create({
          data: { action, role: publicRole.id },
        });
      }
    }
  },
};
