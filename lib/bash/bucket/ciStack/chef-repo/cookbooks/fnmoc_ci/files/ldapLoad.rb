#!/usr/bin/env ruby
# - Require the net/ldap (AKA net-ldap) module
require 'net-ldap'
###
# Internal Methods  
#

#  Trim the DC components from each member of the provided list of DNs.
def get_rdns(dnList)
    dnList.map{|dn| dn.sub(/,dc=.*/i,"")}.select{|s| s.size > 0}
end

# Parse a unique list of Parent DNs from the provided list of DNs.
def dn_parents(dnList)
    dnList.map{|s| s.split(",")[1..-1].join(',')}.sort.uniq.select{|s| s.size > 0}
end

# Parse the directory tree branch structure from the provided list of DNs.
# Sort the return list into the correct order they should be added.
def rdn_branches(dnList)
    dnList=get_rdns(dnList) 
    rl=[]
    while ( dnList.size > 0 ) do
       rl.concat(dnList=dn_parents(dnList))
    end
    rl.sort_by{|s| s.size }.uniq {|s| s.downcase}
end

# This method adds a branch entry, with objectclass based on the starting member of the provided RDN.
#  - O={name},  adds objectclass=organization, and o={name} attributes.
#  - OU={name}, adds objectclass=organizationalUnit, and ou={name} attributes.
#  - CN={name}, adds objectclass=container, and CN={name} attributes.
def add_branch_rdn( rdn, base, ldap)
   oc = { "OU" => %w{ top organizationalUnit },
           'O'=> %w{ top organization},
           'C'=> %w{ top country},
          'CN'=> %w{ top container }
   }
   e = Net::LDAP::Entry.new(rdn + "," + base)
   n = e.dn.split(",")[0].split("=")[0]
   e[n]= rdn.split(",")[0].split("=")[1]
   e[:objectclass]= oc[n.upcase]
   if (e[:objectclass].size == 0)
       STDERR.puts "Unknown or Missing support for attribute type: " + n
       return nil 
   end
   addEntry(e,ldap)
end

###
# This method wraps LDAP.add. It transforms the provided Entry into arguments for LDAP.add.
# Empty Attribute values are ignored, - the filter could have set values to an empty list.
## ldap.rb documentation showes :cn => String  versus :cn => [ String ], however either seem to work.
def addEntry(e, ldap)
   h={}; e.attribute_names.each{|n| h[n] = e[n] unless ( n == :dn || e[n].size == 0 )}
   ldap.add(:dn => e.dn, :attributes => h ) || showLdapErr(ldap, e.to_ldif)
end

def showLdapErr(ldap, msg=nil)
       STDERR.puts "\# Result: #{ldap.get_operation_result.code}"
       STDERR.puts "\# Message: #{ldap.get_operation_result.message}, #{ldap.get_operation_result.error_message}"
       STDERR.puts "\# Extended response: #{ldap.get_operation_result.extended_response}"
       STDERR.puts "\# Provided the following:\n#{msg}\n" unless msg.nil?
       return ldap.get_operation_result.code
end


###  
# Add AD-like group 
#
def addGroup(rdn, base, ldap, members=nil)
 # could have used base = ldap.base
 e = Net::LDAP::Entry.new(rdn + "," + base) if base
 e = Net::LDAP::Entry.new(rdn) if base.nil?
 e[:cn]= e.dn.split(",")[0].split('=')[1]
 ## Set grouptype to a Microsoft global security group (-2147483643).
 e[:grouptype]= [ "-2147483643" ]
 e[:objectclass]= %w{ top group }
 e[:member]=members if members
 addEntry(e,ldap)
end

# rebaseEntry method replaces DCs with LDAPBASE in the DN or attribute values, of the provided entry.
def rebaseEntry(e,base)
   e.dn = e.dn.sub(/dc=.*/i, base)
   l = e[:memberof].map{|s| s.sub(/dc=.*/i, base) }
   e[:memberof] = l unless( l.size == 0 )
   # e.attribute_names.select {|n| e[n].map{|s| s.to_s =~ /,dc=/i }.size}
   return e
