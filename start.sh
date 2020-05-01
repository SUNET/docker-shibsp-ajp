#!/bin/sh -x


printenv

export HTTP_IP="127.0.0.1"
export HTTP_PORT="8080"
if [ "x${BACKEND_PORT}" != "x" ]; then
   HTTP_IP=`echo "${BACKEND_PORT}" | sed 's%/%%g' | awk -F: '{ print $2 }'`
   HTTP_PORT=`echo "${BACKEND_PORT}" | sed 's%/%%g' | awk -F: '{ print $3 }'`
fi

if [ "x$SP_HOSTNAME" = "x" ]; then
   SP_HOSTNAME="`hostname`"
fi

if [ "x$CERTNAME" = "x" ]; then
   CERTNAME=$SP_HOSTNAME
fi

if [ "x$DISCO_URL" = "x" ]; then
   DISCO_URL="https://md.nordu.net/role/idp.ds"
fi

if [ "x$SP_CONTACT" = "x" ]; then
   SP_CONTACT="info@$SP_CONTACT"
fi

if [ "x$SP_ABOUT" = "x" ]; then
   SP_ABOUT="/about"
fi

if [ "x$HTTP_PROTO" = "x" ]; then
   HTTP_PROTO="http"
fi

if [ "x$BACKEND_URL" = "x" ]; then
   BACKEND_URL="$HTTP_PROTO://$HTTP_IP:$HTTP_PORT/"
fi

if [ -z "$KEYDIR" ]; then
   KEYDIR=/etc/ssl
   mkdir -p $KEYDIR
   export KEYDIR
fi

if [ ! -f "$KEYDIR/private/shibsp-${SP_HOSTNAME}.key" -o ! -f "$KEYDIR/certs/shibsp-${SP_HOSTNAME}.crt" ]; then
   shib-keygen -o /tmp -h $SP_HOSTNAME 2>/dev/null
   mv /tmp/sp-key.pem "$KEYDIR/private/shibsp-${SP_HOSTNAME}.key"
   mv /tmp/sp-cert.pem "$KEYDIR/certs/shibsp-${SP_HOSTNAME}.crt"
fi

if [ ! -f "$KEYDIR/private/${CERTNAME}.key" -o ! -f "$KEYDIR/certs/${CERTNAME}.crt" ]; then
   make-ssl-cert generate-default-snakeoil --force-overwrite
   cp /etc/ssl/private/ssl-cert-snakeoil.key "$KEYDIR/private/${CERTNAME}.key"
   cp /etc/ssl/certs/ssl-cert-snakeoil.pem "$KEYDIR/certs/${CERTNAME}.crt"
fi

