# Targets (targets with "*" require the CLIENT variables on the command line):
#   all		Sets up CA
#   add*	Used by 'zip'
#   zip*	Used for making a client cert for a person's own computer [TBA]
#   ctarball*	Used for making a client cert for a Linux host
#   revoke*	Revoke's a given cert and re-generates the CRL (don't forget to install it on the server)
#   tarball	For installation on the server
#   install_keys  Run on a Linux host after extracting the tarball; specify DEST [TBA]
#
# The following variables may/must be present on the command line:
#   CLIENT (if building a client; mandatory)
#   CLIENT_REQ_ARGS= (if building a client; used to require a passphrase)
#   SERVER_ID (if building a server; optional)
#   KEY_NAME (optional; If not using shared keys between connections, override this; default is CLIENT)
#   KEY_DEPT (optional; specifies organizationalUnitName and alters config file name)
#   CN (optional; specifies commonName)
#   KEY_DIR (optional)
#   KEY_CONFIG (optional)
#   REQ_ARGS (optional; can be used to pass "-subj 'arg'" -- NOTE QUOTES)
#   CA_ARGS (optional; can be used to pass "-batch")
#   CA_REQ_ARGS= (when building a ca; used to require a passphrase)
#
# The following environment variables may/must be present (see "vars" file):
#   KEY_ORG (mandatory)
#   SERVER_FQDN (mandatory)
#   KEY_SIZE (optional; do not change after CA is built)
#
# TO-DO:
#   + add 'remove' target; runs "rm -rf keys/$(CLIENT).* clients/.$(CLIENT)_*stamp clients/$(CLIENT)"
#   + make 'remove' target depnd on 'revoke' target

# == Sanity checking ==
ifeq ($(origin KEY_ORG), undefined)
  $(error KEY_ORG not set in "vars" file)
endif
ifeq ($(KEY_ORG), )
  $(error KEY_ORG not set in "vars" file)
endif

# SERVER_FQDN is checked later because it's only needed when building client tarballs


# == Setup ==
.EXPORT_ALL_VARIABLES:

ifeq ($(origin CLIENT), undefined)
  ## CN = $(SERVER_ID)
  CN =
  # must be a single word
  CLIENT = someone
else
  ifeq ($(origin CN), undefined)
    $(warning Warning: CN not specified on command line.  If commonName is set)
    $(warning differently to "$(CLIENT)", MS-Windows connection will be refused.)
    CN = $(CLIENT)
  else
    $(warning Warning: CN specified on command line; will set commonName)
    $(warning default.  If not chosen, MS-Windows connection will be refused.)
  endif
endif
# don't use a passphrase
CLIENT_REQ_ARGS = -nodes

SERVER = server
SERVER_ID = $(SERVER)

CA_REQ_ARGS=-nodes

DEST = /tmp/keys

KEY_CONFIG = openssl.cnf
KEY_DIR = keys

# Settings that depend on whether certain environment variables are set
ifeq ($(origin SERVER_SUBNET), undefined)
  SERVER_SUBNET_SUBST =
else
  SERVER_SUBNET_SUBST = -e '/{{SERVER_SUBNET}}/ { s@@$(SERVER_SUBNET)@ ; s/\#\# // }'
endif

# These might be overriden by an environment variable
KEY_SIZE ?= 2048
ifeq ($(origin KEY_DEPT), undefined)
  CONF_NAME = $(KEY_ORG)
  KEY_DEPT =
else
  CONF_NAME = $(KEY_DEPT)
endif

KEY_NAME = $(CLIENT)


CLIENT_DEPS = clients/$(CLIENT).conf clients/.$(CLIENT)_stamp


# *** TARGETS ***
.PHONY: add all
# make sure all required files exist
all: $(KEY_DIR)/ca.key


# == Client ==
# this target generates the following in clients/:
#   + a pubkey auth client config file called $CLIENT.conf
#   + a subdirectory called $CLIENT containing:
#       - a symbolic link called conf.d/$KEY_ORG.conf
#         (it will instead be called conf.d/$KEY_DEPT.conf if $KEY_DEPT is set)
#       - a symbolic link called secrets.d/$KEY_ORG.conf
#         (it will instead be called secrets.d/$KEY_DEPT.conf if $KEY_DEPT is set)
#       - subdirectories called certs, cacerts and private containing symlinks
#         to the client & ca certs and the the client key, respectively
# Makes sure that if the config file is re-created, the zip/tarball will be too.
add: $(CLIENT_DEPS)