end
def certInfo(certList)
## Extract elements from the provide list of certificates. Returning a list consisting of the following:
## [[ssh-public-key, CN, expireTime.to_s, expireTime.to_i Mail, cert, subject] ...]
#  Expried certificates are rejected (not returned in list).
   certList.map{|cert| c = OpenSSL::X509::Certificate.new(cert) 
        [ "ssh-rsa #{Base64.encode64(c.public_key.to_der).split("\n").join}", 
          c.subject.to_s.sub(/.*CN=/i,""), c.not_after.to_s, c.not_after.to_i.to_s,
          c.extensions.select{|x| 
              x.to_h["oid"] =~ /altname/i && x.to_h["value"] =~ /mail/ 
          }.map { |x| x.to_h["value"].sub(/email:/,"") }.first, cert, c.subject.to_s ] 
          }.reject{ |l| Time.at(l[3].split(" ").last.to_i) < Time.now }
end

def uniq_nocase(a)
  h = {}; a.map {|v| k=v.downcase; next if h.has_key?(k); h[k]=v }
  return h.values
end
## The inject way:
## http://stackoverflow.com/questions/1103327/how-to-uniq-an-array-case-insensitive
## downcased = [] 
## a.inject([]) { |result,h| 
##      unless downcased.include?(h.downcase);
##          result << h
##          downcased << h.downcase
##      end;
##      result}

###
# This method filters attribute values in the provided Entry, removes unwanted attributes,
# and builds some attributes from the userCertificate ( sshpublickey, cn, ...).
# When provided an ldap, the Entry will be added.
def userEntry(se, ldap=nil, includes=[], excludes=[]) 
   # This is a default set of includes, in addition to provided.
   excludes=excludes.map{|n| n.downcase}
   kp =  %w{ accountexpires add admincount cn department description displayname dn 
             gecos gidnumber givenname homedirectory loginshell mail memberof 
             objectclass samaccountname sn telephonenumber 
             uid uidnumber useraccountcontrol usercertificate;binary userprincipalname
    }.concat(includes).map{|n| n.downcase}.reject{|n| excludes.member?(n)}.map{|n| n.to_sym}.sort.uniq
   e = Net::LDAP::Entry.new(se.dn)
   # Copy attributes in the keep list (kp), only if one or more in length.
   kp.each{|n| se[n].size > 0 && e[n]=se[n]}
   ## always keep the first left RDN
   n = e.dn.split(',')[0].split('=')[0]
   v = e.dn.split(',')[0].split('=')[1]
   e[n] = e[n] << v unless e[n].map{|s| s.downcase}.member?(v.downcase)
   e[:objectclass] = %w{ top person organizationalperson inetorgperson user ldappublickey posixaccount shadowaccount }
   if ( e["usercertificate;binary"].size > 0 )
# Build the sshPublicKey valuenis.ldif:, using keys that are bound to the user certificates.
     info = certInfo(e["usercertificate;binary"])
     if ( info.size > 0 )
       e["usercertificate;binary"]= info.map{|l| l[5]}
       e[:sshpublickey] = info.map{|l| l[0..3].join(" ") }
#  Ensure the user certificate subject CN will be included in the LDAP entry
       e[:cn] = e[:cn].concat(info.map{|l| l[1]}).sort.uniq
##  account should expire based on the user certificate YTBD
#   e[:accountExpires]  = info.map{|l| l[2]}.max
#  Only one mail address, if another from the certificate extensions, use:  street postalAddress ... 
       ml  = e[:mail].concat( info.map{|l| l[4] }.select{|x| x}).map{|s| s.downcase.strip }.uniq
       e[:mail] = ml.first if ml.size > 0
       e[:streetaddress] = ml[1..-1] if ml.size > 1
       e[:seealso]  = uniq_nocase( e[:seeAlso].concat( info.map{|l| l[6] }.select{|x| x}))
       ml  = e[:seeAlso].concat( info.map{|l| l[6] }.select{|x| x}).select{|s| s.downcase.strip }.uniq
       cacInfo = info.first[1].split('.')
       e[:userprincipalname]= ["#{cacInfo.last}@mil}"] if e[:userprincipalname].first.nil?
       e[:sn]= [cacInfo.first] unless e[:sn].size > 0
       e[:givenname]= [cacInfo[1]] if e[:givenname].size > 0
       e[:displayname] = ["#{e[:givenname][0]}_#{e[:sn][0]}" ] if e[:displayname].first.nil?
     end
   end
