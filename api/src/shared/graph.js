'use strict';
const { DefaultAzureCredential } = require('@azure/identity');
const { Client } = require('@microsoft/microsoft-graph-client');
const { TokenCredentialAuthenticationProvider } = require('@microsoft/microsoft-graph-client/authProviders/azureTokenCredentials');

let _client = null;

function getGraphClient() {
  if (!_client) {
    const credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID || undefined,
    });
    const authProvider = new TokenCredentialAuthenticationProvider(credential, {
      scopes: ['https://graph.microsoft.com/.default'],
    });
    _client = Client.initWithMiddleware({ authProvider });
  }
  return _client;
}

module.exports = { getGraphClient };
