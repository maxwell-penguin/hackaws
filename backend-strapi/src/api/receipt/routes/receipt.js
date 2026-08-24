'use strict';

module.exports = {
  routes: [
    {
      method: 'POST',
      path: '/receipts',
      handler: 'receipt.upload',
      config: {
        auth: false,
        policies: [],
        middlewares: [],
      },
    },
  ],
};
