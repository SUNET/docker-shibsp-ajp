FROM debian:stable
MAINTAINER leifj@sunet.se
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update
RUN apt-get -y install apache2 libapache2-mod-shib2 ssl-cert wget curl vim less
RUN a2enmod rewrite
RUN a2enmod shib
RUN a2enmod proxy
RUN a2enmod proxy_http
RUN a2enmod ssl
RUN a2enmod headers
RUN a2enmod proxy_ajp
ENV SP_HOSTNAME localhost
ENV SP_CONTACT root@localhost
ENV SP_ABOUT /about
ENV PROTECTED_URL /secure
ENV DISCO_URL https://service.seamlessaccess.org/ds/
ENV METADATA_URL http://mds.swamid.se/md/swamid-idp-transitive.xml
ENV METADATA_SIGNER md-signer2.crt
RUN rm -f /etc/apache2/sites-available/*
RUN rm -f /etc/apache2/sites-enabled/*
ADD start.sh /start.sh
RUN chmod a+rx /start.sh
ADD md-signer2.crt /etc/shibboleth/md-signer2.crt
ADD attribute-map.xml /etc/shibboleth/attribute-map.xml
EXPOSE 80
EXPOSE 443
VOLUME /credentials
ENTRYPOINT ["/start.sh"]
