#!/bin/bash
apt update && sudo apt upgrade -y
apt install php php-mbstring php-xml php-bcmath php-curl git curl python3 python3-pip unzip apache2 glances -y
# sudo nano ~/.bashrc & add this line > export PATH=$PATH:/usr/bin/php to the EOF then source ~/.bashrc
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
mkdir /var/www/html/proj && cd /var/www/html/proj
chown -R www-data:www-data /var/www/html
composer create-project laravel/laravel my_app_name # Replace my_app_name with your fav app name, the directory for the project preferred to be /var/www/html and replance or backup the index.html
apt install mysql-server phpmyadmin -y
service mysql restart
service apache2 restart
