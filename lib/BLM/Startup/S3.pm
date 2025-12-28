package BLM::Startup::S3;

#
#    This file is a part of Bedrock, a server-side web scripting tool.
#    Copyright (C) 2001, Charles Jones, LLC.
#    Copyright (C) 2024, TBC Development Group, LLC.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
# Application Plugin for interacting with AWS S3

use warnings;
use strict;

use Amazon::S3;
use Amazon::Credentials;
use Bedrock qw(:booleans);
use Bedrock::Constants qw(:booleans :chars);
use Bedrock::Hash;
use Carp;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Basename qw(basename fileparse);
use Time::Piece;

our $VERSION = '1.0.1';

use parent qw(Bedrock::Application::Plugin Class::Accessor::Fast);

__PACKAGE__->follow_best_practice;

__PACKAGE__->mk_accessors(
  qw(
    bucket
    bucket_name
    s3
    region
  )
);

########################################################################
sub init_plugin {
########################################################################
  my ($self) = @_;

  $self->SUPER::init_plugin();

  my $config = $self->config;

  my $aws_access_key_id = $config->{aws_access_key_id} // $ENV{AWS_ACCESS_KEY_ID};

  my $aws_secret_access_key = $config->{aws_secret_access_key} // $ENV{AWS_SECRET_ACCESS_KEY};

  my $token = $ENV{AWS_SESSION_TOKEN};

  my $credentials = Amazon::Credentials->new(
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    token                 => $token,
  );

  my $bucket_name = $ENV{AWS_BUCKET}  // $config->{bucket};
  my $region      = $config->{region} // 'us-east-1';
  $self->set_region($region);

  my $s3 = Amazon::S3->new(
    credentials      => $credentials,
    region           => $region,
    host             => $config->{host},
    dns_bucket_names => to_boolean( $config->{dns_bucket_names} ),
    secure           => to_boolean( $config->{secure} ),
  );

  $self->set_s3($s3);

  if ($bucket_name) {
    $self->set_bucket_name($bucket_name);
    $self->bucket;
  }
  else {
    warn "no bucket\n"
      if !$bucket_name;
  }

  return $TRUE;
}

#######################################################################
sub buckets {
#######################################################################
  my ( $self, $verify_region ) = @_;

  my $s3 = $self->get_s3;

  my $bucket_list = eval { return $s3->buckets($verify_region); };

  if ( !$bucket_list || $EVAL_ERROR ) {
    my $errstr = $s3->errstr || $EVAL_ERROR;
    die "could not get bucket list\n$errstr";
  }

  return Bedrock::Array->new( @{ $bucket_list->{buckets} } );
}

#######################################################################
sub copy_object {
#######################################################################
  my ( $self, $source, $dest, @headers ) = @_;

  my $bucket = $self->get_bucket;

  die "set bucket first\n"
    if !$bucket;

  return $bucket->copy_object(
    key    => $dest,
    source => $source,
    @headers ? ( headers => {@headers} ) : ()
  );
}

#######################################################################
sub add_bucket {
#######################################################################
  my ( $self, $bucket_name ) = @_;

  my $s3 = $self->get_s3;

  my $retval
    = eval { $s3->add_bucket( { bucket => $bucket_name, location_constration => $self->get_region } ); };

  if ( !$retval || $EVAL_ERROR ) {
    my $errstr = $s3->errstr || $EVAL_ERROR;
    die "could not add $bucket_name\n$errstr";
  }

  return $retval;
}

#######################################################################
sub add_key {
#######################################################################
  my ( $self, $key, $value, $bucket ) = @_;

  $bucket //= $self->get_bucket;
  my $retval = $bucket->add_key( $key, $value );

  die $self->get_s3->errstr
    if !$retval;

  return $retval;
}

#######################################################################
sub delete_keys {
#######################################################################
  my ( $self, $key, $bucket ) = @_;

  my $keylist = ref $key ? $key : [$key];

  $bucket //= $self->get_bucket;

  return $bucket->delete_keys( @{$keylist} );
}

#######################################################################
sub get_key {
#######################################################################
  my ( $self, $key, $bucket ) = @_;

  $bucket //= $self->get_bucket;

  my $content = $bucket->get_key($key);

  return $content;
}

