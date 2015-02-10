#!/bin/bash

# SE PLACER A LA BASE DU REPERTOIRE VIRTUEL, PAS DANS LE REPERTOIRE HTDOCS
SITEURL=$(basename $PWD)
E_USAGE=64
if [ "$SITEURL" == "htdocs" ]
then
  echo "Usage: pas dans htdocs mais dans le répertoire en dessous, celui du nom de domaine"
  exit $E_USAGE
fi

EXPECTED_ARGS=6
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: bash wpgandi.sh dbname dbuser dbpass adminuser adminmail adminpass"
  exit $E_BADARGS
fi

# Fonction de sortie de script :
die() {
        echo $@ >&2 ;
        exit 1 ;
}

# CREATION DE LA BASE
MYSQL=`which mysql`

D0="GRANT USAGE ON *.* TO $2@localhost;"
D1="DROP USER $2@localhost;" 
D2="DROP DATABASE IF EXISTS $1;" 
Q1="CREATE DATABASE IF NOT EXISTS $1;"
Q2="GRANT USAGE ON *.* TO $2@localhost IDENTIFIED BY '$3';"
Q3="GRANT ALL PRIVILEGES ON $1.* TO $2@localhost;"
Q4="FLUSH PRIVILEGES;"
SQL="${D0}${D1}${D2}${Q1}${Q2}${Q3}${Q4}"

$MYSQL -uroot -p -e "$SQL"
[ $? -eq 0 ] || die "Impossible to de créer la base et le user, mot de passe incorrect ?" ;

#NETTOYAGE
rm -rf htdocs/*
echo "Répertoire htdocs nettoyé"
if [ -f htdocs/.htaccess ]
then
	rm htdocs/.htaccess
else
	echo "pas de htaccess a supprimer"
	echo "htaccess supprimé"
fi
if [ -f .htpasswd ]
then
	rm .htpasswd
	echo "htpasswd supprimé"
else
	echo "pas de htpasswd a supprimer"
fi

# FICHIER CONF WP-CLI
echo 'path:htdocs' > wp-cli.yml
echo 'debug:true' >> wp-cli.yml
echo 'url:http://'$SITEURL >> wp-cli.yml
echo 'apache_modules:' >> wp-cli.yml
echo '	- mod_rewrite' >> wp-cli.yml

# WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

# INSTALLATION
php wp-cli.phar core download --locale=fr_FR --force
php wp-cli.phar core config --dbhost=localhost --dbname=$1 --dbuser=$2 --dbpass=$3 --skip-check --extra-php <<PHP
define('WP_HOME','http://$SITEURL');
define('WP_SITEURL','http://$SITEURL');
PHP

php wp-cli.phar core install --title="Wordpress" --admin_user=$4 --admin_email=$5 --admin_password=$6

# PARAMETRAGE GENERAL
php wp-cli.phar option update blog_public 0
php wp-cli.phar option update timezone_string Europe/Paris

# NETTOYAGE
php wp-cli.phar theme delete twentythirteen
php wp-cli.phar theme delete twentyfourteen
php wp-cli.phar post delete $(php wp-cli.phar post list --post_type=page --posts_per_page=1 --post_status=publish --pagename="page-d-exemple" --field=ID --format=ids)
php wp-cli.phar post delete $(php wp-cli.phar post list --post_type=post --posts_per_page=1 --post_status=publish --postname="bonjour-tout-le-monde" --field=ID --format=ids)
php wp-cli.phar plugin deactivate hello
php wp-cli.phar plugin uninstall hello
php wp-cli.phar plugin deactivate akismet
php wp-cli.phar plugin uninstall akismet

# NOUVEAU CHLD THEME pour TWENTY FIFTEEN
php wp-cli.phar scaffold child-theme twentyfifteen-child --parent_theme=twentyfifteen --activate

# PLUGINS (RAF : ithemes security + parametrage)
php wp-cli.phar plugin install wordpress-seo --activate
php wp-cli.phar plugin install backwpup --activate
php wp-cli.phar plugin install black-studio-tinymce-widget --activate
php wp-cli.phar plugin install contact-form-7 --activate
php wp-cli.phar plugin install really-simple-captcha --activate
php wp-cli.phar plugin install ewww-image-optimizer --activate
php wp-cli.phar plugin install wp-optimize --activate
php wp-cli.phar plugin install zero-spam --activate
php wp-cli.phar plugin install wp-maintenance-mode --activate
php wp-cli.phar plugin install w3-total-cache

# PARAMETRAGE PERMALIENS (avec modif du .htaccess)
php wp-cli.phar rewrite structure "/%postname%/" --hard
php wp-cli.phar rewrite flush --hard

# robots.txt et .htaccess (avec creation htpasswd pour protection Brute Force Attack)
echo 'User-agent: *' > htdocs/robots.txt
echo 'Disallow: /wp-login.php' >> htdocs/robots.txt
echo 'Disallow: /wp-admin' >> htdocs/robots.txt
echo 'Disallow: /wp-includes' >> htdocs/robots.txt
echo 'Sitemap: http://'$SITEURL'/sitemap_index.xml' >> htdocs/robots.txt

htpasswd -b -c .htpasswd $4 $6

echo '<FilesMatch "wp-login.php">' >> htdocs/.htaccess
echo 'AuthType Basic' >> htdocs/.htaccess
echo 'AuthName "Secure Area"' >> htdocs/.htaccess
echo 'AuthUserFile /srv/data/web/vhosts/'$SITEURL'/.htpasswd' >> htdocs/.htaccess
echo 'require valid-user' >> htdocs/.htaccess
echo '</FilesMatch>' >> htdocs/.htaccess

echo 'AuthUserFile /srv/data/web/vhosts/'$SITEURL'/.htpasswd' > htdocs/wp-admin/.htaccess
echo 'AuthName "Secure Area"' >> htdocs/wp-admin/.htaccess
echo 'AuthType Basic' >> htdocs/wp-admin/.htaccess
echo '<limit GET POST>' >> htdocs/wp-admin/.htaccess
echo 'require valid-user' >> htdocs/wp-admin/.htaccess
echo '</limit>' >> htdocs/wp-admin/.htaccess

# NETTOYAGE
rm wp-cli.yml
rm wp-cli.phar