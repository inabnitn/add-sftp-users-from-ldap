#!/bin/bash
#
# add-sftp-users-from-ldap.sh
# initial version: 2020/12/01, Nicholas Inabnit
#
# This script creates SFTP users by reading in a list of usernames,
# then fetching each user's UID and GECOS from LDAP.
#
# The config file 'user_list' contains the list of users (and optionally a colon
# followed by additional groups) to be added. The file format is the same as the
# output of the 'groups' command, such as:
#    user1 : group1 group2
#    user2
#    user3 : group1
#    user4 : group3 group4 group5
#
# The config file 'ldap_pw' must NOT contain a newline, because the 'ldapsearch'
# command treats all characters (including the newline) as part of the password.
# To get around this, remove the newline using whatever method you prefer,
# for example: truncate --size=-1 ldap_pw_file
#
################################################################################

# Specify the LDAP server and special DN.
ldap_server="ldaps://myldapserver.com"
special_dn="cn=my_cn,ou=my_ou,dc=myldapserver,dc=com"

# Specify the file containg the list of usernames to add.
user_list="user_list"

# Specify the file where LDAP results will be temporarily saved.
ldap_results="ldap_results.tmp"

# Specify the file containing the password for querying LDAP.
# Make sure the file does NOT contain a newline!
ldap_pw_file="ldap_pw"

# The user details below will be applied to all new SFTP users.
primary_group="sftp_users"
shell="/usr/libexec/openssh/sftp-server"
home="/sftp_root"

# The input file $user_list is fed into the while loop at the bottom of the script, at the 'done' line.
while read -r line ; do

   # Get first field of the colon-delimited line, remove white space, convert anything uppercase to lowercase.
   username=$(echo "$line" | awk -F: '{ print $1 }' | tr -d [:blank:] | tr [:upper:] [:lower:])

   # Get second field of the colon-delimited line, convert anything uppercase to lowercase.
   additional_groups=$(echo "$line" | awk -F: '{ print $2 }' | tr [:upper:] [:lower:])

   echo "Working on username: $username"

   # Make sure the username doesn't contain special characters.
   if [[ "$username" =~ [[:punct:]] ]] ; then
      echo " --- ERROR: Bailing out because the username '$username' contains invalid characters."
      echo
      exit 1
   fi

   # Make sure the additional groups don't contain special characters.
   if [[ "$additional_groups" =~ [[:punct:]] ]] ; then
      echo " --- ERROR: Bailing out because the group list for '$username' contains invalid characters: $additional_groups"
      echo
      exit 1
   fi

   # Make sure each of the additional groups actually exists.
   for groupname in $additional_groups ; do
      if ! getent group "$groupname" ; then
         echo " --- ERROR: Bailing out because the group list for '$username' contains an invalid group: $groupname"
         echo
         exit 1
      fi
   done

   # The 'useradd' command requires additional groups to be separated only by commas, such as: group1,group2,group3
   # So we need to remove leading and trailing white space from $additional_groups, then replace delimiting spaces with commas.
   # In other words, we need this:
   #    ^ group1   group2 group3   $
   # to become this:
   #    ^group1,group2,group3$
   #
   # Below, the 'xargs' command removes leading and trailing white space.
   # Then the 'sed' command replaces the delimiting spaces with commas.
   additional_groups=$(echo $additional_groups | xargs echo -n | sed 's/ /,/g')

   # Check if the user already has a local account.
   user_info=$(getent passwd "$username")
   if [[ -n "$user_info" ]] ; then
      echo " --- WARNING: Skipping '$username' because the user already exists on this server:"

      # Display the existing user info and group membership.
      echo "$user_info"
      echo -n "Group membership: "
      groups "$username" | awk -F": " '{ print $2 }'
      echo
      continue
   fi
  
   # Query LDAP to get the user's GECOS and UID number.
   ldapsearch -LLL -y "$ldap_pw_file" -H "$ldap_server" -D "$special_dn" uid="$username" gecos uidNumber > "$ldap_results" 2>&1
   if [[ $? -ne 0 ]] ; then
      echo " --- ERROR: Bailing out because the 'ldapsearch' command failed. Below is the output (stdout + stderr), which is also saved in the file $ldap_results"
      echo
      cat "$ldap_results"
      exit 1
   fi
   
   # Get the user's GECOS and UID number from the 'ldap_results' file.
   gecos=$(grep 'gecos: ' "$ldap_results" | awk -F": " '{ print $2 }')
   uid_number=$(grep 'uidNumber: ' "$ldap_results" | awk -F": " '{ print $2 }')
   
   # Bail out if the user couldn't be found in LDAP.
   if [[ -z "$gecos" ]] || [[ -z "$uid_number" ]] ; then
      echo " --- ERROR: Bailing out because the details for the user '$username' could not be found in LDAP."
      echo
      exit 1
   fi
   
   # Add the user. Only use the '--groups' option if $additional_groups is defined.
   if [[ -n "$additional_groups" ]] ; then
      useradd --uid "$uid_number" --gid "$primary_group" --groups "$additional_groups" --shell "$shell" --home-dir "$home" --no-create-home --comment "$gecos" "$username"
      return_code=$?
   else
      useradd --uid "$uid_number" --gid "$primary_group" --shell "$shell" --home-dir "$home" --no-create-home --comment "$gecos" "$username"
      return_code=$?
   fi

   # Exit with a non-zero status if the 'useradd' command failed.
   if [[ $return_code -ne 0 ]] ; then
      echo " --- ERROR: Bailing out because the 'useradd' command failed."
      exit 1
   fi

   # If we made it this far, the user was added.
   echo "Successfully added user."

   # Display the new user's info and group membership.
   getent passwd "$username"
   echo -n "Group membership: "
   groups "$username" | awk -F": " '{ print $2 }'
   echo

done < "$user_list"

# Clean up the temporary file 'ldap_results'.
rm -f "$ldap_results"

# Declare victory.
echo "All done."