clients/$(CLIENT).conf: clients/_template.conf $(KEY_DIR)/ca.crt $(KEY_DIR)/server.crt
	@if [ -z "$$SERVER_FQDN" ] ; then echo ERROR: SERVER_FQDN not present in environment 2>&1; exit 3 ; fi
	sed -e "s/{{SERVER_FQDN}}/$$SERVER_FQDN/" \
	    -e "s/{{CLIENT}}/$(CLIENT)/" \
	    -e "s/{{CONF_NAME}}/$(CONF_NAME)/" \
	    -e "s#{{CA_DN}}#$$(openssl x509 -subject -noout -in "$(KEY_DIR)/ca.crt" | \
	    	 sed -e 's/subject= //')#" \
	    -e "s#{{SERVER_DN}}#$$(openssl x509 -subject -noout -in "$(KEY_DIR)/server.crt" | \
	    	 sed -e 's/subject= //')#" \
	    $(SERVER_SUBNET_SUBST) \
	  clients/_template.conf > "$@"

# -- directory containing links to be archived --
# Use stamp files rather than phony targets to avoid always rebuilding
clients/.$(CLIENT)_stamp: clients/.$(CLIENT)_conf-link-stamp clients/.$(CLIENT)_cert-link-stamp clients/.$(CLIENT)_secrets-stamp
	touch $@

clients/$(CLIENT):
	mkdir -p $@

clients/.$(CLIENT)_cert-link-stamp: $(KEY_DIR)/$(CLIENT).crt $(KEY_DIR)/$(CLIENT).key | clients/$(CLIENT)/certs clients/$(CLIENT)/private clients/$(CLIENT)/cacerts
	ln -s --force ../../../$(KEY_DIR)/$(CLIENT).crt "clients/$(CLIENT)/certs/$(CONF_NAME).crt"
	ln -s --force ../../../$(KEY_DIR)/$(CLIENT).key "clients/$(CLIENT)/private/$(KEY_NAME).key"
	ln -s --force ../../../$(KEY_DIR)/ca.crt "clients/$(CLIENT)/cacerts/$(CONF_NAME).crt"
	touch $@

clients/$(CLIENT)/certs clients/$(CLIENT)/cacerts:
	mkdir -p $@
clients/$(CLIENT)/private:
	install -d -m 700 $@

.PHONY: conf_link
conf_link: clients/.$(CLIENT)_conf-link-stamp
clients/.$(CLIENT)_conf-link-stamp: clients/$(CLIENT).conf | clients/$(CLIENT)/conf.d
	ln -s --force ../../$(CLIENT).conf "clients/$(CLIENT)/conf.d/$(CONF_NAME).conf"
	touch $@

clients/$(CLIENT)/conf.d:
	mkdir -p $@

# -- real .key and .crt files --
$(KEY_DIR)/$(CLIENT).crt: $(KEY_DIR)/$(CLIENT).csr $(KEY_DIR)/ca.crt $(KEY_DIR)/ca.key
	openssl ca -config $(KEY_CONFIG) $(CA_ARGS) \
	  -in $(KEY_DIR)/$(CLIENT).csr -out $(KEY_DIR)/$(CLIENT).crt

# -nodes isn't specified here because it might be in $(CLIENT_REQ_ARGS)
$(KEY_DIR)/$(CLIENT).key $(KEY_DIR)/$(CLIENT).csr: | $(KEY_DIR)/ca.key
	openssl req -config $(KEY_CONFIG) $(REQ_ARGS) $(CLIENT_REQ_ARGS) \
	  -new -out $(KEY_DIR)/$(CLIENT).csr \
	  -newkey rsa:$(KEY_SIZE) -keyout $(KEY_DIR)/$(CLIENT).key
	chmod 0600 $(KEY_DIR)/$(CLIENT).key

# This creates a file with spaces in the name, which is therefore no use as a target
clients/.$(CLIENT)_secrets-stamp: $(KEY_DIR)/$(CLIENT).crt clients/.$(CLIENT)_conf-link-stamp | clients/$(CLIENT)/secrets.d
	openssl x509 -subject -noout -in "$(KEY_DIR)/$(CLIENT).crt" | \
	 sed -e 's/subject= \(.*\)/"\1" : RSA "$(KEY_NAME).key"/' \
	   > "clients/$(CLIENT)/secrets.d/$(CONF_NAME).secrets"
	touch $@

clients/$(CLIENT)/secrets.d:
	mkdir -p $@

# -- distribution archive --
.phony: ctarball
# this target creates a tarball (no symlinks) for distribution to a client machine
ctarball: strongSwan_$(CLIENT).tar.gz
strongSwan_$(CLIENT).tar.gz: $(CLIENT_DEPS) ipsec.conf.snippet ipsec.secrets.snippet
	tar czhvf $@ \
	 ipsec.conf.snippet ipsec.secrets.snippet \
	 -C clients/$(CLIENT) \
	 certs private cacerts \
	 "conf.d/$(CONF_NAME).conf" "secrets.d/$(CONF_NAME).secrets"