CHAINSPEC=""
export CHAINSPEC
if [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${CERTNAME}.chain"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}-chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${CERTNAME}-chain.crt"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${CERTNAME}.chain.crt"
elif [ -f "$KEYDIR/certs/chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.crt"
elif [ -f "$KEYDIR/certs/chain.pem" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.pem"
fi

cp /etc/shibboleth/shibboleth2.xml /etc/shibboleth/shibboleth2.xml.bak
cat>/etc/shibboleth/shibboleth2.xml<<EOF
<SPConfig xmlns="urn:mace:shibboleth:3.0:native:sp:config"
    xmlns:conf="urn:mace:shibboleth:3.0:native:sp:config"
    clockSkew="180">

    <OutOfProcess tranLogFormat="%u|%s|%IDP|%i|%ac|%t|%attr|%n|%b|%E|%S|%SS|%L|%UA|%a" />
  
    <!--
    By default, in-memory StorageService, ReplayCache, ArtifactMap, and SessionCache
    are used. See example-shibboleth2.xml for samples of explicitly configuring them.
    -->

    <!-- The ApplicationDefaults element is where most of Shibboleth's SAML bits are defined. -->
    <ApplicationDefaults entityID="https://${SP_HOSTNAME}/shibboleth"
        REMOTE_USER="eppn subject-id pairwise-id persistent-id"
        attributePrefix="AJP_"
        cipherSuites="DEFAULT:!EXP:!LOW:!aNULL:!eNULL:!DES:!IDEA:!SEED:!RC4:!3DES:!kRSA:!SSLv2:!SSLv3:!TLSv1:!TLSv1.1">

        <!--
        Controls session lifetimes, address checks, cookie handling, and the protocol handlers.
        Each Application has an effectively unique handlerURL, which defaults to "/Shibboleth.sso"
        and should be a relative path, with the SP computing the full value based on the virtual
        host. Using handlerSSL="true" will force the protocol to be https. You should also set
        cookieProps to "https" for SSL-only sites. Note that while we default checkAddress to
        "false", this makes an assertion stolen in transit easier for attackers to misuse.
        -->
        <Sessions lifetime="28800" timeout="3600" relayState="ss:mem"
                  checkAddress="false" handlerSSL="false" cookieProps="http">

            <!--
            Configures SSO for a default IdP. To properly allow for >1 IdP, remove
            entityID property and adjust discoveryURL to point to discovery service.
            You can also override entityID on /Login query string, or in RequestMap/htaccess.
            -->
            <SSO discoveryProtocol="SAMLDS" discoveryURL="${DISCO_URL}">
              SAML2
            </SSO>

            <!-- SAML and local-only logout. -->
            <Logout>SAML2 Local</Logout>

            <!-- Administrative logout. -->
            <LogoutInitiator type="Admin" Location="/Logout/Admin" acl="127.0.0.1 ::1" />
          
            <!-- Extension service that generates "approximate" metadata based on SP configuration. -->
            <Handler type="MetadataGenerator" Location="/Metadata" signing="false"/>

            <!-- Status reporting service. -->
            <Handler type="Status" Location="/Status" acl="127.0.0.1 ::1"/>

            <!-- Session diagnostic service. -->
            <Handler type="Session" Location="/Session" showAttributeValues="false"/>

            <!-- JSON feed of discovery information. -->
            <Handler type="DiscoveryFeed" Location="/DiscoFeed"/>
        </Sessions>

        <!--
        Allows overriding of error template information/filenames. You can
        also add your own attributes with values that can be plugged into the
        templates, e.g., helpLocation below.
        -->
        <Errors supportContact="root@localhost"
            helpLocation="${SP_ABOUT}"
            styleSheet="/shibboleth-sp/main.css"/>

        <MetadataProvider type="XML" validate="false" path="${METADATA_FILE}" maxRefreshDelay="7200">
            <MetadataFilter type="RequireValidUntil" maxValidityInterval="2419200"/>
            <DiscoveryFilter type="Blacklist" matcher="EntityAttributes" trimTags="true" 
              attributeName="http://macedir.org/entity-category"
              attributeNameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"
              attributeValue="http://refeds.org/category/hide-from-discovery" />
        </MetadataProvider>

        <!-- Example of remotely supplied "on-demand" signed metadata. -->
        <!--
        <MetadataProvider type="MDQ" validate="true" cacheDirectory="mdq"
	            baseUrl="http://mdq.federation.org" ignoreTransport="true">
            <MetadataFilter type="RequireValidUntil" maxValidityInterval="2419200"/>
            <MetadataFilter type="Signature" certificate="mdqsigner.pem" />
        </MetadataProvider>
        -->

        <!-- Map to extract attributes from SAML assertions. -->
        <AttributeExtractor type="XML" validate="true" reloadChanges="false" path="attribute-map.xml"/>

        <!-- Default filtering policy for recognized attributes, lets other data pass. -->
        <AttributeFilter type="XML" validate="true" path="attribute-policy.xml"/>

        <!-- Simple file-based resolvers for separate signing/encryption keys. -->
        <CredentialResolver type="File" use="signing"
            key="${KEYDIR}/private/shibsp-${SP_HOSTNAME}.key" certificate="${KEYDIR}/certs/shibsp-${SP_HOSTNAME}.crt"/>
        <CredentialResolver type="File" use="encryption"
            key="${KEYDIR}/private/shibsp-${SP_HOSTNAME}.key" certificate="${KEYDIR}/certs/shibsp-${SP_HOSTNAME}.crt"/>
        
    </ApplicationDefaults>
    
    <!-- Policies that determine how to process and authenticate runtime messages. -->
    <SecurityPolicyProvider type="XML" validate="true" path="security-policy.xml"/>

    <!-- Low-level configuration about protocols and bindings available for use. -->
    <ProtocolProvider type="XML" validate="true" reloadChanges="false" path="protocols.xml"/>

</SPConfig>
EOF

cat>/etc/apache2/sites-available/default.conf<<EOF
ServerName ${SP_HOSTNAME}
<VirtualHost *:80>
   ServerName ${SP_HOSTNAME}
   ServerAdmin ${SP_CONTACT}
   Alias /shibboleth-sp/ /usr/share/shibboleth
   <Location "/Shibboleth.sso">
       SetHandler default-handler
   </Location>
   <Directory /usr/share/shibboleth>
       Order deny,allow
       Allow from all
   </Directory>
   <Location "/">
       Order deny,allow
       Allow from all
   </Location>
   <Location "${PROTECTED_URL}">
       AuthType shibboleth
       ShibRequireSession On
       require valid-user
   </Location>
   AddDefaultCharset utf-8
   ProxyTimeout 600
   ProxyPass /Shibboleth.sso !
   ProxyPass /shibboleth-sp !
   ProxyPreserveHost On
   ProxyPass / ${BACKEND_URL}
   ProxyPassReverse / ${BACKEND_URL}

        HostnameLookups Off
        ErrorLog /proc/self/fd/2
        LogLevel warn
        LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
        LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
        LogFormat "%h %l %u %t \"%r\" %>s %O" common
        LogFormat "%{Referer}i -> %U" referer
        LogFormat "%{User-agent}i" agent

        CustomLog /proc/self/fd/1 combined

        ServerSignature off
</VirtualHost>
EOF

cat>/etc/apache2/sites-available/default-ssl.conf<<EOF
ServerName ${SP_HOSTNAME}
<VirtualHost *:443>
        ServerName ${SP_HOSTNAME}
        SSLProtocol All -SSLv2 -SSLv3
        SSLCompression Off
        SSLCipherSuite "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+AESGCM EECDH EDH+AESGCM EDH+aRSA HIGH !MEDIUM !LOW !aNULL !eNULL !LOW !RC4 !MD5 !EXP !PSK !SRP !DSS"
        SSLEngine On
        SSLCertificateFile $KEYDIR/certs/${CERTNAME}.crt
        ${CHAINSPEC}
        SSLCertificateKeyFile $KEYDIR/private/${CERTNAME}.key
        DocumentRoot /var/www/
        
        Alias /shibboleth-sp/ /usr/share/shibboleth/

        ServerName ${SP_HOSTNAME}
        ServerAdmin ${SP_CONTACT}

        AddDefaultCharset utf-8

   <Location "/Shibboleth.sso">
       SetHandler default-handler
   </Location>
   <Directory /usr/share/shibboleth>
       Order deny,allow
       Allow from all
   </Directory>
   <Location "/">
       Order deny,allow
       Allow from all
   </Location>
   <Location "${PROTECTED_URL}">
       AuthType shibboleth
       ShibRequireSession On
       require valid-user
   </Location>

   ProxyRequests On
   ProxyTimeout 600
   ProxyPass /Shibboleth.sso !
   ProxyPass /shibboleth-sp !
   ProxyPass / ${BACKEND_URL}
   ProxyPassReverse / ${BACKEND_URL}
   ProxyPreserveHost On

        HostnameLookups Off
        ErrorLog /proc/self/fd/2
        LogLevel warn
        LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
        LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
        LogFormat "%h %l %u %t \"%r\" %>s %O" common
        LogFormat "%{Referer}i -> %U" referer
        LogFormat "%{User-agent}i" agent

        CustomLog /proc/self/fd/1 combined

        ServerSignature off
</VirtualHost>
EOF

a2ensite default
a2ensite default-ssl

echo "----"
cat /etc/shibboleth/shibboleth2.xml
echo "----"
cat /etc/apache2/sites-available/default.conf
echo "----"
cat /etc/apache2/sites-available/default-ssl.conf

mkdir -p /var/log/shibboleth
apache2ctl -v

service shibd start&

rm -f /var/run/apache2/apache2.pid
mkdir -p /var/log/apache2
env APACHE_LOCK_DIR=/var/lock/apache2 APACHE_RUN_DIR=/var/run/apache2 APACHE_PID_FILE=/var/run/apache2/apache2.pid APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data APACHE_LOG_DIR=/var/log/apache2 apache2 -DFOREGROUND
