# add-sftp-users-from-ldap
Bash script that adds SFTP users by querying LDAP to get UID and GECOS.

The config file 'user_list' contains the list of users (and optionally a colon followed by additional groups) to be added. The file format is the same as the output of the 'groups' command, such as:
   user1 : group1 group2
   user2
   user3 : group1
   user4 : group3 group4 group5

The LDAP password file must not contain a newline, because the 'ldapsearch' command will include the newline as part of the password. To get around this, remove the newline using whatever method you prefer, for example: truncate --size=-1 ldap_pw_file
