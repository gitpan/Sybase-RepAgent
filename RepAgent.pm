package Sybase::RepAgent;

#-------------------------------------------------------------------------------------------------------------------

=head1 NAME

Sybase::RepAgent - Perl extension for building a Sybase Replication Agent which talks to a Sybase Replication Server

=head1 SYNOPSIS

  use Sybase::RepAgent;
  my $ra = Sybase::RepAgent->new($repserver, 
                                 $user, 
                                 password, 
                                 $dataserver, 
                                 $database, 
                                 $ltl_version);

  $ra->distribute(\%command_tags, $subcommand);
  $ra->begin_tran();
  $ra->commit_tran();
  $ra->rollback_tran();
  $ra->insert();
  $ra->update();
  $ra->delete();

  my $mu = $ra->maintenance_user;
  my $tp = $ra->truncation_pointer;
  my $lv = $ra->ltl_version;
  my $sv = $ra->system_version;
  my $ul = $ra->upgrade_locator;
  my $last_oqid = $ra->last_oqid;
  my $last_tran_id = $ra->last_tran_id;

=head1 DESCRIPTION

Sybase Replication Server is a mighty tool for data distribution, mirroring, warm stand by and a lot more.
RepServer gets the data to distribut from a Replication Agent, which is built into the Sybase database server.
RepAgents exit for all major databases and the language which is used by RepAgent to RepServer is described
in the Replication Server Design Guide at the Sybase web site.

This module is just a wrapper around this language which allows you to roll your own RepAgent.
You can use it to enable replication in a database which is not supported by Sybase 
(e.g. MySQL and PostgreSQL, which both support Perl-Procedures by now).
Or you can use it to feed data into RepServer, which will do the distribution, error handling and all that stuff.

For setting up and using a replication with Sybase::RepAgent see the RepAgent cookbook (cookbook.pm).

This is my own work. Sybase Inc. is in no way involved and does NOT support this module.

=cut

#-------------------------------------------------------------------------------------------------------------------

use 5.006;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw( );
our $VERSION = '0.02';

use DBI;

#-------------------------------------------------------------------------------------------------------------------

=head1 METHODS

=head2 new() - The Constructor

=head2 Parameters:

=over

=item Replicationserver

Name of the Replication Server to which the RepAgent shall connect.

=item User

Login used in the connection.

=item Password

Password used to connect.

=item Source Dataserver

RepServer expects a source from which the data comes.
This is specified in the Replication Definitions as DATASERVER.DATABASE.
This parameter is the DATASERVER part.

=item Source Database

The DATABASE part

=item LTL Version (optional, default 200)

The Version of the Log Transfer Language to use.
Use 100-103 to communicate with RepServer Version 10.0.x - 11.0. Those shouldn't be running anyway.
Use 200 for version 11.5 and later.

=back

=head2 Returnvalue:

The constructor returns a RepAgent-object if the connect to the RepServer succeeds, otherwise it returns undef.

=head2 Example:

  my $ra = Sybase::RepAgent->new($repserver,
                                 $user,
                                 $password,
                                 $dataserver,
                                 $database,
                                 $ltl_version);

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub new {
  my $that = shift;
  my $class = ref($that) || $that;
  
  my $self = {
               REPSERVER => $_[0],
               USER => $_[1],
               PASSWORD => $_[2],
               SOURCE_DS => $_[3],
               SOURCE_DB => $_[4],
               LTL_VERSION => $_[5] || 200
             };

  bless $self, $class;

  return $self->_connect();
}

#-------------------------------------------------------------------------------------------------------------------

=head2 distribute() - send a command to the repserver

=head2 Parameters:

=over

=item \%command_tags

A reference to a hash containing the command_tags for the subcommand.

Keys in the hash can be:

=over

=item origin_time (date_time value, optional)

The origin_time parameter is a datetime value that specifies the time when the 
transaction or data manipulation operation occurred. It is used to report errors. 
origin_time is used only with the transaction control subcommands: 
begin transaction, commit transaction, and rollback transaction.

=item origin_qid (32-byte binary)

