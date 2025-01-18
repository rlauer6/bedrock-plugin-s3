use strict;
use warnings;

package Faux::Context;

########################################################################
sub new {
########################################################################
  my ( $class, %options ) = @_;

  my $self = bless \%options, $class;

  return $self;
}

########################################################################
sub cgi_header_in    { }
sub send_http_header { }
sub cgi_header_out   { }
########################################################################

########################################################################
sub getCookieValue {
########################################################################
  my ( $self, $name ) = @_;

  return $ENV{$name};
}

########################################################################
sub getInputValue {
########################################################################
  my ( $self, $name ) = @_;

  return $ENV{$name};
}

########################################################################
package main;
########################################################################

use Test::More;

use Bedrock qw(slurp_file);
use Bedrock::Handler qw(bind_module);
use Bedrock::BedrockConfig;
use Bedrock::Constants qw(:defaults :chars :booleans);
use Bedrock::XML;
use Amazon::Credentials;

use Cwd;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Temp qw(tempfile tempdir);
use LWP::UserAgent;
use HTTP::Request;

use Readonly;
Readonly::Scalar our $LOCALSTACK_HEALTH_CHECK => 'http://localhost:4566/_localstack/health';

our $BLM_STARTUP_MODULE = 'BLM::Startup::S3';

$Amazon::Credentials::NO_PASSKEY_WARNING = 1;

########################################################################
sub check_localstack {
########################################################################

  my $ua  = LWP::UserAgent->new;
  my $req = HTTP::Request->new( GET => $LOCALSTACK_HEALTH_CHECK );

  my $rsp = eval { $ua->request($req); };

  return $rsp && $rsp->is_success;
}

########################################################################
sub get_module_config {
########################################################################
  my $fh = *DATA;

  my $config = Bedrock::XML->new($fh);

  return $config->{config};
}

my $module_config = get_module_config;

my $ctx = Faux::Context->new( CONFIG => { SESSION_DIR => tempdir( CLEANUP => 1 ) } );

my $blm;
my $s3;
my $dbi;

use_ok($BLM_STARTUP_MODULE);

my $config_str = Bedrock::XML::writeXMLString($module_config);

our $LOCALSTACK = check_localstack();

########################################################################
subtest 'bind module' => sub {
########################################################################
  $blm
    = eval { return bind_module( context => $ctx, config => $module_config, module => $BLM_STARTUP_MODULE, ); };

  ok( !$EVAL_ERROR, 'bound module' )
    or BAIL_OUT($EVAL_ERROR);

  isa_ok( $blm, $BLM_STARTUP_MODULE )
    or do {
    diag( Dumper( [$blm] ) );
    BAIL_OUT( $BLM_STARTUP_MODULE . ' is not instantiated properly' );
    };

  $s3 = $blm->get_s3();

  isa_ok( $s3, 'Amazon::S3' );

  SKIP: {
    skip 'no Localstack available', 1
      if !$LOCALSTACK;

    my $retval = eval { return $blm->add_bucket('test-bucket'); };

    if ( $EVAL_ERROR || !$retval ) {
      diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );
      BAIL_OUT('could not create test-bucket');
    }

    my $bucket = $blm->get_bucket();
    isa_ok( $bucket, 'Amazon::S3::Bucket' );
  }

};

########################################################################
subtest 'buckets()' => sub {
########################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $bucket_list = eval { return $blm->buckets; };

  isa_ok( $bucket_list, 'Bedrock::Array' )
    or diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );
};

########################################################################
subtest 'add_key()' => sub {
########################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $retval = eval { return $blm->add_key( 's3.xml', $config_str ); };

  ok( $retval, 'add_key()' );

  if ( !$retval || $EVAL_ERROR ) {
    BAIL_OUT($EVAL_ERROR);
  }

  my $bucket_list = $blm->list_bucket;

  isa_ok( $bucket_list, 'HASH' )
    or diag( Dumper( [ bucket_list => $bucket_list ] ) );

  ok( $bucket_list->{keys}, 'has keys' );

  isa_ok( $bucket_list->{keys}, 'ARRAY' )
    or BAIL_OUT( Dumper( [ bucket_list => $bucket_list ] ) );

  my @keys = map { $_->{key} } @{ $bucket_list->{keys} };

  is( @{ $bucket_list->{keys} }, 1, 'one key' )
    or BAIL_OUT( Dumper( [ bucket_list => $bucket_list ] ) );

  is( $keys[0], 's3.xml', 'key saved' );
};

########################################################################
subtest 'list_bucket_keys()' => sub {
########################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $keys = $blm->list_bucket_keys();

  isa_ok( $keys, 'Bedrock::Array' );

  ok( @{$keys}, 'has at least 1 key' );

  ok( grep {/s3[.]xml/xsm} @{$keys}, 'contains s3.xml' );
};

########################################################################
subtest 'get_key ()' => sub {
########################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $key = $blm->get_key('s3.xml');

  isa_ok( $key, 'HASH' );

  is( $key->{value}, $config_str, 'read s3.xml from bucket' )
    or BAIL_OUT( Dumper( [ key => $key ] ) );

};

#######################################################################
subtest 'copy_object' => sub {
#######################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $retval = eval { return $blm->copy_object( 's3.xml', 's3-copy.xml' ); };

  ok( !$EVAL_ERROR && $retval, 'copy object' )
    or diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );

  my $keys = $blm->list_bucket_keys;
  isa_ok( $keys, 'Bedrock::Array' )
    or diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );

  ok( grep {/s3\-copy\.xml/xsml} @{$keys}, 'new object in bucket' );

  my $content = $blm->get_key('s3-copy.xml');

  ok( $content->{value} eq $config_str, 'verified copy' );
};

########################################################################
subtest 'delete_keys' => sub {
########################################################################
  plan skip_all => 'no LocalStack available'
    if !$LOCALSTACK;

  my $retval = eval { return $blm->delete_keys('s3-copy.xml'); };

  ok( $retval && !$EVAL_ERROR, 'delete_keys(key)' )
    or diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );

  $retval = eval { return $blm->delete_keys( ['s3.xml'] ); };

  ok( $retval && !$EVAL_ERROR, 'delete_keys(key)' )
    or diag( Dumper( [ error => $EVAL_ERROR, errstr => $s3->errstr ] ) );
};

done_testing;

########################################################################
END {
  eval {
    if ( $LOCALSTACK && $blm ) {
      my $keys = $blm->list_bucket_keys;

      if ( $keys && @{$keys} ) {
        $blm->delete_keys( $blm->list_bucket_keys );
      }
    }

    if ( $s3 && $blm ) {
      # $s3->delete_bucket( { bucket => 'test-bucket' } );
    }
  };

  if ($EVAL_ERROR) {
    print {*STDERR} $EVAL_ERROR;
  }
}

1;

__DATA__
<object> 
  <scalar name="binding">s3</scalar> 
  <scalar name="module">BLM::Startup::S3</scalar> 
  <object name="config">
    <scalar name="bucket">test-bucket</scalar>
    <scalar name="aws_access_key_id">test</scalar>
    <scalar name="aws_secret_access_key">test</scalar>
    <scalar name="region">us-east-1</scalar>
    <scalar name="host">localhost:4566</scalar>
    <scalar name="secure">false</scalar>
    <scalar name="dns_bucket_names">0</scalar>
  </object>
</object>
