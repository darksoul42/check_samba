#!/bin/sh
cd `dirname $0`
DIR=`pwd`
SCRIPT=`basename $0`

usage()
{
	echo "Usage: $0 -H|--hostname <HOSTNAME> -P|--principal <PRINCIPAL> -R|--realm <REALM> [-S|--share <SHARE>]
	[-p|--password <PASSWORD] [-s|--stdin-password] [-C|--config <KERBEROS_CONFIG_FILE>]
	[-T|--keytab <KEYTAB>] [-w|--warning <WARNING_TIME>] [-c|--critical <CRITICAL_TIME>] [-t|--timeout <TIMEOUT>]
	[-L|--label <LABEL>] [-d|--debug] [-v|--verbose] [-h|--help]"
	exit 1
}

alarm() { perl -e 'alarm shift; exec @ARGV' "$@"; }

missing() { echo "Missing required command $1!"; exit 3; }

###############################################################################
# Parse arguments

GETOPT_TEMP=`getopt -o H:P:p:sC:R:S:T:L:w:c:t:dvih --long hostname:,principal:,password:,stdin-password,config:,realm:,share:,keytab:,label:,warning:,critical:,timeout:,debug,verbose,ignore-stdout,help -n "$SCRIPT" -- "$@"`
eval set -- "$GETOPT_TEMP"

DEBUG=0
VERBOSE=0
DEFAULT_TIMEOUT=20
DEFAULT_LABEL="SMB LOGON"
WARNING_TIME=5
CRITICAL_TIME=10
STDIN_PASS=0
USE_PASS=1
IGNORE_OUTPUT=0

while true ; do
  case "$1" in
  -H|--hostname)	HOSTNAME=$2;		shift 2 ;;
  -P|--principal)	case $2 in
			*@*) echo "Invalid principal '$2': please only type the user portion (before the @)"; exit 1 ;;
			*) PRINCIPAL=$2; ;;
			esac;			shift 2 ;;
  -p|--password)	PASS=$2;		shift 2 ;;
  -s|--stdin-password)	STDIN_PASS=1;		shift ;;
  -C|--config)		CONFIG=$2;		shift 2 ;;
  -R|--realm)		REALM=$2;		shift 2 ;;
  -S|--share)		SHARE=$2;		shift 2 ;;
  -T|--keytab)		KEYTAB=$2; USE_PASS=0;	shift 2 ;;
  -L|--label)		LABEL=$2;		shift 2 ;;
  -w|--warning)		WARNING_TIME=$2;	shift 2 ;;
  -c|--critical)	CRITICAL_TIME=$2;	shift 2 ;;
  -t|--timeout)		TIMEOUT=$2;		shift 2 ;;
  -d|--debug)		DEBUG=1; VERBOSE=1; 	shift ;;
  -v|--verbose)		VERBOSE=1;		shift ;;
  -i|--ignore-stdout)	IGNORE_OUTPUT=1;	shift ;;
  -h|--help)		usage ;;
  --) shift ; break ;;
  *) echo "Internal error!"; exit 1 ;;
  esac
done

if [ -z "${HOSTNAME}" -o -z "${PRINCIPAL}" -o -z "${REALM}" ] ; then usage ; fi

LABEL=${LABEL:-$DEFAULT_LABEL}
TIMEOUT=${TIMEOUT:-$DEFAULT_TIMEOUT}

if [ -n "$WARNING_TIME" -a -n "$CRITICAL_TIME" ] ; then
	if [ "$WARNING_TIME" -le 0 ] ; then
		echo "ERROR: Warning time can't be < 0 !"
	fi
	if [ "$CRITICAL_TIME" -le 0 ] ; then
		echo "ERROR: Critical time can't be < 0 !"
	fi
	if [ "$WARNING_TIME" -ge "$CRITICAL_TIME" ] ; then
		echo "ERROR: Invalid warning and critical options, warning must be < critical ! ($WARNING_TIME < $CRITICAL_TIME)"
		exit 1
	fi
fi

if [ "$STDIN_PASS" -gt 0 ] ; then
	read PASS
fi
if [ -z "$PASS" -a "$USE_PASS" -gt 0 ] ; then
	echo -n "ERROR: Password required, but not specified."
	if [ "$STDIN_PASS" -gt 0 ] ; then
		echo -n " You did not pass the password via standard input."
	fi
	echo
	exit 3
fi

###############################################################################
# Execution environment sanity check
for command in kinit smbclient ; do
	which $command >/dev/null || missing $command
done