The origin_qid parameter is a 32-byte binary value that uniquely identifies the 
command in the log. It is a sequence number used by Replication Server to reject 
duplicate commands after a RepAgent connection has been reestablished.

=item tran_id (120-byte binary)

The tran_id parameter is a 120-byte binary value that identifies the transaction 
the command belongs to. The transaction ID must be globally unique. One way to 
guarantee this is to first construct a unique transaction ID for the database log, 
and then attach the data server name and database name to it.

=item mode (binary 0x08, optional)

The mode parameter is set if the owner name is to be used when Replication Server 
looks up replication definitions. This parameter is optional for applied commands. 
It should not be set if the owner name is unavailable.

mode is an LTL version 200 parameter; it is available with Replication Server version 11.5 or later.

=item standby_only (1 or 0, optional)

The standby_only parameter determines whether the command is sent to the standby 
and/or replicate databases. If standby_only is set to 1, the command is sent to the 
standby database and not to the replicate database. If standby_only is set to 0, 
the command is sent to the standby and replicate databases.

standby_only is an LTL version 200 parameter and is available with Replication Server 
version 11.5 or later. It is optional for applied commands.

=back

=item $subcommand

The command that the repserver will execute. (for a more detailed description see Repserver Design Guide)

One of the following:

 begin transaction
 commit transaction
 rollback transaction
 rollback
 applied
 execute
 
=over

=item begin transaction

Starts a transaction.

=item commit transaction

Commits the transaction.

=item rollback transaction

Rolls back the transaction.

=item rollback [from oqid] to] oqid

The rollback subcommand, without the transaction keyword, requires specification of 
origin queue ID (oqid) values. The three possible forms of this subcommand are:

=over

=item rollback oqid 

rolls back a single log record corresponding to the specified origin queue ID. 
This option supports the mini-rollback capability in DB2.

=item rollback to oqid 

rolls back all log records between the specified origin queue ID and the current log record.

=item rollback from oqid1 to oqid2 

rolls back a sequence of log records whose origin queue IDs fall in the specified range.

=back

=item applied

The applied subcommand describes operations recorded in the database, including:

 row inserts
 row updates
 row deletes
 execution of applied stored procedures
 manipulation of text and image columns

Syntax:

 distribute command_tags applied [owner=owner_name]
  {'table'.rs_update
       yielding before param_list after param_list |
  'table'rs_insert  yielding after param_list |
  'table'.rs_delete  yielding before param_list |
  'table'.function_name [param_list]
       yielding after param_list before param_list |
  'table'.rs_datarow_for_writetext
       yielding datarow column_list |
  'table'.rs_writetext
       append [first] [last] [changed] [with  log]
      [textlen=100] column_list}


table is the name of the database table to which the operation was applied. 
It must be enclosed in quotation marks.

Replication Server uses table to associate the command with a replication definition. 
Beginning with Replication Server version 11.5 and version 200 LTL, if the tag @mode=0x08 is set, 
Replication Server also associates the owner name with the replication definition. 
The create replication definition command's with all tables named table_identifier clause 
determines how table is mapped to a replication definition:

If the replication definition has a with all tables named table_identifier or with primary table 
named table_identifier clause, table above is matched to the table_identifier or with the primary table named.

If the with all tables named table_identifier clause and the with primary table named 
table_identifier clauses were omitted, then table above is the name of the replication definition.

RepAgent does not need to be aware of replication definitions. It can use the table name on the data source.

yielding clause

For rs_update, rs_insert, and rs_delete, the yielding clause introduces before and after images 
of the row affected by the operation. Depending on the operation, the before image, the after image, 
or both, must be provided.
Applied subcommand before and after images:

 Operation    Before Image    After Image

 rs_update         Yes            Yes

 rs_insert         ---            Yes

 rs_delete         Yes            ---

The table.function_name form of the applied subcommand is used to distribute replicated stored 
procedures when you use the method associated with table replication definitions. 


Before and after images are specified by a param_list, which is a list of column or parameter values. 
The syntax for param_list is:

[@param_name=]literal[, [@param_name=]literal]...

      param_name is a column name or, 
           for replicated stored procedures, a parameter name.

      literal is the value of the column or parameter.