# - Must have uid, uidNumber, gidNumber.
    n= :givenname; e[n] = ["jane"] unless e[n].size > 0
    n= :sn; e[n] = ["doe"] unless e[n].size > 0
    n= :uid; e[n] = ["jane_doe"] unless e[n].size > 0
    n= :uidnumber; e[n] = "777777" unless e[n].size > 0
    n= :gidnumber; e[n] = "100" unless e[n].size > 0
    n= :homeDirectory; e[n] = "/home/jail" unless e[n].size > 0
   addEntry(e,ldap) unless ldap.nil?
   return(e)
end

## Alias support requires openldap version 2.2 or greater in back-bdb.
## e = ldap.search(:filter=>"(uid=djones)")
## addEntry(aliasEntry(e, "cn=foobar,ou=Users", "dc=example,dc=com"))
def aliasEntry(e, alias_rdn, base=nil)
  a = Net::LDAP::Entry.new( "#{alias_rdn},#{base}" ) unless base.nil?
  a = Net::LDAP::Entry.new( "#{alias_rdn}" ) if base.nil?
  a[:objectclass] = %w{ alias extensibleObject }
  a[:aliasedobjectname] = e.dn
  a[a.dn.split(",").first.split("=").first] = a.dn.split(",").first.split("=").last
  return(a)
end

def cac_subject_info( dn )
    l = dn.split(",").last.split("=")
    return nil unless (l.first =~ /^cn$/i)
    return(l.split("."))
end
## mergeUserEntry(newEntry, oldEntry, ldap) 
def mergeUserEntry(u, b, ldap)
   return nil if new.dn != b.dn
   bl = b.attribute_names; # existing db entry, or old entry to merge with
   # actions to take on an attribute: accumulate, replace, or add
   accumulate = %w{ usercertificate;binary cn }.map{|n| n.downcase.to_sym }.sort.uniq
   accumulate.each{|n| u[n].concat!(b[n]) }
   a = userEntry(u)  
   al = a.attribute_names
   replace = bl.select{|n| al.member?(n) && b[n] != a[n] }
   # Add any remaining attribute names, that were not filtered or changed
   add = al.reject{|n| replace.member?(n)}
   add.each{|n| a[n].each{|m| ldap.add_attribute(a.dn, n, m) || showLdapErr(ldap)}}
   replace.each{|n| a[n].each{|m| ldap.replace_attribute(a.dn, n, m) || showLdapErr(ldap)}}
end
def syncUserGroupMembers(ldap)
# - Parse group DNs from user Entry memberOf attributes.
   userDS = ldap.search(:filter=>"(objectclass=person)").reject{|e| e[:memberof].first.nil? }
   groupDNs = userDS.map{|e| e[:memberof] }.flatten.sort.uniq 
# - Find the branches or parents needed 
   allRDNs = ldap.search(:attributes=> [:dn]).map{|e| e.dn.downcase.sub(/,dc=.*/,"")}
   rdn_branches(groupDNs).reject{|s| allRDNs.member?(s.downcase) || s =~ /^dc=/i }.each {|s| add_branch_rdn(s, ldap.base, ldap) }
# - Hash  memberOf DNs to a list of User DNs
   h={}; groupDNs.each {|g| h[g] = userDS.select{|e| e[:memberof].member?(g)}.map{|e| e.dn}.sort}
#  ldap search for existing group Entries
   groupDS = ldap.search(:filter=>"(objectclass=group)")
   groupDNs = groupDS.map{|e| e.dn.downcase }
# - Create non-existing groups.
   h.keys.reject{|n| groupDNs.member?(n.downcase) }.each{|n| addGroup(n, nil, ldap, h[n])}
# - Update member attributes in the existing groups.
   h.keys.select{|n| groupDNs.member?(n.downcase) }.each{|n| 
     # YTBD compare member before replace
     ge = groupDS.select{|e| e.dn.downcase == n.downcase }.first
     if ge[:member].size == 0
          ldap.add_attribute(n,:member, h[n]) && next
          showLdapErr(ldap, "Could not add Member: #{h[n]}\n To Entry:\n#{ge.to_ldif}")
     end
     next if (h[n] ==  ge[:member]) 
     ldap.replace_attribute( n, :member, h[n]) || showLdapErr(ldap )
   }