# -- util targets --
# Hint: use with CLIENT=\* (but be prepared for warnings)
conf_clean:
	rm -f clients/$(CLIENT)/*.ovpn
	rm -f clients/.$(CLIENT)_conf-link-stamp

revoke:
	openssl ca -config $(KEY_CONFIG) -revoke "$(KEY_DIR)/$(CLIENT).crt"
	$(MAKE) tarball


# == Server ==
$(KEY_DIR)/dh$(KEY_SIZE).pem:
	openssl dhparam -out $(KEY_DIR)/dh$(KEY_SIZE).pem $(KEY_SIZE)

$(KEY_DIR)/$(SERVER_ID).crt: $(KEY_DIR)/$(SERVER_ID).csr $(KEY_DIR)/ca.crt $(KEY_DIR)/ca.key
	openssl ca -config $(KEY_CONFIG) $(CA_ARGS) \
	  -extensions server -days 3650 \
	  -in $(KEY_DIR)/$(SERVER_ID).csr -out $(KEY_DIR)/$(SERVER_ID).crt

$(KEY_DIR)/$(SERVER_ID).key $(KEY_DIR)/$(SERVER_ID).csr: $(KEY_DIR)/ca.key
	CN="$(SERVER_ID)" openssl req -config $(KEY_CONFIG) $(REQ_ARGS) \
	  -new -extensions server -out $(KEY_DIR)/$(SERVER_ID).csr \
	  -newkey rsa:$(KEY_SIZE) -keyout $(KEY_DIR)/$(SERVER_ID).key -nodes
	chmod 0600 $(KEY_DIR)/$(SERVER_ID).key

# updates the CRL whenever index.txt has changed
# (avoids having to generate the CRL every time a cert is revoked,
# but does take the safe option of making $(SERVER_ID).tar.gz transitively dependent
# on $(KEY_DIR)/index.txt)
$(SERVER_ID)/ipsec.d/crls/banned_certs.crl: $(KEY_DIR)/ca.key $(KEY_DIR)/index.txt | $(SERVER_ID)/ipsec.d
	openssl ca -config $(KEY_CONFIG) \
	  -gencrl -out $@

ipsec.conf.snippet:
	echo "include /etc/ipsec.d/conf.d/*.conf" > $@

ipsec.secrets.snippet:
	echo "include /etc/ipsec.d/secrets.d/*.secrets" > $@

$(SERVER_ID)/ipsec.secrets: $(KEY_DIR)/$(SERVER_ID).crt
	openssl x509 -subject -noout -in "$^" | \
	 sed -e 's/subject= \(.*\)/"\1" : RSA "$(SERVER_ID).key"/' > "$@"

.$(SERVER_ID)_cert-link-stamp: $(KEY_DIR)/$(SERVER_ID).crt $(KEY_DIR)/$(SERVER_ID).key | $(SERVER_ID)/ipsec.d
	ln -s --force ../../../$(KEY_DIR)/$(SERVER_ID).crt $(SERVER_ID)/ipsec.d/certs
	ln -s --force ../../../$(KEY_DIR)/$(SERVER_ID).key $(SERVER_ID)/ipsec.d/private
	ln -s --force ../../../$(KEY_DIR)/ca.crt $(SERVER_ID)/ipsec.d/cacerts
	touch $@

$(SERVER_ID)/ipsec.d:
	mkdir -p $@ $@/certs $@/cacerts $@/crls
	install -d -m 700 $@/private

# -- distribution archive --
.phony: tarball
tarball: $(SERVER_ID).tar.gz
# to be extracted into /etc
$(SERVER_ID).tar.gz: $(SERVER_ID)/ipsec.conf $(SERVER_ID)/ipsec.secrets $(SERVER_ID)/ipsec.d/crls/banned_certs.crl .$(SERVER_ID)_cert-link-stamp
	tar czhvf $@ \
	 -C $(SERVER_ID) \
	 ipsec.conf ipsec.secrets \
	 ipsec.d/cacerts/ca.crt ipsec.d/certs/$(SERVER_ID).crt \
	 ipsec.d/private/$(SERVER_ID).key ipsec.d/crls/banned_certs.crl \
	 scripts/routing_on.up


# == CA ==
# Note: $(REQ_ARGS) is not used
$(KEY_DIR)/ca.crt: | $(KEY_DIR)/ca.key
$(KEY_DIR)/ca.key: | $(KEY_DIR)/index.txt $(KEY_DIR)/serial
	@echo Creating CA key and certificate
	openssl req -config $(KEY_CONFIG) \
	  -new -x509 -days 3650 -out $(KEY_DIR)/ca.crt \
	  -newkey rsa:$(KEY_SIZE) -keyout $(KEY_DIR)/ca.key $(CA_REQ_ARGS)
	chmod 0600 $(KEY_DIR)/ca.key

$(KEY_DIR)/index.txt: | $(KEY_DIR)
	touch $@

$(KEY_DIR)/serial: | $(KEY_DIR)
	echo 01 > $@

$(KEY_DIR):
	mkdir -p $@

# == Other ==
.PHONY: install_keys
# used to install keys as root for a specific client into a specfic directory