All column names in the replication definition must appear in the list. Replication Server ignores 
any additional columns. Column or parameter names can be omitted if the values are supplied in the 
same sequence as they are defined in the replication definition. If the column names are included, 
you can list them in any order, although there is a performance advantage if the columns are 
supplied in replication definition order.

Replication Server version 10.1 and later supports an optimized yielding clause. An after image value 
can be omitted if it is the same as the before image value. For example, if a table has three columns 
a, b, and c, for an update where only column b changes, the yielding clause could be:

yielding before @a=5, @b=10, @c=15  after @b=12

If the minimal columns feature is used, a RepAgent using LTL version 101 or later must omit identical 
after images.

=item execute

The execute subcommand is used to send a replicated function or stored procedure call to another 
Replication Server. This subcommand is used with the preferred method for distributing stored procedures
-- applied and request functions -- and with the older method--request stored procedures.

This is the syntax for the execute subcommand:

 distribute command_tags execute
  {[repfunc] function | [replication_definition.]function | 
  sys_sp stored_procedure} [param_list]

    * The repfunc keyword (available only with LTL version 103 or later) 
      indicates that the function name that follows is a user-defined 
      function associated with a function replication definition. When 
      you create a function replication definition for a replicated 
      stored procedure, a user-defined function with the same name is 
      created for you. In this case, the execute subcommand does not 
      include the function replication definition name.

      For applied functions, Replication Server distributes the execute 
      repfunc subcommand from a primary Replication Server to any 
      replicate Replication Servers with subscriptions for the associated 
      function replication definition.

      For request functions, Replication Server distributes the execute 
      repfunc subcommand from a replicate Replication Server to the 
      primary Replication Server for the function replication definition.

    * When the repfunc keyword is omitted, the function name that follows 
      is a user-defined function associated with a table replication 
      definition, and replication_definition is the name of the replication 
      definition.

      Without the repfunc keyword, the execute subcommand is used only for 
      request stored procedures associated with table replication definitions. 
      (Applied stored procedures associated with table replication definitions 
      use the applied subcommand.) Replication Server distributes the execute 
      subcommand from a replicate Replication Server to the primary 
      Replication Server for the table replication definition.

      If the execute subcommand does not specify a replication definition, 
      Replication Server searches its system tables for the function name 
      and then finds the associated table replication definition. If the 
      function name is not unique, and the replication definition is not 
      specified, an error message reports that the function name is valid 
      for more than one replication definition.

    * function is the name of both the user-defined function and the 
      replicated stored procedure. When Replication Server receives the 
      execute command, it maps the function name to a user-defined function 
      previously created by either the create function replication definition 
      command or the create function command.

    * With LTL version 200 or later, RepAgent uses sys_sp to send system 
      stored procedures to the standby database.

    * param_list is a list of the data values supplied when the procedure 
      was executed. You must enclose parameter values in parentheses.



=back

=back

