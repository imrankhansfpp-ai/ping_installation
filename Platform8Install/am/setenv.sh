#!/bin/bash
CATALINA_OPTS="-Xms256m -Xmx512m -server -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m -Djavax.net.ssl.trustStore={{AM_TRUSTSTORE}} -Djavax.net.ssl.trustStorePassword={{TRUSTSTORE_PASSWORD}} -Djavax.net.ssl.trustStoreType=jks"
export CATALINA_OPTS