end
def showLdapSyntax()
   puts `ldapsearch -H ldap://localhost -x -s base -b cn=subschema ldapsyntaxes`
end
### 
# Main:
#  - Read the provided LDIF encoded file (first parameter). This being the new user data to filter and load.
ldifFile = ARGV[0] ? ARGV[0] : "ldap.ldif"
# - Use the value of environment variable LDAPBASE, as the base (domain DN).
base = ENV['LDAPBASE'] ? ENV['LDAPBASE'] : "dc=exern,dc=nps,dc=edu"
# - Use the value of environment variable LDAPBINDDN, to authenticate to LDAP.
bindDN = ENV['LDAPBINDDN'] ?  ENV['LDAPBINDDN'] : "cn=manager,#{base}"
# - Use the value of environment variable LDAPPW, to authenticate to LDAP.
pw = ENV['LDAPPW'] ?  ENV['LDAPPW'] : "changeit"
port = ENV['LDAPPORT'] ?  ENV['LDAPPORT'] : "389"
x='LDAPHOST'; ldaphost = ENV[x] ? ENV[x] : "127.0.0.1"
ldap = Net::LDAP::new( :base => base, :host => ldaphost, :port => port )
ldap.auth( bindDN, pw ) 
unless ldap.bind
   STDERR.puts "ERROR: #{File::split($0)[-1]}: Could not bind to LDAP."
   l=%w{LDAPBASE LDAPBINDDN LDAPPW LDAPHOST LDAPPORT}.map{|n| "#{n}=\"#{ENV[n]}\"" }
   STDERR.puts "ENV: #{ l.join(" ")}\n"
   exit 1
end
def main(ldifFile, ldap)
   unless File.readable?(ldifFile)
      STDERR.puts "ERROR: #{File::split($0)[-1]}: could not read file: \"#{ldifFile}\""
      STDERR.puts "Usage: #{File.split($0)[-1]} <LDIF-file>\n"
      return nil
   end
   base = ldap.base
   db = ldap.search
## if ldifFile was made with the ldapsearch command, it may have a few lines that
## that read_ldif will choke on, namely the search: and result: lines,  
`sed -i -e 's/^search:/#search:/' -e 's/^result:/\#result:/' #{ldifFile}`
   data = Net::LDAP::Dataset::read_ldif(StringIO.new(File.read( ldifFile ))).to_entries
## - ldap.seach directory (existing) data set.
## ldap = Net::LDAP::new( :base => base, :encryption=>:simple_tls, :scheme=>"ldaps", port=> 636 ) 

## 
# - Find entries with objectclass person.
   personEntrys=data.select{|e| e[:objectclass].member?("person") }
   personDNs=personEntrys.map{|e| e.dn }
# - Find groups from memberof attribute.
   groupDNs = personEntrys.map{|e| e[:memberof] }.flatten.sort.uniq 
# - Find the branches needed 
   rdn_list= get_rdns(dn_list = db.reject{|e| e[:dc].size > 0 }.map{|e| e.dn.to_s.downcase })
   rdn_missing = rdn_branches(personDNs.concat(groupDNs)).reject{|s| rdn_list.member?(s.downcase)}
# - Add missing parents: O, OU, CN (as container),
   rdn_missing.each {|s| add_branch_rdn(s, base, ldap) }
## - Add groups
   get_rdns(groupDNs).reject{|s| rdn_list.member?(s.downcase) }.map { |rdn| addGroup(rdn, base, ldap) }
# - Add persons objectclasse entries
#  - Change the DCs (rebase) in all attributes
   personEntries = personEntrys.map{|e| rebaseEntry(e,base) }
   personEntries.reject{|e| dn_list.member?(e.dn.downcase) }.map {|e| userEntry(e,ldap) }
# - modify existing person with ldif entries
   personEntries.select{|e| dn_list.member?(e.dn) }.map { |e| 
      mergeUserEntry(e,db.select{|curEntry| curEntry.dn == e.dn}.first, ldap) 
   }
# - Rebuild group entries from memberOf entries of users.
   syncUserGroupMembers(ldap)
end

main( ldifFile, ldap) unless $0 =~ /irb/
