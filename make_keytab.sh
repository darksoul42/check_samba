#!/bin/sh
cd `dirname $0`
DIR=`pwd`
SCRIPT=`basename $0`

usage()
{
	echo "Usage: KRB5_CONFIG=/path/krb5.conf $0 user [<REALM1..N>] < password-from-stdin"
	exit 1
}

KRB_USERNAME=$1
if [ -z "$KRB_USERNAME" ] ; then usage ; fi
shift
KRB_REALMS=$@
read KRB_PASSWORD
if [ -z "$KRB_CIPHER" ] ; then KRB_CIPHER=aes256-cts-hmac-sha1-96 ; fi

if [ -z "$KRB_PASSWORD" -o -z "$KRB_REALMS" ] ; then usage ; fi

for realm in $KRB_REALMS ; do
	printf "%b" "addent -password -p $KRB_USERNAME@$realm -k 1 -e $KRB_CIPHER\n$KRB_PASSWORD\nwrite_kt $KRB_USERNAME.keytab" | ktutil
done
