# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 9 };
use lib '../../';
use Sybase::RepAgent;
ok(1); # If we made it this far, we're ok.

my %connect_info;
{
	local $/=undef;
	open DEF, 'connect_info' or last;
	%connect_info = split /[:\n]/,<DEF>;
	close DEF;
}

print "RepServer ($connect_info{repserver}): ";
my $reps = <>;
chomp $reps;
$reps ||= $connect_info{repserver};
print "User ($connect_info{user}): ";
my $user = <>;
chomp $user;
$user ||= $connect_info{user};
print "Password ($connect_info{password}): ";
my $password = <>;
chomp $password;
$password ||= $connect_info{password};
print "Source Dataserver ($connect_info{dataserver}): ";
my $ds = <>;
chomp $ds;
$ds ||= $connect_info{dataserver};
print "Source Database ($connect_info{database}): ";
my $db = <>;
chomp $db;
$db ||= $connect_info{database};
my $ra = Sybase::RepAgent->new($reps, $user, $password, $ds, $db);
ok($ra);

ok($ra->maintenance_user);
ok($ra->truncation_pointer);
ok($ra->ltl_version);
ok($ra->system_version);
ok($ra->upgrade_locator);

ok($ra->begin_tran);
ok($ra->insert({}, 't1', q{@f1=12, @f2='foo'}));
ok($ra->update({}, 't1', q{@f1=12, @f2='foo'}, q{@f1=8, @f2='bar'}));
ok($ra->commit_tran);

