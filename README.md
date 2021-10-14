# check_samba

Simplified Nagios plugin for monitoring SMB systems

## Usage

```
Usage: ./check_samba.sh -H|--hostname <HOSTNAME> -P|--principal <PRINCIPAL> -R|--realm <REALM> [-S|--share <SHARE>]
        [-T|--keytab <KEYTAB>] [-w|--warning <WARNING_TIME>] [-c|--critical <CRITICAL_TIME>] [-t|--timeout <TIMEOUT>]
        [-L|--label <LABEL>] [-d|--debug] [-v|--verbose] [-h|--help]
```

It can be used to do the following :
- Checking the SMB service on a host responds
```
./check_samba.sh -H dc1.my.domain.org -R MY.DOMAIN.ORG -P nagios-monitoring -T /etc/nagios3/nagios-monitoring.keytab -w 5 -c 10 -t 20
```
- Checking if a SMB share is reachable
```
./check_samba.sh -H dc1.my.domain.org -R MY.DOMAIN.ORG -P nagios-monitoring -T /etc/nagios3/nagios-monitoring.keytab -S DFS -w 5 -c 10 -t 20
```

It operates by :
- Taking a Kerberos principal, and a keytab file to authenticate
- Wrapping the smbclient command to check authentication

It will then measure delay in establishing a session.
As a default, it will return :
- A WARNING after 5 seconds
- A CRITICAL after 10 seconds
- A timeout after 20 seconds

# Dependencies

- Being a wrapper around the `smbclient` command, it will require the Samba client packages on your distribution.
- As a method of enforcing timeout, the script relies on the perl interpreter's alarm function too.
