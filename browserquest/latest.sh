apt-get update
apt-get upgrade

apt-get install --yes build-essential g++ libssl-dev curl git-core
apt-get install --yes libxml2-dev libssl0.9.8

export NODE_VERSION='0.6.8'
wget http://nodejs.org/dist/node-v$NODE_VERSION.tar.gz
tar xvfz node-v$NODE_VERSION.tar.gz
cd node-v$NODE_VERSION
./configure --prefix=~/local
make install
cd ~

# add node to path
# (see http://increaseyourgeek.wordpress.com/2010/08/18/install-node-js-without-using-sudo/)
export PATH=~/local/bin:${PATH}
echo 'export PATH=~/local/bin:${PATH}' >> ~/.bashrc
https://github.com/mozilla/BrowserQuest.git


curl http://npmjs.org/install.sh | sh
---browserquest----
npm install underscore log bison websocket websocket-server sanitizer memcache
git clone https://github.com/mozilla/BrowserQuest.git

# I usually start client and servers in separate screens
# screen -S server 
node server/js/main.js

# screen -S client
cd client
npm install -g http-server
# (edit config_local.json)
cp -r ../shared .
cp config/config_local.json config/config_build.json
http-server -p 8080
