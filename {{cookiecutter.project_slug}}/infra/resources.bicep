param name string
param location string
param resourceToken string
param principalId string
@secure()
param databasePassword string
@secure()
param djangoSecretKey string
param tags object

var prefix = '${name}-${resourceToken}'

var pgServerName = '${prefix}-postgres-server'
var databaseSubnetName = 'database-subnet'
var webappSubnetName = 'webapp-subnet'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: databaseSubnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: '${prefix}-subnet-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: webappSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: '${prefix}-subnet-delegation-web'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
  resource databaseSubnet 'subnets' existing = {
    name: databaseSubnetName
  }
  resource webappSubnet 'subnets' existing = {
    name: webappSubnetName
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${pgServerName}.private.postgres.database.azure.com'
  location: 'global'
  tags: tags
  dependsOn: [
    virtualNetwork
  ]
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${pgServerName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

var validStoragePrefix = take(replace(prefix, '-', ''), 17)

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: '${validStoragePrefix}storage'
  location: location
  kind: 'StorageV2'
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
}


resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
  name: '${storageAccount.name}/default/django'
  properties: {
    publicAccess: 'Blob'
  }
}

resource redisCache 'Microsoft.Cache/Redis@2020-06-01' = {
  name: '${prefix}-redis'
  location: location
  tags: tags
  properties: {
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    sku: {
      capacity: 1
      family: 'C'
      name: 'Basic'
    }
  }
}

resource Microsoft_Insights_diagnosticsettings_redisCacheName 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: redisCache
  name: redisCache.name
  properties: {
    storageAccountId: storageAccount.id
    metrics: [
      {
        timeGrain: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 90
          enabled: true
        }
      }
    ]
  }
}

resource web 'Microsoft.Web/sites@2022-03-01' = {
  name: '${prefix}-app-service'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      alwaysOn: true
      linuxFxVersion: 'PYTHON|3.9'
      ftpsState: 'Disabled'
      appCommandLine: 'python manage.py migrate && {% if cookiecutter.use_celery == 'y' -%} celery -A config.celery_app worker --loglevel=info --uid=65534 -B & {%- endif %} gunicorn --workers 2 --threads 4 --timeout 60 --access-logfile \'-\' --error-logfile \'-\' --bind=0.0.0.0:8000 --chdir=/home/site/wwwroot config.wsgi'
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }

  resource appSettings 'config' = {
    name: 'appsettings'
    properties: {
      DATABASE_URL: 'postgres://${postgresServer.properties.administratorLogin}:${databasePassword}@${postgresServer.properties.fullyQualifiedDomainName}/${djangoDatabase.name}'
      DJANGO_SETTINGS_MODULE: 'config.settings.production'
      DJANGO_DEBUG: 'False'
      DJANGO_SECRET_KEY: djangoSecretKey
      DJANGO_ALLOWED_HOSTS: web.properties.defaultHostName
      DJANGO_ADMIN_URL: 'admin${uniqueString(resourceGroup().id)}'
      REDIS_URL: 'rediss://:${redisCache.listKeys().primaryKey}@${redisCache.properties.hostName}:${redisCache.properties.sslPort}/0?ssl_cert_reqs=CERT_REQUIRED'
      {% if cookiecutter.use_celery == 'y' -%}
      CELERY_BROKER_URL: 'rediss://:${redisCache.listKeys().primaryKey}@${redisCache.properties.hostName}:${redisCache.properties.sslPort}/1?ssl_cert_reqs=CERT_REQUIRED'
      {% endif %}
      DJANGO_AZURE_ACCOUNT_NAME: storageAccount.name
      DJANGO_AZURE_ACCOUNT_KEY: storageAccount.listKeys().keys[0].value
      DJANGO_AZURE_CONTAINER_NAME: 'django'
      {%- if cookiecutter.mail_service == 'Mailgun' %}
      MAILGUN_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=MAILGUN-API-KEY)'
      MAILGUN_SENDER_DOMAIN: web.properties.defaultHostName
      {%- elif cookiecutter.mail_service == 'Mailjet' %}
      MAILJET_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=MAILJEY-API-KEY)'
      MAILJET_SECRET_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=MAILJEY-SECRET-KEY)'
      {%- elif cookiecutter.mail_service == 'Mandrill' %}
      MANDRILL_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=MANDRILL-API-KEY)'
      {%- elif cookiecutter.mail_service == 'Postmark' %}
      POSTMARK_SERVER_TOKEN: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=POSTMARK-SERVER-TOKEN)'
      {%- elif cookiecutter.mail_service == 'Sendgrid' %}
      # https://anymail.readthedocs.io/en/stable/esps/sendgrid/
      SENDGRID_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=SENDGRID-API-KEY)'
      {%- elif cookiecutter.mail_service == 'SendinBlue' %}
      SENDINBLUE_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=SENDINBLUE-API-KEY)'
      {%- elif cookiecutter.mail_service == 'SparkPost' %}
      SPARKPOST_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=SPARKPOST-API-KEY)'
      {%- endif %}
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      {%- if cookiecutter.frontend_pipeline == 'Gulp' %}
      POST_BUILD_COMMAND: 'npm install && npm run build'
      {%- endif %}
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }

  resource webappVnetConfig 'networkConfig' = {
    name: 'virtualNetwork'
    properties: {
      subnetResourceId: virtualNetwork::webappSubnet.id
    }
  }

  dependsOn: [virtualNetwork]

}

resource appServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: '${prefix}-service-plan'
  location: location
  tags: tags
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-03-01-preview' = {
  name: '${prefix}-workspace'
  location: location
  tags: tags
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2022-01-20-preview' = {
  location: location
  tags: tags
  name: pgServerName
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '13'
    administratorLogin: 'django'
    administratorLoginPassword: databasePassword
    availabilityZone: '1'
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: virtualNetwork::databaseSubnet.id
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
    highAvailability: {
      mode: 'Disabled'
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
      dayOfWeek: 0
      startHour: 0
      startMinute: 0
    }
  }

  dependsOn: [
    privateDnsZoneLink
  ]
}


resource djangoDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2022-01-20-preview' = {
  parent: postgresServer
  name: 'django'
}

var validKeyVaultPrefix = take(prefix, 17)
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${validKeyVaultPrefix}-vault'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    accessPolicies: [
      {
        objectId: principalId
        permissions: { secrets: [ 'get', 'list', 'set' ] }
        tenantId: subscription().tenantId
      }
      {
        objectId: web.identity.principalId
        permissions: { secrets: [ 'get'] }
        tenantId: web.identity.tenantId
      }
    ]
  }
}

resource databasePasswordSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'databasePassword'
  properties: {
    value: databasePassword
  }
}

resource djangoSecretKeySecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'djangoSecretKey'
  properties: {
    value: djangoSecretKey
  }
}


output WEB_URI string = 'https://${web.properties.defaultHostName}'
output AZURE_KEY_VAULT_NAME string = keyVault.name
