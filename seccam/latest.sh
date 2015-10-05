#!/bin/bash

source <(curl -s https://raw.githubusercontent.com/portalplatform/apps/master/portal.sh)

# Packages
add-apt-repository -y ppa:nginx/stable
apt-get update
apt-get install -y vsftpd pwgen nginx

export CAMERAS="cam1 cam2 cam3 cam4 cam5 cam6 cam7 cam8 cam9 cam10"
export PASSWORD_FILE="/data/pw"

# Generate FTP password, if necessary.
[ -e $PASSWORD_FILE ] || pwgen 8 1 > $PASSWORD_FILE
export PASSWORD=$(cat $PASSWORD_FILE)

# Users
for camera in $CAMERAS ; do
    useradd --home-dir "/$camera" --create-home --shell /bin/true "$camera"
    echo "$camera:$PASSWORD" | chpasswd
done

# Setup vsftpd
echo /bin/true >>/etc/shells

cat <<VSFTPD >/etc/vsftpd.conf 
seccomp_sandbox=NO
listen=YES
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_umask=077
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
nopriv_user=ftp
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
port_enable=NO
pasv_enable=YES
pasv_addr_resolve=YES
pasv_min_port=20000
pasv_max_port=20005
pasv_address=$DOMAIN
VSFTPD

restart vsftpd


# Create cameras directory, if necessary.
if [ ! -d /data/cameras ] ; then
    mkdir -p /data/cameras
    mkdir -p /data/static
fi
echo $PASSWORD >/data/static/pw.json


# Nginx
cat <<NGINX >/etc/nginx/sites-enabled/default
server {
    listen 81;
    location $PRIVATE_URI {
        alias /data/;
        autoindex on;
        autoindex_format json;
        autoindex_localtime on;

        location ~ \.jpg$ {
            expires 1y;
        }
    }
}
NGINX
service nginx restart

# jQuery
curl --silent http://code.jquery.com/jquery-1.11.3.min.js >/data/static/jquery.js

# Javascript
cat <<'SCRIPT' >/data/static/helper.js
$(document).ready(function() {

    AUTOREFRESH = true;
    PREFIX = window.location.href.substr(0, window.location.href.lastIndexOf('/')+1);
    PREFIX += '/cameras/';
    SELECTED = '';
    DISPLAY = 50;

    function draw(cb) {
        var $dirs = $('#dirs');
        $dirs.html('');

        var $images = $('#images');
        $images.html('');

        var dirs = get_dirs(dirs);

        $.each(dirs, function(i, dir) {
            $dirs.append('<a href="#'+dir.name+'+'+DISPLAY+'">'+dir.name+'</a>');
        });

        $.each(dirs, function(i, dir) {
            if (SELECTED !== '' && SELECTED !== dir.name) {
                return
            } else {
                if (i > 1) {
                    return
                }
            }
            var images = get_images(dir.name+'/');
            if (!images.length) {
                return
            }
            $images.append('<h3>'+dir.name+'('+DISPLAY+' of '+images.length+')</h3>');
            $.each(images, function(j, image) {
                if (j >= DISPLAY) {
                    return;
                }
                path = PREFIX+dir.name+'/'+image.name;
                $images.append('<a target="_blank" href="'+path+'" title="'+image.mtime+'"><img src="'+path+'"></a>');
            });
        });

        if (typeof cb !== 'undefined') {
            cb();
        }
    }

    function get_dirs() {
        var filtered = [];
        $.ajax({
            url: PREFIX,
            dataType: "json",
            async: false
        }).success(function(dirs) {
            $.each(dirs, function(i, dir) {
                if (dir.type !== 'directory') {
                    return;
                }
                if (/^\d+\-\d+\-\d+$/.test(dir.name) == false) {
                    return;
                }
                filtered.push(dir);
            });
        });
        filtered.sort(function (a, b) {
            return new Date(b.mtime).getTime() - new Date(a.mtime).getTime()
        });
        return filtered;
    }

    function get_images(dir) {
        var filtered = [];
        $.ajax({
            "url": PREFIX+dir,
            dataType: "json",
            async: false
        }).success(function(images) {
            $.each(images, function(i, img) {
                if (/\.jpg$/.test(img.name) == false) {
                    return;
                }
                filtered.push(img);
            });
        });
        filtered.sort(function (a, b) {
            return new Date(b.mtime).getTime() - new Date(a.mtime).getTime()
        });
        return filtered;
    }

    function update_settings() {
        if (window.location.hash.length > 1) {
            var hash = window.location.hash.substr(1);
            var day = hash.substr(0, hash.lastIndexOf('+'));
            var n = hash.substr(hash.lastIndexOf('+')+1);

            if (day !== '') {
                SELECTED = day;
            }
            DISPLAY = parseInt(n, 10);
        }
        draw();
    }

    $.get('static/pw.json', function(pw) {
        $('.password').text(pw);
    }, 'text');

    $('#toggle').click(function() {
        $('#login').show();
        $(this).remove();
    });
    $('#autorefresh').click(function() {
        var $btn = $(this);
        if ($btn.data('enabled') === 'yes') {
            $btn.data('enabled', 'no');
            $btn.text('Auto Refresh: Off');
            AUTOREFRESH = false;
        } else {
            $btn.data('enabled', 'yes');
            $btn.text('Auto Refresh: On');
            AUTOREFRESH = true;
        }
    });


    $(window).on('hashchange', update_settings);
    
    update_settings();

    draw();

    setInterval(function() {
        if (AUTOREFRESH) {
            draw();
        }
    }, 2500);
});

SCRIPT



cat <<'HTML' >/data/index.html
<html>
    <head>
        <title>IP Camera Viewer</title>
        <style>
            html, body {
                min-height: 100%;
                margin: 0;
                padding: 0;
            }
            body {
                background-color: #f9f9f9;
                font-size: 125%;
                color: #333;
                font-family: sans-serif;
            }
            a {
                color: #333 !important;
            }
            #login { display: none; }
            button {
                background-color: #ddd;
                color: #333;
                padding: 10px 20px;
                border: 0;
                float: right;
            }
            #images {
                margin-top: 15px;
                width: 100%;
            }
            img {
                max-width: 33%;
            }
            table {
                padding: 10px;
                margin-top: 5px;
                border: 1px solid #333;
            }
            td {
                padding: 5px 0;
                font-family: monospace;
            }
            h2 a {
                margin-left: 10px;
            }
        </style>
    </head>