=head2 examples

 $ra->distribute({origin_time => 'Dec  10 1992  8:48:12:750AM',
                  origin_qid => '0x00000000000000000000000000000001',
                  tran_id => '0x000000111111'}, 
                  "begin transaction 'T1' for 'user'/'password'");

 $ra->distribute({origin_time => 'Dec  10 1992  8:48:13:750AM',
                  origin_qid => '0x00000000000000000000000000000002',
                  tran_id => '0x000000111111'},
                  "applied 'mytable'.rs_insert 
                   yielding after @name='foo', @city='bar'");

 $ra->distribute({origin_time => 'Dec  10 1992  8:48:13:750AM',
                  origin_qid => '0x00000000000000000000000000000003',
                  tran_id => '0x000000111111'},
                  "applied 'mytable'.rs_update 
                   yielding before @name='bar', @city='baz'
                            after  @name='bar', @city='qwert'");

 $ra->distribute({origin_time => 'Dec  10 1992  8:48:13:750AM',
                  origin_qid => '0x00000000000000000000000000000004',
                  tran_id => '0x000000111111'},
                  "commit transaction");

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub distribute {
	my ($self, $cmd_tags, $cmd) = @_;

# 	$self->_otime($cmd_tags);
	$self->_oqid($cmd_tags,$cmd);
	$self->_tran_id($cmd_tags, $cmd);

	my $tags = join ', ', map {"\@$_=$cmd_tags->{$_}"} keys %$cmd_tags;
	my $res = $self->{DBH}->do("distribute $tags $cmd");

	my $sth = $self->{DBH}->prepare("get truncation $self->{SOURCE_DS}.$self->{SOURCE_DB}");
	return undef unless $sth;

	$sth->execute or return undef;

	$self->{TRUNCATION_POINTER} = $sth->fetchrow_array;	
	$sth->finish;
	if (substr($self->{TRUNCATION_POINTER},0,64) ne substr($cmd_tags->{origin_qid},2,64)) {
		if ($cmd =~ /commit|rollback/) {
			for (1..100) {
				select(undef, undef, undef, 0.1);         # have to wait max 10s after commit, repserver will report wrong oqid otherwise
				$sth->execute or return undef;

				if (substr($self->{TRUNCATION_POINTER},0,64) eq substr($cmd_tags->{origin_qid},2,64)) {
					$self->{TRUNCATION_POINTER} = $sth->fetchrow_array;	
					$sth->finish;
					last;
				}
			}
		}
		if (substr($self->{TRUNCATION_POINTER},0,64) ne substr($cmd_tags->{origin_qid},2,64)) {
			$self->{TRUNCATION_POINTER} = substr($cmd_tags->{origin_qid}, 2) . '00000000';
		}
	}

	return $res;
}

#-------------------------------------------------------------------------------------------------------------------

=head2 begin_tran()

Starts a transaction.
Shortcut for distribute(\%tags,"begin transaction");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=back

=head2 Returns

begin_tran returns the result of the dbi command and the tran_id valid for the transaction just started.

=head2 examples

 $ra->begin_tran({origin_time => 'Dec  10 1992  8:48:12:750AM',
                  origin_qid => '0x00000000000000000000000000000001',
                  tran_id => '0x000000111111'});

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub begin_tran {
	my ($self, $cmd_tags) = @_;
	$cmd_tags ||= {};

	return $self->distribute($cmd_tags, 'begin transaction'), $self->last_tran_id();
}

#-------------------------------------------------------------------------------------------------------------------

=head2 commit_tran()

Commits a transaction.
Shortcut for distribute(\%tags,"commit transaction");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=back

=head2 Returns

commit_tran returns the result of the dbi command and the tran_id valid for the transaction just comitted.

=head2 examples

 $ra->commit_tran({origin_time => 'Dec  10 1992  8:48:12:750AM',
                  origin_qid => '0x00000000000000000000000000000001',
                  tran_id => '0x000000111111'});

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub commit_tran {
	my ($self, $cmd_tags) = @_;
	$cmd_tags ||= {};

	return $self->distribute($cmd_tags, 'commit transaction'), $self->last_tran_id();
}

#-------------------------------------------------------------------------------------------------------------------

=head2 rollback_tran()

Rolls a transaction back.
Shortcut for distribute(\%tags,"rollback transaction");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=back

=head2 Returns

rollback_tran returns the result of the dbi command and the tran_id valid for the transaction just rolled back.

=head2 examples

 $ra->rollback_tran({origin_time => 'Dec  10 1992  8:48:12:750AM',
                  origin_qid => '0x00000000000000000000000000000001',
                  tran_id => '0x000000111111'});

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub rollback_tran {
	my ($self, $cmd_tags) = @_;
	$cmd_tags ||= {};

	return $self->distribute($cmd_tags, 'rollback transaction'), $self->last_tran_id();
}

#-------------------------------------------------------------------------------------------------------------------

=head2 insert()

Inserts a record into a table.
Shortcut for distribute(\%tags,"applied 'mytable'.rs_insert ...");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=item $table

Name of the table into which the data will be inserted.

=item $param_list

'after' parameter list as described in 'distribute'.

=back

=head2 Returns

insert returns the result of the dbi command.

=head2 examples

 $ra->insert({origin_time => 'Dec  10 1992  8:48:12:750AM',
              origin_qid => '0x00000000000000000000000000000001',
              tran_id => '0x000000111111'},
              'mytable', 
              q{@name='Joe Looser', @phone='123-456'}
            );

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub insert {
	my ($self, $cmd_tags, $table, $param_list) = @_;

	return $self->distribute($cmd_tags, "applied '$table'.rs_insert yielding after $param_list");
}

#-------------------------------------------------------------------------------------------------------------------

=head2 update()

Changes a record in a table.
Shortcut for distribute(\%tags,"applied 'mytable'.rs_update ...");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=item $table

Name of the table into which the data will be inserted.

=item $before_param_list

'before' parameter list as described in 'distribute'.

=item $after_param_list

'after' parameter list as described in 'distribute'.

=back

=head2 Returns

insert returns the result of the dbi command.

=head2 examples

 $ra->update({origin_time => 'Dec  10 1992  8:48:12:750AM',
              origin_qid => '0x00000000000000000000000000000001',
              tran_id => '0x000000111111'},
              'mytable', 
              q{@name='Joe Looser', @phone='123-456'}, 
              q{@name='Joe Random', @phone='987-654'}
            );

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub update {
	my ($self, $cmd_tags, $table, $before_param_list, $after_param_list) = @_;

	return $self->distribute($cmd_tags, "applied '$table'.rs_update yielding before $before_param_list after $after_param_list");
}

#-------------------------------------------------------------------------------------------------------------------

=head2 delete()

Deletes a record in a table.
Shortcut for distribute(\%tags,"applied 'mytable'.rs_delete ...");

=head2 Parameters:

=over

=item \%cmd_tags

Look at cmd_tags at the distribute command.

=item $table

Name of the table into which the data will be inserted.

=item $before_param_list

'before' parameter list as described in 'distribute'.

=back

=head2 Returns

insert returns the result of the dbi command.

=head2 examples

 $ra->delete({origin_time => 'Dec  10 1992  8:48:12:750AM',
              origin_qid => '0x00000000000000000000000000000001',
              tran_id => '0x000000111111'},
              'mytable', 
              q{@name='Joe Random', @phone='987-654'}
            );

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub delete {
	my ($self, $cmd_tags, $table, $before_param_list) = @_;

	return $self->distribute($cmd_tags, "applied '$table'.rs_delete yielding before $before_param_list");
}


#-------------------------------------------------------------------------------------------------------------------

=head2 Accessor Methods

=head2 maintenance_user()

Returns the name of the maintenance user given by the repserver

  my $mu = $ra->maintenance_user;

=head2 truncation_pointer()

Returns the log truncation pointer given by the repserver

  my $tp = $ra->truncation_point;

=head2 ltl_version()

Returns the ltl version that was agreed upon between repagent and repserver

  my $lv = $ra->ltl_version;

=head2 system_version()

Returns the system version of the repserver

  my $sv = $ra->system_version;

=head2 upgrade_locator()

Returns the upgrade locator given by the repserver

  my $ul = $ra->upgrade_locator;

=head2 last_oqid()

Fetches the last origin queue id from the repserver.

  my $last_oqid = $ra->last_oqid;

=head2 last_tran_id()

Fetches the last transaction id seen or generated by the repagent.

  my $last_tran_id = $ra->last_tran_id;

=cut - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub maintenance_user {
	return $_[0]->{MAINTENANCE_USER};
}

sub truncation_pointer {
	return $_[0]->{TRUNCATION_POINTER};
}

sub ltl_version {
	return $_[0]->{LTL_VERSION};
}

sub system_version {
	return $_[0]->{SYSTEM_VERSION};
}

sub upgrade_locator {
	return $_[0]->{UPGRADE_LOCATOR};
}

sub last_oqid {
	return sprintf('0x%064d', $_[0]->{LAST_ORIGIN_QID});
}

sub last_tran_id {
	return $_[0]->{LAST_TRAN_ID};
}


#===================================================================================================================
# INTERNAL USE ONLY
#===================================================================================================================

# _connect
# connects to the RepServer, 
# issues 'connect source', fetches the response and stores it in $self
# issues 'get mainenance user', fetches the response and stores it in $self
# issues 'get truncation', fetches the response and stores it in $self

sub _connect {
	my $self = shift;
	my $dbh = DBI->connect("dbi:Sybase(PrintError=1):server=$self->{REPSERVER}", $self->{USER}, $self->{PASSWORD});
	return undef unless $dbh;

	my $sth = $dbh->prepare("connect source lti $self->{SOURCE_DS}.$self->{SOURCE_DB} $self->{LTL_VERSION}");
	return undef unless $sth;

	$sth->execute or return undef;

	my ($ltl_version) = $sth->fetchrow_array;										# fetch ltl version offered by rs
	$sth->fetchrow_array;																							# dummy fetch to skip to next result set
	my ($sysversion, $upgradelocator) = $sth->fetchrow_array;

	$sth->finish;

	$sth = $dbh->prepare("get maintenance user for $self->{SOURCE_DS}.$self->{SOURCE_DB}");
	return undef unless $sth;

	$sth->execute or return undef;

	my ($maint_user) = $sth->fetchrow_array;	

	$sth->finish;

	$sth = $dbh->prepare("get truncation $self->{SOURCE_DS}.$self->{SOURCE_DB}");
	return undef unless $sth;

	$sth->execute or return undef;

	my ($trunc_point) = $sth->fetchrow_array;	

	$sth->finish;

	$self->{DBH} = $dbh;
	$self->{LTL_VERSION} = $self->{LTL_VERSION} < $ltl_version ? $self->{LTL_VERSION} : $ltl_version;
	$self->{SYSTEM_VERSION} = $sysversion;
	$self->{UPGRADE_LOCATOR} = $upgradelocator;
	$self->{MAINTENANCE_USER} = $maint_user;
	$self->{TRUNCATION_POINTER} = $trunc_point;

	return $self;
}

#-------------------------------------------------------------------------------------------------------------------
# _otime checks for the existance of the otime in the command tags.
# if it is not present, a new otime will be generated
#
# parameters: \%cmd_tags

sub _otime {
	my ($self, $cmd_tags) = @_;

	if (! exists $cmd_tags->{origin_time}) {
		$cmd_tags->{origin_time} = "'" . localtime() . "'";
	}
}

#-------------------------------------------------------------------------------------------------------------------
# _oqid checks for the existance of the origin_qid in the command tags.
# if it is not present, a new origin_qid will be generated
#
# parameters: \%cmd_tags

sub _oqid {
	my ($self, $cmd_tags) = @_;

	if (! exists $cmd_tags->{origin_qid}) {
		$self->{LAST_ORIGIN_QID} = substr($self->{TRUNCATION_POINTER}, 0, 64);
		$self->{LAST_ORIGIN_QID}++;
		$cmd_tags->{origin_qid} = sprintf('0x%064d', $self->{LAST_ORIGIN_QID});
	}
	$self->{LAST_ORIGIN_QID} = $cmd_tags->{origin_qid};
}

#-------------------------------------------------------------------------------------------------------------------
# _tran_id checks for the existance of the tran_id in the command tags.
# if it is not present, a new tran_id will be generated
#
# parameters: \%cmd_tags, $cmd

sub _tran_id {
	my ($self, $cmd_tags, $cmd) = @_;

	if ($cmd =~ /begin.*?tran/) {
		if (! exists $cmd_tags->{tran_id}) {
			$cmd_tags->{tran_id} = _gen_tran_id();
		}
		$self->{LAST_TRAN_ID} = $cmd_tags->{tran_id};
	} else {
		if (! exists $cmd_tags->{tran_id}) {
			$cmd_tags->{tran_id} = $self->{LAST_TRAN_ID};
		}
	}
}

#-------------------------------------------------------------------------------------------------------------------
# _gen_tran_id generates a new transaction_id
#
# parameters: none

sub _gen_tran_id {
	my $lt = time;
	return '0x' . unpack "H15", $lt;
}

1;
__END__

=head1 AUTHOR

Bernd Dulfer <bdulfer@cpan.org>

=head1 SEE ALSO

 Perl
 DBI
 DBD::Sybase
 Replication Server Design Guide (Sybase web site)

=cut
