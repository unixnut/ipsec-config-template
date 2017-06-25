== Introduction ==

Implements a full PKI solution for IPsec VPNs, using tunnel mode and authorised
(and revokable) certificates.  Currently only supports Linux/Unix clients.

Tested with [strongSwan](https://www.strongswan.org/).

You are responsible for the security of your installation; for tips, see
https://wiki.strongswan.org/projects/strongswan/wiki/SecurityRecommendations

The config files interpret 'left' as local (initiator) and 'right' as remote
(responder), as recommended by the strongSwan website.  A git branch called
'orthogonal' will be created at some point that interprets 'left' as initiator
and 'right' as responder, which means that regardless of whether you're looking
at the client or server config, 'left' and 'right' mean the same thing.

== CA operation ==

***TBA***

See `Makefile` for some basic instructions.
**Beware**: by default, client keys have no passphrase.

== Server setup ==

**Warning**: This will overwrite your existing `/etc/ipsec.conf` and
`/etc/ipsec.secrets` files.

    sudo apt-get install strongswan
    sudo tar xf /tmp/server.tar.gz -C /etc
    sudo service ipsec restart

== Client setup ==

The `tar` command extracts some .snippet files that are not used directly;
instead, when running the sudoedit commands, paste in the contents of the
respective .snippet file.

    sudo apt-get install strongswan
    sudo tar xf strongSwan_xyz.tar.gz -C /etc/ipsec.d/
    sudoedit /etc/ipsec.conf
    sudoedit /etc/ipsec.secrets
    sudo service ipsec restart

== Remote subnet access ==
This is the "`left|rightsubnet = <ip subnet>[[<proto/port>]][,...]`"
[config item](https://wiki.strongswan.org/projects/strongswan/wiki/ConnSection#leftright-End-Parameters).

If just the client specifies `rightsubnet`, then the client will be able to
access the server's private IP address, but nothing else in the subnet.  If the
server config defines `leftsubnet` *and* the client specifies `rightsubnet`, then
the client will be able to access the server's entire subnet.  If neither end
(or just the server) defines it, remote subnet access doesn't work.

== TO-DO ==
Generate server/ipsec.conf from server/_ipsec_template.conf to allow `leftca`
and `leftsubnet` to be set automatically.