#######################################################################
sub list_bucket_keys {
#######################################################################
  my ( $self, %args ) = @_;

  my $result = $self->list_bucket;

  return Bedrock::Array->new( map { $_->{key} } @{ $result->{keys} } );
}

#######################################################################
sub list_bucket {
#######################################################################
  my ( $self, %args ) = @_;

  my $max_keys = delete $args{max_keys};

  if ($max_keys) {
    $args{'max-keys'} = $max_keys;
  }

  my $bucket = delete $args{bucket};
  $bucket //= $self->get_bucket;

  my $result = eval {

    return $bucket->list_v2( \%args )
      if $args{'max-keys'};

    return $bucket->list_all_v2( \%args );
  };

  # roll up common prefixes as keys
  if ( $args{delimiter} && $result->{common_prefixes} ) {
    foreach my $k ( @{ $result->{common_prefixes} } ) {
      my $key = {
        key               => $k . $args{delimiter},
        owner_displayname => $EMPTY,
        storage_class     => $EMPTY,
        last_modified     => $EMPTY,
        size              => $EMPTY,
        etag              => $EMPTY,
      };

      push @{$result}, $key;
    }
  }

  return $result;
}

#######################################################################
sub parse_key {
#######################################################################
  my ( $self, $key ) = @_;

  my ( $name, $path, $ext ) = fileparse( $key, qr/[.][^.]+$/xsm );

  return Bedrock::Hash->new(
    name     => $name,
    path     => $path,
    ext      => $ext,
    filename => "$name$ext",
  );
}

#######################################################################
sub bucket {
########################################################################
  my ( $self, $bucket_name ) = @_;

  $bucket_name //= $self->get_bucket_name;

  my $bucket = $self->get_s3->bucket($bucket_name);
  $self->set_bucket($bucket);

  return $bucket;
}

1;

__END__

=pod

=head1 PUBLIC

BLM::Startup::S3 - Interface to S3

=head1 SYNOPSIS

Create a F<s3.xml> configuration file and drop it in the usual places
Bedrock looks for config files.

 <object> 
   <scalar name="binding">s3</scalar> 
   <scalar name="module">BLM::Startup::S3</scalar> 
     <object name="config">
       <scalar name="bucket">treasurersbriefcase-development</scalar>
     </object>
 </object>

 <null:list $s3.list_bucket('delimiter', '/') >

A LocalStack configuration...

 <object>
   <scalar name="binding">s3</scalar>
   <scalar name="module">BLM::Startup::S3</scalar>
   <object name="config">
     <scalar name="aws_access_key_id">test</scalar>
     <scalar name="aws_secret_access_key">test</scalar>
     <scalar name="region">us-east-1</scalar>
     <scalar name="host">localhost:4566</scalar>
     <scalar name="secure">false</scalar>
     <scalar name="dns_bucket_names">0</scalar>
   </object>
 </object>

=head1 DESCRIPTION

Provides a basic interface to L<Amazon::S3>. These are convenience
routines that don't necessarily expose all of the capabilities of
L<Amazon::S3>, however you call L<Amazon::S3>'s other methods too.

 <null:s3_client $s3.get_s3()>
 <null:result $s3_client.list_bucket()>

The convenience routines will return Bedrock objects while the raw method
calls only return POPOs.

=head1 CONFIGURATION

A typical configuration file might look like this:

 <object> 
   <scalar name="binding">s3</scalar> 
   <scalar name="module">BLM::Startup::S3</scalar> 
   <object name="config">
     <scalar name="bucket">test-bucket</scalar>
     <scalar name="aws_access_key_id">****************</scalar>
     <scalar name="aws_secret_access_key">****************</scalar>
     <scalar name="region">us-east-1</scalar>
   </object>
 </object>

See L<Amazon::S3> for details.

=head1 METHODS AND SUBROUTINES

=head2 add_bucket

 add_bucket(bucket-name)

Creates a new bucket. If you need to set options use the S3 object.

 my $s3 = $self->get_s3;

 $s3->add_bucket({ bucket => $bucket_name, ...});

 $self->bucket($bucket_name);

