#!/bin/bash

# SE PLACER A LA BASE DU REPERTOIRE VIRTUEL, PAS DANS LE REPERTOIRE HTDOCS
SITEURL=$(basename $PWD)
E_USAGE=64
if [ "$SITEURL" == "htdocs" ]
then
  echo "Usage: pas dans htdocs mais dans le répertoire en dessous, celui du nom de domaine"
  exit $E_USAGE
fi

EXPECTED_ARGS=3
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: bash wpgandi.sh dbname wpuser wpmail"
  exit $E_BADARGS
fi

# GENERATION DE PASSWORD DB
passworddb=`head -c 12 /dev/random | base64`
passworddb=${passworddb:0:12}

# GENERATION DE PASSWORD WP
passwordwp=`head -c 12 /dev/random | base64`
passwordwp=${passwordwp:0:12}

# Fonction de sortie de script :
die() {
        echo $@ >&2 ;
        exit 1 ;
}

# CREATION DE LA BASE
MYSQL=`which mysql`

D0="GRANT USAGE ON *.* TO $1@localhost;"
D1="DROP USER $1@localhost;" 
D2="DROP DATABASE IF EXISTS $1;" 
Q1="CREATE DATABASE IF NOT EXISTS $1;"
Q2="GRANT USAGE ON *.* TO $1@localhost IDENTIFIED BY '$passworddb';"
Q3="GRANT ALL PRIVILEGES ON $1.* TO $1@localhost;"
Q4="FLUSH PRIVILEGES;"
SQL="${D0}${D1}${D2}${Q1}${Q2}${Q3}${Q4}"

$MYSQL -uroot -p -e "$SQL"
[ $? -eq 0 ] || die "Impossible de créer la base et le user, mot de passe mysql incorrect ?" ;

