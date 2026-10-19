#!/bin/bash
#CATALINA_OPTS="-Djavax.net.ssl.trustStore=/home/fradmin/am/security/keystores/truststore -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=jks"

CATALINA_OPTS="\
  -Dcom.sun.identity.sm.sms_object_filebased_enabled=true \
  -Dam.server.fqdn=am.example.com \
  -Dam.stores.user.servers={{DS_IDREPO_SERVER}}:{{DS_IDREPO_SERVER_LDAPS_PORT}} \
  -Dam.stores.user.username=uid=am-identity-bind-account,ou=admins,{{DS_IDREPO_DN}} \
  -Dam.stores.user.password={{DEFAULT_PASSWORD}} \
  -Dam.test.mode=true \
  -Dam.stores.application.servers={{DS_AMCONFIG_SERVER}}:{{DS_AMCONFIG_SERVER_LDAPS_PORT}} \
  -Dam.stores.application.password={{DEFAULT_PASSWORD}} \
  -Djavax.net.ssl.trustStore={{AM_TRUSTSTORE}} \
  -Djavax.net.ssl.trustStorePassword={{TRUSTSTORE_PASSWORD}} \
  -Djavax.net.ssl.trustStoreType=jks \
  -Dam.stores.cts.servers={{DS_CTS_SERVER}}:{{DS_CTS_SERVER_LDAPS_PORT}} \
  -Dam.stores.cts.password={{DEFAULT_PASSWORD}} \
  -server \
  -Xms256m \
  -Xmx512m \
  -XX:MetaspaceSize=128m \
  -XX:MaxMetaspaceSize=256m"
export CATALINA_OPTS