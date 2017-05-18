#! /bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. install.conf

apt-get update
apt-get install aptitude dbus vim curl -y

/etc/init.d/dbus start

LDAP_CONFIG="/etc/ldap/slapd.d/cn=config"
LDAP_CONFIG_FILE="olcDatabase={1}mdb.ldif"

echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
echo $HOSTNAME  > /etc/hostname

hostnamectl set-hostname $HOSTNAME

aptitude install slapd ldap-utils ldapscripts samba -y
service slapd start


base_dn=$(grep olcSuffix "$LDAP_CONFIG/$LDAP_CONFIG_FILE" | awk '{print $2}')
export base_dn
admin_user=$(grep olcRootDN "$LDAP_CONFIG/$LDAP_CONFIG_FILE" |  awk '{print $2}')
export admin_user

echo "You configure LDAP with base dn: $base_dn"
echo "Your Ldap Admin is: $admin_user"


echo "Is LDAP DN is correct ?"
echo "yes/no and press [ENTER]: "
read check_dn

if  [ $check_dn == "no" ] ; then
        exit
fi

#### Configuring Samba Ldap Schema:
zcat /usr/share/doc/samba/examples/LDAP/samba.schema.gz > /etc/ldap/schema/samba.schema
cd /root/
cat <<EOF > samba.conf
include          /etc/ldap/schema/core.schema
include          /etc/ldap/schema/cosine.schema
include          /etc/ldap/schema/nis.schema
include          /etc/ldap/schema/inetorgperson.schema
include          /etc/ldap/schema/samba.schema
EOF


mkdir /tmp/slapd.d
slaptest -f samba.conf -F /tmp/slapd.d/
cp "/tmp/slapd.d/cn=config/cn=schema/cn={4}samba.ldif" "/etc/ldap/slapd.d/cn=config/cn=schema"
chown openldap: '/etc/ldap/slapd.d/cn=config/cn=schema/cn={4}samba.ldif'
/etc/init.d/slapd stop
/etc/init.d/slapd start

ldapsearch -LLLQY EXTERNAL -H ldapi:/// -b cn=schema,cn=config "(objectClass=olcSchemaConfig)" dn  | grep samba


##  Installing PHP LDAP Admin:
apt-get install phpldapadmin -y
## Get external IP:
ext_ip=$(curl ifconfig.co 2>/dev/null)
export ext_ip
echo "PHP  LDAP WEB Console available here:  http://$ext_ip/phpldapadmin/"



## Configuring LDAP structure:

cd /root/
cat <<EOF > base.ldif
dn: ou=$LDAP_MAIN_OU,$base_dn
objectClass: organizationalUnit
ou: $LDAP_MAIN_OU

dn: OU=$LDAP_SUB_OU,ou=$LDAP_MAIN_OU,$base_dn
objectClass: organizationalUnit
ou: $LDAP_SUB_OU
EOF

echo "You must  enter you LDAP ADMIN Password below: "
ldapadd -x -D $admin_user  -W -f base.ldif


echo "Please visit PHP  LDAP WEB Console to validate Ldap structure"
echo "Is LDAP structure is correct ?"
echo "yes/no and press [ENTER]: "
read check_structure

if  [ $check_structure == "no" ] ; then
        exit
fi



## installing LDAP SASL
apt-get install libsasl2-2 libsasl2-modules sasl2-bin -y
sed -i 's/START=no/START=yes/' /etc/default/saslauthd
sed -i 's/MECHANISMS="pam"/MECHANISMS="ldap"/' /etc/default/saslauthd

cat <<EOF > /etc/saslauthd.conf
ldap_servers: $WINDOWS_AD
ldap_search_base: $WINDOWS_AD_BASE
ldap_timeout: 10
ldap_filter: sAMAccountName=%U
ldap_bind_dn: $WINDOWS_BIND_DN
ldap_password: $WINDOWS_AD_BIND_PASSWORD
ldap_deref: never
ldap_restart: yes
ldap_scope: sub
ldap_use_sasl: no
ldap_start_tls: no
ldap_version: 3
ldap_auth_method: bind
EOF


/etc/init.d/saslauthd restart
ps axux | grep sasl

cat <<EOF > /usr/lib/sasl2/slapd.conf
pwcheck_method: saslauthd
saslauthd_path: /var/run/saslauthd/mux
EOF