I<NOTE: This does not set that bucket as the current bucket. Use C<bucket()>>.

=head2 add_key

 add_key(key, value, [ bucket ])

Example:

 <null:readme $s3.get_key('README.md')>
 <null:html --markdown $readme.value>
 <null $s3.add_key('README.html', $html)>

=head2 bucket

 bucket(bucket-name)

Overrides the bucket defined in the configuration file.

=head2 buckets

Returns an array bucket objects.

=head2 copy_object

 copy_object(source, destination, [headers])

C<headers> is an optional list of key value pairs.

Example:

 <null $s3.copy_object('/resources/info-book.pdf', ($session.session + '/info-book.pdf')>

=head2 delete_keys

 delete_keys(key, [bucket])

C<key> can be a single key or an array of multiple keys to delete.

Example: Delete all the session files.

 <null:keylist $s3.list_bucket('delimiter', '/', 'prefix', $session.session)>
 
 <null $s3.delete_keys($keylist.keys)>

=head2 get_key

 get_key(key, [ bucket ])

Returns a hash contain the key value and metadata.

=over 5

=item etag

=item value

=item content_length

=item content_type

=back

=head2 list_bucket

 list_bucket(args)

C<args> is a list of key/value pairs.  See L<Amazon::S3> for details
on arguments.

Example:

 <null:list $s3.list_bucket('delimiter', '/', 'prefix', $session.session, 'max-keys', 100)>

Returns a hash similar to the one shown below..

 {
   keys => [
     [0] .. {
       etag => (13b3e8c3656ede58ed2ff4db6b7601c9)
       owner_displayname => *** Undefined ***
       storage_class => (STANDARD)
       last_modified => (2023-12-08T15:12:40.000Z)
       owner_id => *** Undefined ***
       size => (843243)
       key => (ChangeLog)
       }, {
       etag => 
       owner_displayname =>
       storage_class => 
       last_modified => 
       owner_id =>
       size =>
       key => '73d8d5cf730948895f1ffb2b6af6a27f/'
      }
     ]
   marker => ()
   common_prefixes => [
     '73d8d5cf730948895f1ffb2b6af6a27f'
    ],
   max_keys => (1000)
   is_truncated => (0)
   next_marker => ()
   bucket => (test-bucket)
   prefix => ()
   }

I<Note that common prefixes will be rolled up into the keys array.>

=over 5

=item keys

Array containing the metadata for each key.

=item marker

Current marker that started the result list.

=item max_keys

Maximum number of keys that will be returned.

=item is_truncated

Boolean that indicates if the results have been truncated.

=item next_marker

If populated us this on the next call to page through results.

=item bucket

Bucket name

=item prefix

Prefix if sent in original call
 
=back

=head2 list_bucket_keys

This a convenience method that does the same things as C<list_bucket>
but returns just an array of key names.

Essentially this just does:

  my $list = map [ $_->{key} ] @{$self->list_bucket->{keys}};

In Bedrock...

 <null:list $s3.list_bucket()>
 <array:keys>

 <foreach $s3.list_bucket()>
   <null $keys.push($_.key) >
 </foreach>

=head2 parse_key

 parse_key(key)

Parses as if it were a fully qualified path to a file.  Similar to
what L<File::Basename> might return.

Returns a hash with key parts show below:

Example:

 <null:parts $s3.parse_key('foo/bar/baz.jpg')>

 path:     <var $parts.path>
 filename: <var $parts.filename>
 name:     <var $parts.name>
 ext:      <var $parts.ext>

...would result in

 path:     foo/bar/
 filename: baz.jpg
 name:     baz
 ext       .jpg

=over

=item name

name portion of the key

=item path

=item ext

=item filename

=back

=head2 set_bucket_name

 set_bucket_name(bucket-name)

=head1 SEE ALSO

L<Amazon::S3>, L<Amazon::S3::Bucket>, L<Bedrock::Application::Plugin>, L<Bedrock::Apache::BedrockCloudSessionFiles>

=head1 AUTHOR

Rob Lauer - <rlauer6@comcast.net>

=cut
