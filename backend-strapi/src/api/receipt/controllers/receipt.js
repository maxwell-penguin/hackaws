'use strict';

const fs = require('fs');
const path = require('path');

// ponytail: just persists the raw upload to disk and hands back the path.
// Gemini processing gets wired in separately.
module.exports = {
  async upload(ctx) {
    const uploaded = ctx.request.files?.file;
    const file = Array.isArray(uploaded) ? uploaded[0] : uploaded;

    if (!file) {
      return ctx.badRequest('No file uploaded. Send multipart/form-data with a "file" field.');
    }

    const tmpDir = path.join(strapi.dirs.app.root, 'tmp', 'receipts');
    fs.mkdirSync(tmpDir, { recursive: true });

    const filename = `${Date.now()}-${file.originalFilename || file.newFilename}`;
    const destPath = path.join(tmpDir, filename);
    fs.copyFileSync(file.filepath, destPath);

    ctx.body = { path: destPath };
  },
};