<body>
    <a href="/cloud">&laquo; Home</a>
    <h1>
        IP Camera Viewer
        <button id="autorefresh" type="button" data-enabled="yes">Auto Refresh: On</button>
        <button id="toggle" type="button">Show FTP Upload Information</button>
    </h1>
    <h2>
        <a class="draw" href="#+10">10</a>
        <a class="draw" href="#+50">50</a>
        <a class="draw" href="#+200">200</a>
        <a class="draw" href="#+1000">1000</a>
    </h2>
    <h2>
        <span id="dirs"></span>
    </h2>

    <div id="login">
        <table>
            <caption>FTP Upload Information</caption>
            <tbody>
                <tr>
                    <td>Username</td>
                    <td>cam1, cam2, cam3, ..., cam10</td>
                </tr>
                <tr>
                    <td>Password</td>
                    <td><span class="password"></span></td>
                </tr>
                <tr>
                    <td>Upload Directory</td>
                    <td>/</td>
                </tr>
                <tr>
                    <td>Mode</td>
                    <td>Passive (PASV)</td>
                </tr>
            </tbody>
        </table>
    </div>
    <div id="images">
    </div>
    <script src="static/jquery.js"></script>
    <script src="static/helper.js"></script>
</body>
</html>
HTML



cat <<CRON >/etc/cron.hourly/delete-old-pictures
#!/bin/bash

find /data/cameras/ -type f -mtime +3 -name \*.jpg -exec rm {} \;
find /data/cameras/ -type d -empty -exec rmdir {} \;

CRON



# We're ready.
curl http://169.254.169.254/ping


# Move images on upload.
tail -F /var/log/vsftpd.log | perl -ne '
	next unless /OK UPLOAD/;
	my ($camera, $filename) = /\[(\w+)].*,\s+"([^"]+)"/;
	$filename = "/$camera" . $filename;
	my ($md5) = `md5sum "$filename"` =~ /^(\w+)\s+/;
	my ($date) = `date +%Y-%m-%d` =~ /(\S+)/;
	my $dst_dir = "/data/cameras/$date";
	my $dst_filename = "$dst_dir/$camera-$md5.jpg";

	system "/bin/mkdir", "-p", $dst_dir if not -d $dst_dir;
	print "$filename -> $dst_filename\n";
	system "/bin/mv", $filename, $dst_filename;
	system "/bin/chown", "www-data:www-data", $dst_filename;
'





