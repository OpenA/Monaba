Monaba
======

Imageboard engine written in Haskell and powered by Yesod.

Features
------
* Multiple file attachment
* File censorship ratings
* [Hellbanning](http://en.wikipedia.org/wiki/Hellbanning)
* AJAX, EventSource, HTML5
* Prooflabes
* Flexible account system
* Internationalization
* Post deletion by OP
* GeoIP support
* Thread hiding

Dependencies
------
* GHC >= 7.6
* PHP 5
* GD image library
* PostgreSQL >= 9.1

Installation
------
Edit config/settings.yml and config/mysql.yml

**Download GeoIPCity:**

    wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
    gzip -d GeoLiteCity.dat.gz
    cp GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat

Or it can be installed from repositories.

**Download GeSHi:**

    wget http://sourceforge.net/projects/geshi/files/geshi/GeSHi%201.0.8.11/GeSHi-1.0.8.11.tar.gz
    tar -zxvf GeSHi-1.0.8.11.tar.gz

(Set your path to GeSHi in highlight.php)

**Install all required packages:**

Linux (APT):

    apt-get install ghc php5 libgd-dev postgresql
    apt-get install cabal-install zlibc libpcre++-dev libpcre3 libpcre3-dev libgeoip-dev libcrypto++-dev libssl-dev postgresql-server-dev-all
    
OS X (Homebrew):

    brew install ghc freetype fontconfig postgresql
    brew install cabal-install geoip gd
    
**Using already compiled binary:**

Download Monaba-[your-arch]-[your-platform].7z [here](https://github.com/ahushh/Monaba/releases) and unpack it to dist/build/Monaba/

**Manual building:**

    cabal update
    cabal install hsenv
    ~/.cabal/bin/hsenv
    source .hsenv/bin/activate
    cabal install happy
    cabal install --only-dependencies
    cabal install yesod-bin
    cabal clean && yesod configure && yesod build

**Run:**

Create a database:

    psql
    =# ALTER USER postgres WITH PASSWORD 'youpassword';
    =# CREATE DATABASE monaba_production OWNER postgres ENCODING 'UTF8' LC_COLLATE = 'en_EN.UTF-8' LC_CTYPE = 'en_EN.UTF-8';

Run the application to initialize database schema:

    ./dist/build/Monaba/Monaba production

Open another terminal and fill database with default values:

    psql -U postgres monaba_production < init-db.sql

Use "admin" both for username and for password to log in.