ldapmodify -Y external -H ldapi:/// <<EOF
dn: cn=config
add: olcSaslHost
olcSaslHost: 127.0.0.1
-
add: olcSaslSecProps
olcSaslSecProps: none
EOF

echo "Need to check if sasl auth is working correctly"
echo "Please enter any test user SAMAccountName and Password below:"
echo -n "Enter test user SAMAccountName  and press [ENTER]: "
read test_username
echo -n "Enter test user password and press [ENTER]: "
read -s test_userpass
echo


testsaslauthd -u $test_username -p $test_userpass

echo "If you got  \"Success\" we successfully configured LDAP"
echo "yes/no and press [ENTER]: "
read check_ldap

if  [ $check_ldap == "no" ] ; then
        exit
fi


## Installing Java

## https://www.digitalocean.com/community/tutorials/how-to-install-java-with-apt-get-on-debian-8

apt-get install software-properties-common -y
add-apt-repository "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main"
apt-get update
echo "Please confirm Java licence terms bellow: "
apt-get install oracle-java8-installer -y
echo export JAVA_HOME=/usr/lib/jvm/java-8-oracle/ >> ~/.bashrc
source /root/.bashrc
java -version



## installing LSC:

cd /root/
wget https://lsc-project.org/archives/lsc_2.1.4-1_all.deb
dpkg -i lsc_2.1.4-1_all.deb

cd /etc/lsc
mkdir ad2openldap
cp -pr lsc.xml logback.xml -t ad2openldap
cd ad2openldap/

## installing LSC:

echo "Please enter password for: $admin_user"
read -s ldap_admin_password
export ldap_admin_password

cd /root/
TEMPLATE="lsc_conf.template"
OUTPUT=/etc/lsc/ad2openldap/lsc.xml

echo "#!/bin/bash
cat > $OUTPUT << EOF
`cat $TEMPLATE`
EOF" > $OUTPUT;
bash $OUTPUT



echo "Checking LSC configuration ... "
lsc -f /etc/lsc/ad2openldap/ -s all -c all -n

echo  "You should not see ERRORs or WARNINGs except the latest error about empty destination, it's normal because we have empty OpenLdap server"
echo "Is LSC configured correctly?"
echo "yes/no and press [ENTER]: "
read check_lsc

if  [ $check_lsc == "no" ] ; then
        exit
fi

echo "Next we are going to install Lemon::NG on this host, the ldap sync was configured with cronjob for root user"
echo '* * * * * lsc -f /etc/lsc/ad2openldap/ -s all   2 >> /var/log/lsc/lsc.error.log'  >> /var/spool/cron/crontabs/root
service cron restart

cat /var/spool/cron/crontabs/root   | grep ad2openldap 

insserv saslauthd
insserv slapd
insserv apache2

## Lemon::NG


echo "You will be promted to enter the linux Ldap host and Ldap Base DN"
echo "In most cases you have to to enter:"
echo "LDAP server URI: ldap://localhost:389"
echo "LDAP server search base: $base_dn"

sleep 10

apt install libpam-ldapd  -y
apt install apt-transport-https -y
cat <<EOF > /etc/apt/sources.list.d/lemonldap-ng.list
### LemonLDAP::NG repository
deb     https://lemonldap-ng.org/deb stable main
##deb-src https://lemonldap-ng.org/deb stable main
EOF

wget https://lemonldap-ng.org/_media/rpm-gpg-key-ow2
apt-key add rpm-gpg-key-ow2
apt-get update
aptitude install lemonldap-ng -y



sed -i 's/example\.com/'$LEMON_BASE_HOST'/g' /etc/lemonldap-ng/* /var/lib/lemonldap-ng/conf/lmConf-1.js /var/lib/lemonldap-ng/test/index.pl
cat /etc/lemonldap-ng/for_etc_hosts >> /etc/hosts

lemon_hosts=$(cat   /etc/lemonldap-ng/for_etc_hosts  | awk -F"\t" '{print $2}' | head -n1 )

echo "You have to set up DNS A records for following hosts:"
echo $lemon_hosts
echo
echo
echo "You can edit your local hosts file on your worskstation ..."


echo "Now go to http://manager.stratis.fr to configure Lemon ..."
