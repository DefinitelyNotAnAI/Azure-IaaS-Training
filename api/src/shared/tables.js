'use strict';
const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

let _credential = null;

function getCredential() {
  if (!_credential) {
    _credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID || undefined,
    });
  }
  return _credential;
}

function getTableClient(tableName) {
  const accountName = process.env.STORAGE_ACCOUNT_NAME;
  if (!accountName) throw new Error('STORAGE_ACCOUNT_NAME is not configured');
  return new TableClient(
    `https://${accountName}.table.core.windows.net`,
    tableName,
    getCredential()
  );
}

module.exports = { getTableClient };
