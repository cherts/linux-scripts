#
# Build nginx (use custom openssl via rpath) with image_filter, xslt and njs module
#
# Author: Eric Pruitt (http://www.codevat.com)
# Author: Mikhail Grigorev (sleuthhound@gmail.com)
#
# License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
#

NGINX_VERSION=1.29.3
NJS_VERSION=0.9.4
OPENSSL_VERSION=3.5.4
PCRE2_VERSION=10.47
ZLIB_VERSION=1.3.1
XSLT_VERSION=1.1
XSLT_FULL_VERSION=1.1.43
XML_VERSION=2.9
XML_FULL_VERSION=2.9.9

# URL of nginx source tarball
NGINX_SOURCE=https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
# URL of NJS module source tarball
NJS_SOURCE=https://github.com/nginx/njs/archive/refs/tags/${NJS_VERSION}.tar.gz
# URL of OuickJS git repo
QJS_SOURCE=https://github.com/bellard/quickjs
# URL of OpenSSL source tarball
OPENSSL_SOURCE=https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
# URL of PCRE source tarball
PCRE2_SOURCE=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz
# URL of zlib source tarball
ZLIB_SOURCE=https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz
# URL of xslt source tarball
XSLT_SOURCE=https://download.gnome.org/sources/libxslt/$(XSLT_VERSION)/libxslt-$(XSLT_FULL_VERSION).tar.xz
# URL of xml2 source tarball
XML_SOURCE=https://download.gnome.org/sources/libxml2/$(XML_VERSION)/libxml2-$(XML_FULL_VERSION).tar.xz

# Static lib directory
LIB_DIR=/opt/local

all: nginx/nginx

amroot:
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Must be root to install dependencies."; \
		exit 1; \
	fi

ifeq (/etc/debian_version, $(wildcard /etc/debian_version))
deps: amroot
	apt-get install wget libxslt1-dev libxml2-dev zlib1g-dev libbz2-dev
else ifeq (/etc/redhat-release, $(wildcard /etc/redhat-release))
deps: amroot
	yum -y install wget gcc gcc-c++ make zlib-devel
else
deps:
	echo "Linux distribution not supported; install dependencies manually."
	exit 1
endif

clean:
	rm -rf nginx openssl pcre zlib njs quickjs libxslt

nginx.tar.gz:
	wget -O $@ $(NGINX_SOURCE)

nginx: nginx.tar.gz
	tar xf $<
	mv nginx-*/ $@
	touch $@

njs.tar.gz:
	wget -O $@ $(NJS_SOURCE)

njs: njs.tar.gz
	tar xf $<
	mv njs-* $@
	touch $@

quickjs:
	git clone $(QJS_SOURCE)
	touch $@

quickjs/build: quickjs
	cd quickjs && CFLAGS='-fPIC' make
	cd ..

libxslt.tar.xz:
	wget -O $@ $(XSLT_SOURCE)

libxslt: libxslt.tar.xz
	tar xf $<
	mv libxslt*/ $@
	touch $@

libxslt/build: libxslt
	cd libxslt && ./configure --prefix=$(LIB_DIR) --with-libxml-prefix=$(LIB_DIR) --disable-static --without-python && make install
	cd ..

libxml2.tar.xz:
	 wget -O $@ $(XML_SOURCE)

libxml2: libxml2.tar.xz
	tar xf $<
	mv libxml2*/ $@
	touch $@

libxml2/build: libxml2
	cd libxml2 && ./configure --prefix=$(LIB_DIR) --disable-static --without-python && make install
	cd ..

pcre.tar.gz:
	wget -O $@ $(PCRE2_SOURCE)

pcre: pcre.tar.gz
	tar xf $<
	mv pcre*/ $@
	touch $@

openssl.tar.gz:
	wget -O $@ $(OPENSSL_SOURCE)

openssl: openssl.tar.gz
	tar xf $<
	mv openssl*/ $@
	touch $@

openssl/build: openssl
	cd openssl && ./config --prefix=$(LIB_DIR) && make && make all install
	echo "$(LIB_DIR)/lib64" > /etc/ld.so.conf.d/openssl3.conf && ldconfig
	cd ..

zlib.tar.gz:
	wget -O $@ $(ZLIB_SOURCE)

zlib: zlib.tar.gz
	tar xf $<
	mv zlib*/ $@
	touch $@

build:
	mkdir -p $(LIB_DIR)

nginx/nginx: build nginx njs pcre zlib openssl/build libxml2/build libxslt/build quickjs/build
	cd nginx && ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-cc-opt="-O2 -static -static-libgcc -I $(LIB_DIR)/include -I ../quickjs -I $(LIB_DIR)/include/libxml2" \
        --with-ld-opt="-L $(LIB_DIR)/lib64 -L ../quickjs -L $(LIB_DIR)/lib -ldl -Wl,-rpath,$(LIB_DIR)/lib64" \
        --with-openssl=$(LIB_DIR) \
        --with-pcre=../pcre \
        --with-zlib=../zlib \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-poll_module \
        --with-select_module \
        --with-http_image_filter_module \
        --with-http_geoip_module \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre-jit \
        --with-http_xslt_module \
        --add-module=../njs/nginx
	cd nginx && $(MAKE)
	echo "Build finished, use binary ./nginx/objs/nginx"

.PHONY: all clean cleaner amroot deps