#NETTOYAGE
rm -rf htdocs/*
echo "Repertoire htdocs clean"
if [ -f htdocs/.htaccess ]
then
	rm htdocs/.htaccess
	echo "Delete htaccess"
else
	echo "Pas de htaccess a supprimer"
fi
if [ -f .htpasswd ]
then
	rm .htpasswd
	echo "Delete htpasswd"
else
	echo "Pas de htpasswd a supprimer"
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
php wp-cli.phar core download --force
php wp-cli.phar core config --dbhost=localhost --dbname=$1 --dbuser=$1 --dbpass=$passworddb --dbprefix="site_" --locale=fr_FR --extra-php <<PHP
define('WP_HOME','http://$SITEURL');
define('WP_SITEURL','http://$SITEURL');
define( 'WP_MEMORY_LIMIT', '64M' );
PHP

php wp-cli.phar core install --title="Un site utilisant Wordpress" --url=$SITEURL --admin_user=$2 --admin_email=$3 --admin_password=$passwordwp

php wp-cli.phar core language install fr_FR --activate

# PARAMETRAGE GENERAL
php wp-cli.phar option update blog_public 0
php wp-cli.phar option update timezone_string Europe/Paris
php wp-cli.phar option update date_format 'j F Y'
php wp-cli.phar option update time_format 'G \h i \m\i\n'

# NETTOYAGE
php wp-cli.phar theme delete twentythirteen
php wp-cli.phar theme delete twentyfourteen
php wp-cli.phar post delete $(php wp-cli.phar post list --post_type=page --posts_per_page=1 --post_status=publish --pagename="sample-page" --field=ID --format=ids)
php wp-cli.phar post delete $(php wp-cli.phar post list --post_type=post --posts_per_page=1 --post_status=publish --postname="bonjour-tout-le-monde" --field=ID --format=ids)
php wp-cli.phar plugin deactivate hello
php wp-cli.phar plugin uninstall hello
php wp-cli.phar plugin deactivate akismet
php wp-cli.phar plugin uninstall akismet
php wp-cli.phar widget delete $(php wp-cli.phar widget list sidebar-1 --format=ids)

# PLUGINS (RAF : redirection manuellement)
php wp-cli.phar plugin install wordpress-seo --activate

php wp-cli.phar plugin install disable-emojis --activate
php wp-cli.phar plugin install black-studio-tinymce-widget --activate
php wp-cli.phar plugin install contact-form-7 --activate

php wp-cli.phar plugin install backwpup --activate
php wp-cli.phar plugin install automatic-updater --activate
php wp-cli.phar plugin install wp-sweep --activate
php wp-cli.phar plugin install ewww-image-optimizer --activate

php wp-cli.phar plugin install varnish-http-purge
php wp-cli.phar plugin install wp-super-cache --activate
php wp-cli.phar plugin install all-in-one-wp-security-and-firewall

# PARAMETRAGE PERMALIENS (avec modif du .htaccess)
php wp-cli.phar rewrite structure "/%postname%/" --hard
php wp-cli.phar rewrite flush --hard

# FERMETURE DES COMMENTAIRES
php wp-cli.phar option set default_comment_status closed

# PARAMETRAGE PLUGIN EWWW IMAGE
php wp-cli.phar option update ewww_image_optimizer_jpegtran_copy 1

# OPTION : NOUVEAU CHLD THEME pour TWENTY FIFTEEN
#php wp-cli.phar scaffold child-theme twentyfifteen-child --parent_theme=twentyfifteen --activate

# OPTION : CREATION DE 3 PAGES PAR DEFAUT
#php wp-cli.phar post create --post_type=page --post_title='Accueil' --post_status=publish --post_author=$(php wp-cli.phar user get $2 --field=ID --format=ids)
#php wp-cli.phar post create --post_type=page --post_title='A propos' --post_status=publish --post_author=$(php wp-cli.phar user get $2 --field=ID --format=ids)
#php wp-cli.phar post create --post_type=page --post_title='Contact' --post_content='[contact-form-7 id="5" title="Formulaire de contact 1"]' --post_status=publish --post_author=$(php wp-cli.phar user get $2 --field=ID --format=ids)
#php wp-cli.phar option update show_on_front 'page'
#php wp-cli.phar option update page_on_front $(php wp-cli.phar post list --post_type=page --post_status=publish --posts_per_page=1 --pagename=accueil --field=ID --format=ids)

# OPTION : CREATION MENU
#php wp-cli.phar menu create "Menu Principal"
#for pageid in $(php wp-cli.phar post list --order="ASC" --orderby="date" --post_type=page --post_status=publish --posts_per_page=-1 --field=ID --format=ids); do
#	php wp-cli.phar menu item add-post menu-principal $pageid
#done
#php wp-cli.phar menu location assign menu-principal primary

# robots.txt et .htaccess (avec creation htpasswd pour protection Brute Force Attack)
echo '# Googlebot' > htdocs/robots.txt
echo 'User-agent: Googlebot' >> htdocs/robots.txt
echo 'Allow: *.css*' >> htdocs/robots.txt
echo 'Allow: *.js*' >> htdocs/robots.txt
echo '# Global' >> htdocs/robots.txt
echo 'User-agent: *' >> htdocs/robots.txt
echo 'Disallow: /wp-admin/' >> htdocs/robots.txt
echo 'Disallow: /wp-includes/' >> htdocs/robots.txt
echo 'Allow: /wp-includes/js/' >> htdocs/robots.txt
echo 'Allow: /wp-content/plugins/' >> htdocs/robots.txt
echo 'Allow: /wp-content/themes/' >> htdocs/robots.txt
echo 'Allow: /wp-content/cache/' >> htdocs/robots.txt
echo 'Disallow: /xmlrpc.php' >> htdocs/robots.txt
echo 'Sitemap: http://'$SITEURL'/sitemap_index.xml' >> htdocs/robots.txt

htpasswd -b -c .htpasswd $2 $passwordwp

echo '' >> htdocs/.htaccess
echo '<FilesMatch "wp-login.php">' >> htdocs/.htaccess
echo 'AuthType Basic' >> htdocs/.htaccess
echo 'AuthName "Secure Area"' >> htdocs/.htaccess
echo 'AuthUserFile /srv/data/web/vhosts/'$SITEURL'/.htpasswd' >> htdocs/.htaccess
echo 'require valid-user' >> htdocs/.htaccess
echo '</FilesMatch>' >> htdocs/.htaccess
echo '' >> htdocs/.htaccess
echo 'Header unset Pragma' >> htdocs/.htaccess
echo 'FileETag None' >> htdocs/.htaccess
echo 'Header unset ETag' >> htdocs/.htaccess
echo '## EXPIRES CACHING ##' >> htdocs/.htaccess
echo '<IfModule mod_expires.c>' >> htdocs/.htaccess
echo 'ExpiresActive On' >> htdocs/.htaccess
echo 'ExpiresByType image/jpg "access 1 year"' >> htdocs/.htaccess
echo 'ExpiresByType image/jpeg "access 1 year"' >> htdocs/.htaccess
echo 'ExpiresByType image/gif "access 1 year"' >> htdocs/.htaccess
echo 'ExpiresByType image/png "access 1 year"' >> htdocs/.htaccess
echo 'ExpiresByType text/css "access 1 month"' >> htdocs/.htaccess
echo 'ExpiresByType text/html "access 1 month"' >> htdocs/.htaccess
echo 'ExpiresByType application/pdf "access 1 month"' >> htdocs/.htaccess
echo 'ExpiresByType text/x-javascript "access 1 month"' >> htdocs/.htaccess
echo 'ExpiresByType application/x-shockwave-flash "access 1 month"' >> htdocs/.htaccess
echo 'ExpiresByType image/x-icon "access 1 year"' >> htdocs/.htaccess
echo 'ExpiresDefault "access 1 month"' >> htdocs/.htaccess
echo '</IfModule>' >> htdocs/.htaccess
echo '## EXPIRES CACHING ##' >> htdocs/.htaccess

echo 'AuthUserFile /srv/data/web/vhosts/'$SITEURL'/.htpasswd' > htdocs/wp-admin/.htaccess
echo 'AuthName "Secure Area"' >> htdocs/wp-admin/.htaccess
echo 'AuthType Basic' >> htdocs/wp-admin/.htaccess
echo 'require valid-user' >> htdocs/wp-admin/.htaccess

# NETTOYAGE
rm wp-cli.yml
rm wp-cli.phar

# SECU : ON DEPLACE WP-CONFIG
# mv htdocs/wp-config.php ./
# chmod 600 wp-config.php

find ./htdocs/ -type d -exec chmod 755 {} \;
find ./htdocs/ -type f -exec chmod 644 {} \;

echo "================================================================="
echo "Installation ok."
echo ""
echo "Username DB: $1"
echo "Password DB: $passworddb"
echo ""
echo "Username WP: $2"
echo "Password WP: $passwordwp"
echo ""
echo "================================================================="
