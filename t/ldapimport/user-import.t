use strict;
use warnings;

use RT::Test tests => 8 + 13*2;
use Net::LDAP::Server::Test;

use Net::LDAP::Entry;

my $importer = RT::LDAPImport->new;
isa_ok($importer,'RT::LDAPImport');

my $ldap_port = 1024 + int rand(10000) + $$ % 1024;
ok( my $server = Net::LDAP::Server::Test->new( $ldap_port, auto_schema => 1 ),
    "spawned test LDAP server on port $ldap_port");

my $ldap = Net::LDAP->new("localhost:$ldap_port");
$ldap->bind();
$ldap->add("ou=foo,dc=bestpractical,dc=com");

my @ldap_entries;
for ( 1 .. 13 ) {
    my $username = "testuser$_";
    my $dn = "uid=$username,ou=foo,dc=bestpractical,dc=com";
    my $entry = {
                    cn   => "Test User $_ ".int rand(200),
                    mail => "$username\@invalid.tld",
                    uid  => $username,
                    objectClass => 'User',
                };
    push @ldap_entries, $entry;
    $ldap->add( $dn, attr => [%$entry] );
}
$ldap->add(
    "uid=42,ou=foo,dc=bestpractical,dc=com",
    attr => [
        cn   => "Numeric user",
        mail => "numeric\@invalid.tld",
        uid  => 42,
        objectclass => 'User',
    ],
);


RT->Config->Set('LDAPHost',"ldap://localhost:$ldap_port");
RT->Config->Set('LDAPMapping',
                   {Name         => 'uid',
                    EmailAddress => 'mail',
                    RealName     => 'cn'});
RT->Config->Set('LDAPBase','ou=foo,dc=bestpractical,dc=com');
RT->Config->Set('LDAPFilter','(objectClass=User)');

$importer->screendebug(1) if ($ENV{TEST_VERBOSE});

# check that we don't import
ok($importer->import_users());
{
    my $users = RT::Users->new($RT::SystemUser);
    for my $username (qw/RT_System root Nobody/) {
        $users->Limit( FIELD => 'Name', OPERATOR => '!=', VALUE => $username, ENTRYAGGREGATOR => 'AND' );
    }
    is($users->Count,0);
}

# check that we do import
ok($importer->import_users( import => 1 ));
for my $entry (@ldap_entries) {
    my $user = RT::User->new($RT::SystemUser);
    $user->LoadByCols( EmailAddress => $entry->{mail},
                       Realname => $entry->{cn},
                       Name => $entry->{uid} );
    ok($user->Id, "Found $entry->{cn} as ".$user->Id);
    ok(!$user->Privileged, "User created as Unprivileged");
}

# Check that we skipped numeric usernames
my $user = RT::User->new($RT::SystemUser);
$user->LoadByCols( EmailAddress => "numeric\@invalid.tld" );
ok(!$user->Id);
$user->LoadByCols( Name => 42 );
ok(!$user->Id);
$user->Load( 42 );
ok(!$user->Id);

# can't unbind earlier or the server will die
$ldap->unbind;
