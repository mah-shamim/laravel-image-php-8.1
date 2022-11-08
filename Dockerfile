FROM ubuntu:22.04
MAINTAINER Derek Bourgeois <derek@ibourgeois.com>

# set some environment variables
ENV APP_NAME app
ENV APP_EMAIL app@laraedit.com
ENV APP_DOMAIN app.dev
ENV DEBIAN_FRONTEND noninteractive

# upgrade the container
RUN apt-get update && \
    apt-get upgrade --assume-yes

# install some prerequisites
RUN apt-get update && apt-get install --assume-yes --no-install-recommends apt-utils

RUN apt-get install --assume-yes software-properties-common curl \
    build-essential libmcrypt4 libpcre3-dev python-pip wget zip \
    unattended-upgrades whois vim libnotify-bin locales \
    cron libpng-dev unzip

# add some repositories
RUN curl --silent --location https://deb.nodesource.com/setup_18.x | bash - && \
    add-apt-repository ppa:ondrej/nginx-mainline && \
    add-apt-repository ppa:ondrej/php && \
    apt-get update

# set the locale
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale  && \
    locale-gen en_US.UTF-8  && \
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
    
# setup bash
COPY .bash_aliases /root

# install nginx
RUN apt-get install --assume-yes --allow-downgrades --allow-remove-essential --allow-change-held-packages nginx
COPY homestead /etc/nginx/sites-available/
RUN rm -rf /etc/nginx/sites-available/default && \
    rm -rf /etc/nginx/sites-enabled/default && \
    ln -fs "/etc/nginx/sites-available/homestead" "/etc/nginx/sites-enabled/homestead" && \
    sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf && \
    sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf && \
    echo "daemon off;" >> /etc/nginx/nginx.conf && \
    usermod -u 1000 www-data && \
    chown -Rf www-data.www-data /var/www/html/ && \
    sed -i -e"s/worker_processes  1/worker_processes 5/" /etc/nginx/nginx.conf
VOLUME ["/var/www/html/app"]
VOLUME ["/var/cache/nginx"]
VOLUME ["/var/log/nginx"]

# install php
RUN apt-get install --assume-yes --allow-downgrades --allow-remove-essential --allow-change-held-packages php-fpm php-cli php-gd \
    php-curl php-imap php-mysql php-readline php-common php-mbstring php-xml php-zip php-bcmath php-soap php-imagick php-intl
    
COPY fastcgi_params /etc/nginx/
RUN mkdir -p /run/php/ && chown -Rf www-data.www-data /run/php

# install node and databases 
RUN apt-get install --assume-yes --allow-downgrades --allow-remove-essential --allow-change-held-packages nodejs

# install mysql 
RUN echo mysql-server mysql-server/root_password password $DB_PASS | debconf-set-selections;\
    echo mysql-server mysql-server/root_password_again password $DB_PASS | debconf-set-selections;\
    apt-get install --assume-yes mysql-server && \
    echo "[mysqld]" >> /etc/mysql/my.cnf && \
    echo "default_password_lifetime = 0" >> /etc/mysql/my.cnf && \
    sed -i '/^bind-address/s/bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf

RUN find /var/lib/mysql -exec touch {} \; && service mysql start && \
    sleep 10s && \
    echo "GRANT ALL PRIVILEGES ON *.* TO root@'localhost' WITH GRANT OPTION; \
    FLUSH PRIVILEGES; \
    CREATE USER 'homestead'@'%' IDENTIFIED BY 'secret'; \
    GRANT ALL PRIVILEGES ON *.* TO 'homestead'@'%'  WITH GRANT OPTION; \
    FLUSH PRIVILEGES; \
    CREATE DATABASE homestead;" | mysql

#    before flush previlage
# GRANT ALL PRIVILEGES ON *.* TO 'homestead'@'%'; \

VOLUME ["/var/lib/mysql"]

# install composer
RUN curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer && \
    printf "\nPATH=\"~/.composer/vendor/bin:\$PATH\"\n" | tee -a ~/.bashrc
    

# install supervisor
RUN apt-get install --assume-yes supervisor && \
    mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

VOLUME ["/var/log/supervisor"]

# clean up our mess
RUN apt-get remove --purge --assume-yes software-properties-common && \
    apt-get autoremove --assume-yes && \
    apt-get clean && \
    apt-get autoclean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/man/?? && \
    rm -rf /usr/share/man/??_*

# expose ports
EXPOSE 80 443 3306

# set container entrypoints
ENTRYPOINT ["/bin/bash","-c"]
CMD ["/usr/bin/supervisord"]
