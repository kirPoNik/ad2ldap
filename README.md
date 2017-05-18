# ad2ldap
1) Go to install.conf file. Open it with your favorite editor. Please read carefuly comments for each directive, if something is not corresponding your structure, let me know. 
2) If you got install.conf filled out, run install.sh . I propose to run in like following:
	bash install.sh | tee install.log

	if something gets failed, please send the install.log to me. 

3) When OpenLdap installed you'll get output like following:
	You configure LDAP with base dn: <your ldap base dn>
	Your Ldap Admin is: <you ldap admin user dn>
	Is LDAP DN is correct ?
	yes/no and press [ENTER]
	
	Please save base dn and ldap admin user dn and ldap admin password  somewhere.
	Press yes. 
	When you press no, the script ends.

4) Follow on what script prompts.

5) After scripts ends you need to configure Lemon ldap Auth. This pretty well described on official Lemon wiki page: https://lemonldap-ng.org/documentation/1.9/authldap
