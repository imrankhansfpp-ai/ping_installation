#!/bin/bash

# Script to execute all API calls from the Postman collection: Platform8 Setup - Current
# Assumes jq is installed for JSON parsing.
# Runs requests in sequence, extracting AdminSsoTokenId from the first login response.

set -euo pipefail

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }


# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env

HOST="http://${AM_HOSTNAME}:${TOMCAT_HTTP_PORT}"
ADMIN_TOKEN=""

# -----------------------------------------------------------------------------
# Function: am_admin_login
# Description: Logs in as amadmin and retrieves the session token.
# -----------------------------------------------------------------------------
function am_admin_login() {
info "Executing: AM - Amadmin login"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/authenticate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: resource=2.0, protocol=1" \
    -H "X-OpenAM-Username: amadmin" \
    -H "X-OpenAM-Password: password" \
    -d "{}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


    ADMIN_TOKEN=$(jq -r '.tokenId' "$RESPONSE_FILE")
    if [ -z "$ADMIN_TOKEN" ]; then
error "Error: Failed to get token from login response."


      cat "$RESPONSE_FILE"
echo
      rm "$RESPONSE_FILE"
      exit 1
    fi
    echo "AdminSsoTokenId set: $ADMIN_TOKEN"
  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
    rm "$RESPONSE_FILE"
    exit 1
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_alpha_realm
# Description: Creates the Alpha realm.
# -----------------------------------------------------------------------------
function create_alpha_realm() {
info "Executing: AM.- Create Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/global-config/realms?_action=create" \
    -H "Accept: application/json" \
    -H "Accept-Language: en-US,en;q=0.5" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "accept-api-version: protocol=2.0,resource=1.0" \
    -H "content-type: application/json" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d "{\"name\":\"alpha\",\"active\":true,\"parentPath\":\"/\",\"aliases\":[]}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: configure_alpha_realm_repo
# Description: Configures the identity repository for the Alpha realm.
# -----------------------------------------------------------------------------
function configure_alpha_realm_repo() {
info "Executing: AM - Configure Alpha Realm Repo"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/id-repositories/LDAPv3ForOpenDS/OpenDJ" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=2.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "_id": "OpenDJ",
    "ldapsettings": {
        "openam-idrepo-ldapv3-mtls-enabled": false,
        "openam-idrepo-ldapv3-heartbeat-timeunit": "SECONDS",
        "sun-idrepo-ldapv3-config-connection_pool_min_size": 1,
        "sun-idrepo-ldapv3-config-search-scope": "SCOPE_ONE",
        "openam-idrepo-ldapv3-proxied-auth-enabled": false,
        "openam-idrepo-ldapv3-contains-iot-identities-enriched-as-oauth2client": false,
        "sun-idrepo-ldapv3-config-max-result": 1000,
        "sun-idrepo-ldapv3-config-organization_name": "ou=identities",
        "openam-idrepo-ldapv3-proxied-auth-denied-fallback": false,
        "openam-idrepo-ldapv3-affinity-enabled": false,
        "sun-idrepo-ldapv3-config-authid": "uid=am-identity-bind-account,ou=admins,ou=identities",
        "openam-idrepo-ldapv3-heartbeat-interval": 10,
        "sun-idrepo-ldapv3-config-trust-all-server-certificates": false,
        "sun-idrepo-ldapv3-config-connection-mode": "LDAPS",
        "openam-idrepo-ldapv3-affinity-level": "all",
        "openam-idrepo-ldapv3-keepalive-searchfilter": "(objectclass=*)",
        "openam-idrepo-ldapv3-behera-support-enabled": true,
        "sun-idrepo-ldapv3-config-ldap-server": [
            "'"$DS_IDREPO_SERVER"':'"$DS_IDREPO_SERVER_LDAPS_PORT"'"
        ],
        "sun-idrepo-ldapv3-config-time-limit": 10,
        "sun-idrepo-ldapv3-config-connection_pool_max_size": 10
    },
    "userconfig": {
        "sun-idrepo-ldapv3-config-users-search-filter": "(objectclass=inetorgperson)",
        "sun-idrepo-ldapv3-config-inactive": "Inactive",
        "sun-idrepo-ldapv3-config-user-objectclass": [
            "iplanet-am-managed-person",
            "inetuser",
            "sunFMSAML2NameIdentifier",
            "inetorgperson",
            "devicePrintProfilesContainer",
            "boundDevicesContainer",
            "iplanet-am-user-service",
            "iPlanetPreferences",
            "pushDeviceProfilesContainer",
            "forgerock-am-dashboard-service",
            "organizationalperson",
            "top",
            "kbaInfoContainer",
            "person",
            "sunAMAuthAccountLockout",
            "oathDeviceProfilesContainer",
            "webauthnDeviceProfilesContainer",
            "iplanet-am-auth-configuration-service",
            "deviceProfilesContainer"
        ],
        "sun-idrepo-ldapv3-config-users-search-attribute": "fr-idm-uuid",
        "sun-idrepo-ldapv3-config-auth-kba-attempts-attr": [
            "kbaInfoAttempts"
        ],
        "sun-idrepo-ldapv3-config-auth-kba-attr": [
            "kbaInfo"
        ],
        "sun-idrepo-ldapv3-config-auth-kba-index-attr": "kbaActiveIndex",
        "sun-idrepo-ldapv3-config-people-container-value": "people",
        "sun-idrepo-ldapv3-config-isactive": "inetuserstatus",
        "sun-idrepo-ldapv3-config-people-container-name": "ou",
        "sun-idrepo-ldapv3-config-active": "Active",
        "sun-idrepo-ldapv3-config-createuser-attr-mapping": [
            "cn",
            "sn"
        ],
        "sun-idrepo-ldapv3-config-user-attributes": [
            "iplanet-am-auth-configuration",
            "iplanet-am-user-alias-list",
            "iplanet-am-user-password-reset-question-answer",
            "mail",
            "assignedDashboard",
            "authorityRevocationList",
            "dn",
            "iplanet-am-user-password-reset-options",
            "employeeNumber",
            "createTimestamp",
            "kbaActiveIndex",
            "caCertificate",
            "iplanet-am-session-quota-limit",
            "iplanet-am-user-auth-config",
            "sun-fm-saml2-nameid-infokey",
            "sunIdentityMSISDNNumber",
            "iplanet-am-user-password-reset-force-reset",
            "sunAMAuthInvalidAttemptsData",
            "devicePrintProfiles",
            "givenName",
            "iplanet-am-session-get-valid-sessions",
            "objectClass",
            "adminRole",
            "inetUserHttpURL",
            "lastEmailSent",
            "iplanet-am-user-account-life",
            "postalAddress",
            "userCertificate",
            "preferredtimezone",
            "iplanet-am-user-admin-start-dn",
            "boundDevices",
            "oath2faEnabled",
            "preferredlanguage",
            "sun-fm-saml2-nameid-info",
            "userPassword",
            "iplanet-am-session-service-status",
            "telephoneNumber",
            "iplanet-am-session-max-idle-time",
            "distinguishedName",
            "iplanet-am-session-destroy-sessions",
            "kbaInfoAttempts",
            "modifyTimestamp",
            "uid",
            "iplanet-am-user-success-url",
            "iplanet-am-user-auth-modules",
            "kbaInfo",
            "memberOf",
            "sn",
            "preferredLocale",
            "manager",
            "iplanet-am-session-max-session-time",
            "deviceProfiles",
            "cn",
            "oathDeviceProfiles",
            "webauthnDeviceProfiles",
            "iplanet-am-user-login-status",
            "pushDeviceProfiles",
            "push2faEnabled",
            "inetUserStatus",
            "retryLimitNodeCount",
            "iplanet-am-user-failure-url",
            "iplanet-am-session-max-caching-time"
        ]
    },
    "groupconfig": {
        "sun-idrepo-ldapv3-config-group-attributes": [
            "dn",
            "cn",
            "uniqueMember",
            "objectclass"
        ],
        "sun-idrepo-ldapv3-config-groups-search-attribute": "cn",
        "sun-idrepo-ldapv3-config-memberurl": "memberUrl",
        "sun-idrepo-ldapv3-config-group-container-name": "ou",
        "sun-idrepo-ldapv3-config-group-objectclass": [
            "top",
            "groupofuniquenames"
        ],
        "sun-idrepo-ldapv3-config-uniquemember": "uniqueMember",
        "sun-idrepo-ldapv3-config-groups-search-filter": "(objectclass=groupOfUniqueNames)",
        "sun-idrepo-ldapv3-config-group-container-value": "groups"
    },
    "errorhandling": {
        "com.iplanet.am.ldap.connection.delay.between.retries": 1000
    },
    "pluginconfig": {
        "sunIdRepoAttributeMapping": [],
        "sunIdRepoSupportedOperations": [
            "realm=read,create,edit,delete,service",
            "user=read,create,edit,delete,service",
            "group=read,create,edit,delete"
        ],
        "sunIdRepoClass": "org.forgerock.openam.idrepo.ldap.DJLDAPv3Repo"
    },
    "authentication": {
        "sun-idrepo-ldapv3-config-auth-naming-attr": "uid"
    },
    "persistentsearch": {
        "sun-idrepo-ldapv3-config-psearch-filter": "(!(objectclass=frCoreToken))",
        "sun-idrepo-ldapv3-config-psearchbase": "ou=identities",
        "sun-idrepo-ldapv3-config-psearch-scope": "SCOPE_SUB"
    },
    "cachecontrol": {
        "sun-idrepo-ldapv3-dncache-enabled": true,
        "sun-idrepo-ldapv3-dncache-size": 1500
    },
    "_type": {
        "_id": "LDAPv3ForOpenDS",
        "name": "OpenDJ",
        "collection": true
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: delete_opendj_top_level
# Description: Deletes the OpenDJ configuration in the top level realm.
# -----------------------------------------------------------------------------
function delete_opendj_top_level() {
info "Executing: Delete the configuration for OpenDJ in Top Level Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X DELETE \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/services/id-repositories/LDAPv3ForOpenDS/OpenDJ" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=2.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -H "Priority: u=0")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_idm_resource_server
# Description: Creates the idm-resource-server OAuth2 client.
# -----------------------------------------------------------------------------
function create_idm_resource_server() {
info "Executing: Create idm-resource-server"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/agents/OAuth2Client/idm-resource-server" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=2.0,resource=1.0" \
    -H "If-None-Match: *" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d "{\"coreOAuth2ClientConfig\":{\"defaultScopes\":[],\"redirectionUris\":[],\"scopes\":[\"am-introspect-all-tokens\",\"am-introspect-all-tokens-any-realm\"],\"userpassword\":\"password\"}}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_idm_provisioning
# Description: Creates the idm-provisioning OAuth2 client in the Alpha realm.
# -----------------------------------------------------------------------------
function create_idm_provisioning() {
info "Executing: Create idm-provisioning"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/agents/OAuth2Client/idm-provisioning" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: ForgeRock Identity Cloud Postman Collection" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
  "coreOAuth2ClientConfig": {
    "agentgroup": "",
    "status": {
      "inherited": false,
      "value": "Active"
    },
    "userpassword": "openidm",
    "clientType": {
      "inherited": false,
      "value": "Confidential"
    },
    "loopbackInterfaceRedirection": {
      "inherited": true,
      "value": true
    },
    "redirectionUris": {
      "inherited": false,
      "value": []
    },
    "scopes": {
      "inherited": false,
      "value": [
        "fr:idm:*"
      ]
    },
    "defaultScopes": {
      "inherited": false,
      "value": []
    },
    "clientName": {
      "inherited": false,
      "value": [
        "idm-provisioning"
      ]
    },
    "authorizationCodeLifetime": {
      "inherited": true,
      "value": 0
    },
    "refreshTokenLifetime": {
      "inherited": true,
      "value": 0
    },
    "accessTokenLifetime": {
      "inherited": true,
      "value": 0
    }
  },
  "advancedOAuth2ClientConfig": {
    "grantTypes": {
      "inherited": false,
      "value": [
        "client_credentials"
      ]
    },
    "tokenEndpointAuthMethod": {
      "inherited": false,
      "value": "client_secret_basic"
    },
    "isConsentImplied": {
      "inherited": false,
      "value": false
    }
  }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_idm_admin_ui_alpha
# Description: Creates the idm-admin-ui OAuth2 client in the Alpha realm.
# -----------------------------------------------------------------------------
function create_idm_admin_ui_alpha() {
info "Executing: Create idm-admin-ui Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/agents/OAuth2Client/idm-admin-ui" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: ForgeRock Identity Cloud Postman Collection" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "coreOAuth2ClientConfig": {
        "agentgroup": "",
        "status": {
            "inherited": false,
            "value": "Active"
        },
        "clientType": {
            "inherited": false,
            "value": "Public"
        },
        "loopbackInterfaceRedirection": {
            "inherited": true,
            "value": true
        },
        "redirectionUris": {
            "inherited": false,
            "value": [
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/platform/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/platform/sessionCheck.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/admin/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/admin/sessionCheck.html",
                "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/appAuthHelperRedirect.html",
                "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/admin/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/admin/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform-ui/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform-ui/sessionCheck.html"
            ]
        },
        "scopes": {
            "inherited": false,
            "value": [
                "openid",
                "fr:idm:*"
            ]
        },
        "defaultScopes": {
            "inherited": false,
            "value": []
        },
        "clientName": {
            "inherited": false,
            "value": [
                "idm-admin-ui"
            ]
        },
        "authorizationCodeLifetime": {
            "inherited": true,
            "value": 0
        },
        "refreshTokenLifetime": {
            "inherited": true,
            "value": 0
        },
        "accessTokenLifetime": {
            "inherited": true,
            "value": 0
        }
    },
    "advancedOAuth2ClientConfig": {
        "grantTypes": {
            "inherited": false,
            "value": [
                "authorization_code",
                "implicit"
            ]
        },
        "tokenEndpointAuthMethod": {
            "inherited": false,
            "value": "none"
        },
        "isConsentImplied": {
            "inherited": false,
            "value": true
        }
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_idm_admin_ui_root
# Description: Creates the idm-admin-ui OAuth2 client in the root realm.
# -----------------------------------------------------------------------------
function create_idm_admin_ui_root() {
info "Executing: Create idm-admin-ui Root Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/agents/OAuth2Client/idm-admin-ui" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: ForgeRock Identity Cloud Postman Collection" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "coreOAuth2ClientConfig": {
        "agentgroup": "",
        "status": {
            "inherited": false,
            "value": "Active"
        },
        "clientType": {
            "inherited": false,
            "value": "Public"
        },
        "loopbackInterfaceRedirection": {
            "inherited": true,
            "value": true
        },
        "redirectionUris": {
            "inherited": false,
            "value": [
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/platform/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/platform/sessionCheck.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/admin/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/admin/sessionCheck.html",
                "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/appAuthHelperRedirect.html",
                "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/admin/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/admin/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform-ui/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform-ui/sessionCheck.html"
            ]
        },
        "scopes": {
            "inherited": false,
            "value": [
                "openid",
                "fr:idm:*"
            ]
        },
        "defaultScopes": {
            "inherited": false,
            "value": []
        },
        "clientName": {
            "inherited": false,
            "value": [
                "idm-admin-ui"
            ]
        },
        "authorizationCodeLifetime": {
            "inherited": true,
            "value": 0
        },
        "refreshTokenLifetime": {
            "inherited": true,
            "value": 0
        },
        "accessTokenLifetime": {
            "inherited": true,
            "value": 0
        }
    },
    "advancedOAuth2ClientConfig": {
        "grantTypes": {
            "inherited": false,
            "value": [
                "authorization_code",
                "implicit"
            ]
        },
        "tokenEndpointAuthMethod": {
            "inherited": false,
            "value": "none"
        },
        "isConsentImplied": {
            "inherited": false,
            "value": true
        }
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_end_user_ui_alpha
# Description: Creates the end-user-ui OAuth2 client in the Alpha realm.
# -----------------------------------------------------------------------------
function create_end_user_ui_alpha() {
info "Executing: Create end-user-ui Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/agents/OAuth2Client/end-user-ui" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: ForgeRock Identity Cloud Postman Collection" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "coreOAuth2ClientConfig": {
        "agentgroup": "",
        "status": {
            "inherited": false,
            "value": "Active"
        },
        "clientType": {
            "inherited": false,
            "value": "Public"
        },
        "loopbackInterfaceRedirection": {
            "inherited": true,
            "value": true
        },
        "redirectionUris": {
            "inherited": false,
            "value": [
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/enduser-ui/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/enduser-ui/sessionCheck.html",
                "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/appAuthHelperRedirect.html",
                "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/enduser-ui/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/enduser-ui/sessionCheck.html"
            ]
        },
        "scopes": {
            "inherited": false,
            "value": [
                "openid",
                "fr:idm:*"
            ]
        },
        "defaultScopes": {
            "inherited": false,
            "value": []
        },
        "clientName": {
            "inherited": false,
            "value": [
                "end-user-ui"
            ]
        },
        "authorizationCodeLifetime": {
            "inherited": true,
            "value": 0
        },
        "refreshTokenLifetime": {
            "inherited": true,
            "value": 0
        },
        "accessTokenLifetime": {
            "inherited": true,
            "value": 0
        }
    },
    "advancedOAuth2ClientConfig": {
        "grantTypes": {
            "inherited": false,
            "value": [
                "authorization_code",
                "implicit"
            ]
        },
        "tokenEndpointAuthMethod": {
            "inherited": false,
            "value": "none"
        },
        "isConsentImplied": {
            "inherited": false,
            "value": true
        }
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_end_user_ui_root
# Description: Creates the end-user-ui OAuth2 client in the root realm.
# -----------------------------------------------------------------------------
function create_end_user_ui_root() {
info "Executing: Create end-user-ui Root Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/agents/OAuth2Client/end-user-ui" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: ForgeRock Identity Cloud Postman Collection" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "coreOAuth2ClientConfig": {
        "agentgroup": "",
        "status": {
            "inherited": false,
            "value": "Active"
        },
        "clientType": {
            "inherited": false,
            "value": "Public"
        },
        "loopbackInterfaceRedirection": {
            "inherited": true,
            "value": true
        },
        "redirectionUris": {
            "inherited": false,
            "value": [
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/enduser-ui/appAuthHelperRedirect.html",
                "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/enduser-ui/sessionCheck.html",
                "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/appAuthHelperRedirect.html",
                "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/sessionCheck.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/enduser-ui/appAuthHelperRedirect.html",
                "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/enduser-ui/sessionCheck.html"
            ]
        },
        "scopes": {
            "inherited": false,
            "value": [
                "openid",
                "fr:idm:*"
            ]
        },
        "defaultScopes": {
            "inherited": false,
            "value": []
        },
        "clientName": {
            "inherited": false,
            "value": [
                "end-user-ui"
            ]
        },
        "authorizationCodeLifetime": {
            "inherited": true,
            "value": 0
        },
        "refreshTokenLifetime": {
            "inherited": true,
            "value": 0
        },
        "accessTokenLifetime": {
            "inherited": true,
            "value": 0
        }
    },
    "advancedOAuth2ClientConfig": {
        "grantTypes": {
            "inherited": false,
            "value": [
                "authorization_code",
                "implicit"
            ]
        },
        "tokenEndpointAuthMethod": {
            "inherited": false,
            "value": "none"
        },
        "isConsentImplied": {
            "inherited": false,
            "value": true
        }
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

function configure_idm_integration_service() {
info "Executing: Configure IdmIntegrationService"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/global-config/services/idm-integration" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d "{\"configurationCacheDuration\":0,\"provisioningEncryptionKeyAlias\":\"\",\"provisioningSigningKeyAlias\":\"\",\"jwtSigningCompatibilityMode\":false,\"provisioningEncryptionAlgorithm\":\"\",\"idmDeploymentPath\":\"openidm\",\"idmDeploymentUrl\":\"http://${IDM_HOSTNAME}:${BOOT_PORT_HTTP}\",\"idmProvisioningClient\":\"idm-provisioning\",\"provisioningSigningAlgorithm\":\"\",\"provisioningEncryptionMethod\":\"\",\"useInternalOAuth2Provider\":false,\"enabled\":true,\"provisioningClientScopes\":[\"fr:idm:*\"],\"_id\":\"\",\"_type\":{\"_id\":\"idm-integration\",\"name\":\"IdmIntegrationService\",\"collection\":false}}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: configure_validation_service_root
# Description: Configures the validation service in the root realm.
# -----------------------------------------------------------------------------
function configure_validation_service_root() {
info "Executing: Configure Validation Service Root Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/services/validation?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "validGotoDestinations": [
        "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/*",
        "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/*?*",
        "http://'"$LOGIN_HOSTNAME"':'"$LOGIN_PORT"'/*",
        "http://'"$LOGIN_HOSTNAME"':'"$LOGIN_PORT"'/*?*",
        "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/*",
        "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/*?*",
        "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/*",
        "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/*?*",
        "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/*",
        "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/*?*"
    ]
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: configure_validation_service_alpha
# Description: Configures the validation service in the Alpha realm.
# -----------------------------------------------------------------------------
function configure_validation_service_alpha() {
info "Executing: Configure Validation Service Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/validation?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "validGotoDestinations": [
        "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/*",
        "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'/*?*",
        "http://'"$LOGIN_HOSTNAME"':'"$LOGIN_PORT"'/*",
        "http://'"$LOGIN_HOSTNAME"':'"$LOGIN_PORT"'/*?*",
        "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/*",
        "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'/*?*",
        "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/*",
        "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/*?*",
        "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/*",
        "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'/*?*"
    ]
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_cors_service
# Description: Creates the CORS service configuration.
# -----------------------------------------------------------------------------
function create_cors_service() {
info "Executing: Create CORS Service"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/global-config/services/CorsService/configuration?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "acceptedHeaders": [
      "accept-api-version",
      "authorization",
      "cache-control",
      "content-type",
      "if-match",
      "if-none-match",
      "user-agent",
      "x-forgerock-transactionid",
      "x-openidm-nosession",
      "x-openidm-password",
      "x-openidm-username",
      "x-requested-with"
    ],
    "exposedHeaders": [
      "WWW-Authenticate"
    ],
    "acceptedMethods": [
      "DELETE", "GET", "HEAD", "PATCH", "POST", "PUT"
    ],
    "acceptedOrigins": [
      "http://'"$LOGIN_HOSTNAME"':'"$LOGIN_PORT"'",
      "http://'"$ADMIN_HOSTNAME"':'"$ADMIN_PORT"'",
      "http://'"$ENDUSER_HOSTNAME"':'"$ENDUSER_PORT"'",
      "http://'"$IDM_HOSTNAME"':'"$BOOT_PORT_HTTP"'",
      "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'"
    ],
    "maxAge": 600,
    "allowCredentials": true,
    "enabled": true,
    "_id": "Cors Configuration"
  }')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: set_external_login_root
# Description: Sets the external login page URL in the root realm.
# -----------------------------------------------------------------------------
function set_external_login_root() {
info "Executing: Set External Login Page URL Root Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/authentication" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "twoFactorRequired": false,
    "defaultAuthLevel": 0,
    "userStatusCallbackPlugins": [],
    "identityType": [
        "agent",
        "user"
    ],
    "externalLoginPageUrl": "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'/platform-login",
    "statelessSessionsEnabled": false,
    "locale": "en_US"
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: set_external_login_alpha
# Description: Sets the external login page URL in the Alpha realm.
# -----------------------------------------------------------------------------
function set_external_login_alpha() {
info "Executing: Set External Login Page URL Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/authentication" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "twoFactorRequired": false,
    "defaultAuthLevel": 0,
    "userStatusCallbackPlugins": [],
    "identityType": [
        "agent",
        "user"
    ],
    "externalLoginPageUrl": "",
    "statelessSessionsEnabled": false,
    "locale": "en_US"
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: map_self_service_trees
# Description: Maps self-service trees in the Alpha realm.
# -----------------------------------------------------------------------------
function map_self_service_trees() {
info "Executing: Map Self Service Trees"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/selfServiceTrees?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "treeMapping": {
        "registration": "PlatformRegistration",
        "login": "PlatformLogin",
        "resetPassword": "PlatformResetPassword"
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: set_am_cookie_domain
# Description: Sets the AM cookie domain for the platform.
# -----------------------------------------------------------------------------
function set_am_cookie_domain() {
info "Executing: Set AM Cookie Domain for platform"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/global-config/services/platform" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "cookieDomains": [
        "'"$COOKIE_DOMAIN"'"
    ],
    "locale": "en_US",
    "_id": "",
    "_type": {
        "_id": "platform",
        "name": "Platform",
        "collection": false
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_base_url_service
# Description: Creates the base URL service in the root realm.
# -----------------------------------------------------------------------------
function create_base_url_service() {
info "Executing: Create Base-Url Service"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/services/baseurl?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d "{\"extensionClassName\":\"\"}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: configure_base_url_service
# Description: Configures the base URL service in the root realm.
# -----------------------------------------------------------------------------
function configure_base_url_service() {
info "Executing: Configure Base-URL Service"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/services/baseurl" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "extensionClassName": "",
    "fixedValue": "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'",
    "contextPath": "/am",
    "source": "FIXED_VALUE",
    "_id": "",
    "_type": {
        "_id": "baseurl",
        "name": "Base URL Source",
        "collection": false
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_base_url_service_alpha
# Description: Creates the base URL service in the Alpha realm.
# -----------------------------------------------------------------------------
function create_base_url_service_alpha() {
info "Executing: Create Base-Url Service Alpha"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/baseurl?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d "{\"extensionClassName\":\"\"}")

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: configure_base_url_service_alpha
# Description: Configures the base URL service in the Alpha realm.
# -----------------------------------------------------------------------------
function configure_base_url_service_alpha() {
info "Executing: Configure Base-URL Service Alpha"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X PUT \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/baseurl" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "extensionClassName": "",
    "fixedValue": "https://'"$PLATFORM_HOSTNAME"':'"$IG_HTTPS_PORT"'",
    "contextPath": "/am",
    "source": "FIXED_VALUE",
    "_id": "",
    "_type": {
        "_id": "baseurl",
        "name": "Base URL Source",
        "collection": false
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_oauth_oidc_root
# Description: Creates the OAuth2/OIDC service in the root realm.
# -----------------------------------------------------------------------------
function create_oauth_oidc_root() {
info "Executing: Create OAuth/OIDC Service in Root Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realm-config/services/oauth-oidc?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "advancedOAuth2Config": {
        "passwordGrantAuthService": "[Empty]",
        "persistentClaims": [],
        "supportedScopes": [
            "am-introspect-all-tokens",
            "am-introspect-all-tokens-any-realm",
            "fr:idm:*",
            "openid"
        ]
    },
    "clientsCanSkipConsent": true,
    "advancedOIDCConfig": {
        "authorisedOpenIdConnectSSOClients": []
    },
    "pluginsConfig": {
        "oidcClaimsClass": "",
        "accessTokenModifierClass": ""
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# -----------------------------------------------------------------------------
# Function: create_oauth_oidc_alpha
# Description: Creates the OAuth2/OIDC service in the Alpha realm.
# -----------------------------------------------------------------------------
function create_oauth_oidc_alpha() {
info "Executing: Create OAuth/OIDC Service in Alpha Realm"


  RESPONSE_FILE=$(mktemp)
  STATUS=$(curl -s -X POST \
    -o "$RESPONSE_FILE" \
    -w "%{http_code}" \
    "${HOST}/${AM_CONTEXT}/json/realms/root/realms/alpha/realm-config/services/oauth-oidc?_action=create" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Content-Type: application/json" \
    -H "Accept-API-Version: protocol=1.0,resource=1.0" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Cookie: iPlanetDirectoryPro=$ADMIN_TOKEN" \
    -d '{
    "advancedOAuth2Config": {
        "passwordGrantAuthService": "[Empty]",
        "persistentClaims": [],
        "supportedScopes": [
            "fr:idm:*",
            "openid"
        ]
    },
    "clientsCanSkipConsent": true,
    "advancedOIDCConfig": {
        "authorisedOpenIdConnectSSOClients": []
    },
    "pluginsConfig": {
        "oidcClaimsClass": "",
        "accessTokenModifierClass": ""
    }
}')

  if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
success "Success: HTTP $STATUS"


  else
error "Failure: HTTP $STATUS"


    cat "$RESPONSE_FILE"
echo
  fi
  rm "$RESPONSE_FILE"
}

# ==========================
# Main execution sequence
# ==========================
am_admin_login
#create_alpha_realm
configure_alpha_realm_repo
delete_opendj_top_level
create_oauth_oidc_root
create_oauth_oidc_alpha
create_idm_resource_server
create_idm_provisioning
create_idm_admin_ui_alpha
create_idm_admin_ui_root
create_end_user_ui_alpha
create_end_user_ui_root
configure_idm_integration_service
configure_validation_service_root
configure_validation_service_alpha
create_cors_service
set_external_login_root
set_external_login_alpha
map_self_service_trees
set_am_cookie_domain
create_base_url_service
configure_base_url_service
create_base_url_service_alpha
configure_base_url_service_alpha
success "All requests executed."
