# PUBLIC

BLM::Startup::S3 - Interface to S3

# SYNOPSIS

Create a `s3.xml` configuration file and drop it in the usual places
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

# DESCRIPTION

Provides a basic interface to [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3). These are convenience
routines that don't necessarily expose all of the capabilities of
[Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3), however you call its methods directly too.

    <null:s3_client $s3.get_s3()>
    <null:result $s3_client.list_bucket()>

The convenience routines return Bedrock objects while the raw method
calls only return POPOs.

# CONFIGURATION

A typical configuration file might look like this:

    <object> 
      <scalar name="binding">s3</scalar> 
      <scalar name="module">BLM::Startup::S3</scalar> 
      <object name="config">
        <scalar name="bucket">test-bucket</scalar>
        <scalar name="aws_access_key_id">****************</scalar>
        <scalar name="aws_secret_access_key">****************</scalar>
        <scalar name="region">us-east-1</scalar>
        <scalar name="host">localstack_main:4566</scalar>
        <scalar name="secure">false</scalar>
        <scalar name="dns_bucket_names">0</scalar>
      </object>
    </object>

See [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3) for details.

# METHODS AND SUBROUTINES

## copy\_object

    copy_object(source, destination, [headers])

`headers` is an optional list of key value pairs.

Example:

    <null $s3.copy_object('/resources/info-book.pdf', ($session.session + '/info-book.pdf')>

## list\_bucket

    list_bucket(args)

`args` is a list of key/value pairs.  See [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3) for details
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

_Note that common prefixes will be rolled up into the keys array._

- keys

    Array containing the metadata for each key.

- marker

    Current marker that started the result list.

- max\_keys

    Maximum number of keys that will be returned.

- is\_truncated

    Boolean that indicates if the results have been truncated.

- next\_marker

    If populated us this on the next call to page through results.

- bucket

    Bucket name

- prefix

    Prefix if sent in original call

## list\_bucket\_keys

This a convenience method that does the same things as `list_bucket`
but returns just an array of key names.

Essentially this just does:

    my $list = map [ $_->{key} ] @{$self->list_bucket->{keys}};

In Bedrock...

    <null:list $s3.list_bucket()>
    <array:keys>

    <foreach $s3.list_bucket()>
      <null $keys.push($_.key) >
    </foreach>

## bucket

    bucket(bucket-name)

Overrides the bucket defined in the configuration file.

## buckets

Returns an array bucket objects.

## add\_bucket

    add_bucket(bucket-name)

Creates a new bucket. If you need to set options use the S3 object.

    my $s3 = $self->get_s3;

    $s3->add_bucket({ bucket => $bucket_name, ...});

    $self->bucket($bucket_name);

_NOTE: This does not set that bucket as the current bucket. Use `bucket()`._

## add\_key

    add_key(key, value, [ bucket ])

## delete\_keys

    delete_keys(key, [bucket])

`key` can be a single key or an array of multiple keys to delete.

Example: Delete all the session files.

    <null:keylist $s3.list_bucket('delimiter', '/', 'prefix', $session.session)>
    
    <null $s3.delete_keys($keylist.keys)>

## get\_key

    get_key(key, [ bucket ])

## parse\_key

    parse_key(key)

Parses as if it were a fully qualified path to a file.  Similar to
what [File::Basename](https://metacpan.org/pod/File%3A%3ABasename) might return.

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

- name

    name portion of the key

- path
- ext
- filename

## set\_bucket\_name

    set_bucket_name(bucket-name)

# SEE ALSO

[Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3), [Amazon::S3::Bucket](https://metacpan.org/pod/Amazon%3A%3AS3%3A%3ABucket), [Bedrock::Application::Plugin](https://metacpan.org/pod/Bedrock%3A%3AApplication%3A%3APlugin), [Bedrock::Apache::BedrockCloudSessionFiles](https://metacpan.org/pod/Bedrock%3A%3AApache%3A%3ABedrockCloudSessionFiles)

# AUTHOR

Rob Lauer - <rlauer6@comcast.net>

# POD ERRORS

Hey! **The above document had some coding errors, which are explained below:**

- Around line 473:

    Unterminated I<...> sequence
