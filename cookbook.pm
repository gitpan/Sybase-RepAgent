=head1 RepAgent Cookbook

Here is a simple step-by-step on setting up replication with RepAgent.pm.
If you are not familiar with RepServer, make sure you read the manuals in advance.

This text assumes you have a repserver and a destination database up and running.

=head1 Setting up a replication

=head2 Creating a database connection

A database connection in repserver is a two-way street. Since we will use only one way,
we create the connection with dsi_suspended and with dummies for user and password:

 create connection to PERL_RA_DS.perl_ra_db 
 set error class rs_sqlserver_error_class 
 set function string class rs_sqlserver_function_class 
 set username perl 
 set password perl 
 with log transfer on, dsi_suspended

PERL_RA_DS is the Source Dataserver in the constructor of RepAgent.

perl_ra_db is the Source Database in the constructor of RepAgent.

rs_sqlserver_error_class, rs_sqlserver_function_class are defaults for a connection.
If you don't understand these two, either ignore them or read the repserver manuals.

For username and password are dummies supplied, because repserver will never connect to our RepAgent.

=head2 Creating a replication definition

A replication definition tells repserver what data is expected from where:

 create replication definition perl_ra_t1_rd 
 with primary at PERL_RA_DS.perl_ra_db 
 with all tables named t1 (f1 int, f2 varchar(10)) 
 primary key (f1)

perl_ra_t1_rd is the name of the replication definition. You can choose any name you like, but, 
as always, it's best to choose a speaking name.

PERL_RA_DS.perl_ra_db is the Dataserver and the Database mentioned in the connection.

t1 (f1 int, f2 varchar(10)) is the definition of the destination table, which has to be specified.

(f1) is a primary key in the destination table which has to be specified also.

Read the repserver manuals for more details.

=head2 Creating a subscription

A subscription tells repserver where to distribute the data that comes in for replication definition.
Due to the somewhat abnormal source we are building, the subscription has to be built in three steps:

 define subscription perl_ra_t1_sub 
 for perl_ra_t1_rd 
 with replicate at DEST_SERVER.dest_db

 activate subscription perl_ra_t1_sub 
 for perl_ra_t1_rd 
 with replicate at DEST_SERVER.dest_db

 validate subscription perl_ra_t1_sub 
 for perl_ra_t1_rd 
 with replicate at DEST_SERVER.dest_db

perl_ra_t1_sub is the name of the subscription.

perl_ra_t1_rd is the name of the replication definition for which this subscription is created.

DEST_SERVER is the destination database server.

dest_db is the destination database.

=head1 Running the RepAgent

Using RepAgent.pm is pretty straight forward.

You create a RepAgent object:

 my $ra = Sybase::RepAgent->new('REPSERVER', 
                                'REPS_USER', 
                                'REPS_PWD', 
                                'PERL_RA_DS', 
                                'perl_ra_db');

This connects to the repserver and fetches all information needed to go on.

Next you have to create transactions that will be transmitted to your destination database.
The easiest way is to have RepAgent.pm handle all the nasty stuff, so you can concentrate on the important things.

Every Transaction starts with 'begin transaction':

 $ra->begin_tran;

Next you will have some data modification statements like insert and update:

 $ra->insert({}, 't1', q{@f1=12, @f2='foo'});

You have to specify three parameters to insert:

 A reference to a hash containing command tags, this can be empty. 
   RepAgent.pm handles this for you.
 The name of the destination table.
 And a string containing name/value pairs for each column in the table.

An update statement looks like this:

 $ra->update({}, 't1', q{@f1=12, @f2='foo'}, q{@f1=8, @f2='bar'});

You have to supply four parameters for the update statement:

 The first two are identical to the insert statement.
 The next is a before-image of the chenged column.
 The fourth is the after-image, make sure each image contains all columns.

And in the end you commit the transaction:

 $ra->commit_tran;

=head1 Dropping the replication

If you want to get rid of this replication, there are the usual three steps to drop a replication:

Drop the subscription:

 drop subscription perl_ra_t1_sub
 for perl_ra_t1_rd
 with replicate at DEST_SERVER.dest_db
 without purge

Drop the replication definition:

 drop replication definition perl_ra_t1_rd

And finally drop the connection:

 drop connection to PERL_RA_DS.perl_ra_db

=head1 Further reading

Sybase has all produkt manuals online on their web site. Go to www.sybase.com and look for support/manuals/replication server.