###############################################################################
# Execute command
tmp_stderr=`mktemp`
tmp_stdout=`mktemp`
retcode=0; kinit_code=0; kinit_fail=0; smbclient_code=0;
start_time=`date +%s`

# First ensure we use another credential cache store for this script and this hostname
export KRB5CCNAME="/tmp/krb5cc.user`id -u`.`basename ${0}`.$HOSTNAME"

# Then, if we have a custom Kerberos configuration file, ensure we use it
if [ -n "$CONFIG" ] ; then
	export KRB5_CONFIG="$CONFIG"
fi

# Apply requested authentication mode
if [ -n "$KEYTAB" ] ; then
	kinit_output=`alarm $TIMEOUT kinit -t "${KEYTAB}" -k -V "${PRINCIPAL}@${REALM}" 2>&1`
	kinit_last=`echo "$kinit_output" | tail -1`
	kinit_code="$?"
	if [ "$kinit_code" -ne 0 ] ; then
		ERROR_REASON="kinit failed : ${kinit_last}"
		retcode=2; kinit_fail=1
	fi
elif [ -n "$PASS" ] ; then
	kinit_output=`echo "$PASS" | kinit -V "${PRINCIPAL}@${REALM}" 2>&1`
	kinit_code="$?"
	if [ "$kinit_code" -ne 0 ] ; then
		ERROR_REASON="kinit failed : ${kinit_last}"
		retcode=2; kinit_fail=1
	fi
fi
if [ "$kinit_fail" -eq 0 ] ; then
	if [ -z "$SHARE" ] ; then # No share ? Just check the share listing.
		alarm $TIMEOUT smbclient -k -L $HOSTNAME 2>"${tmp_stderr}" >"${tmp_stdout}"
		smbclient_code="$?"
	else # Share ? Try to connect.
		alarm $TIMEOUT smbclient -k "//$HOSTNAME/$SHARE" -c ls 2>"${tmp_stderr}" >"${tmp_stdout}"
		smbclient_code="$?"
	fi
	if [ "$smbclient_code" -ne 0 ] ; then retcode=2; ERROR_REASON=`cat "${tmp_stdout}"`; fi
fi
end_time=`date +%s`
delay=$((end_time-start_time))

###############################################################################
# Based on execution delay, determine if we have a warning or a critical
if [ -n "$WARNING_TIME" -o -n "$CRITICAL_TIME" ] ; then
	if [ "$delay" -ge "$WARNING_TIME" ] ; then
		if [ $retcode -lt 1 ] ; then
			ERROR_REASON="${ERROR_REASON}, execution took $delay seconds"
			retcode=1;
		fi;
	fi
	if [ "$delay" -ge "$CRITICAL_TIME" ] ; then
		if [ $retcode -lt 2 ] ; then
			ERROR_REASON="${ERROR_REASON}, execution took $delay seconds"
			retcode=2;
		fi;
	fi
fi

###############################################################################
# Calculate response
if [ "$IGNORE_OUTPUT" -eq 0 ] ; then
	RESPONSE=`cat "${tmp_stderr}" | head -1`
else
	RESPONSE="SMB Session Established to $HOSTNAME"
fi
case $kinit_code in
142) ERROR_REASON="${ERROR_REASON}, execution timeout while running kinit" ;;
esac
case $smbclient_code in
142) ERROR_REASON="${ERROR_REASON}, execution timeout while running smbclient" ;;
esac

###############################################################################
# Verbose mode
(if [ "$VERBOSE" -gt 0 ] ; then
	echo "--"
	echo "Kinit output :"
	echo "$kinit_output"
	echo "--"
	echo "Kinit return code : $kinit_code"
	echo "--"
	echo "SMBClient Standard error output :"
	cat "${tmp_stderr}"
	echo "--"
	echo "SMBClient Standard output :"
	cat "${tmp_stdout}"
	echo "--"
	echo "SMBclient return code : $smbclient_code"
fi) >&2

###############################################################################
# Clean up temp files
if [ -n "$KEYTAB" -a "$kinit_fail" -eq 0 ] ; then kdestroy >/dev/null 2>&1; fi
rm "${tmp_stderr}"
rm "${tmp_stdout}"

###############################################################################
# Display result and return exit code
case $retcode in
0) echo "$LABEL OK: $RESPONSE" ;;
1) echo "$LABEL WARNING: $ERROR_REASON" ;;
2) echo "$LABEL CRITICAL: $ERROR_REASON" ;;
3) echo "$LABEL UNKNOWN: $ERROR_REASON" ;;
esac

exit $retcode
