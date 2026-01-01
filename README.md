# PUBLIC

BLM::Startup::S3 - Bedrock Application Plugin for AWS S3

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

Usage in Bedrock:

    <null:list $s3.list_bucket('delimiter', '/') >

# DESCRIPTION

Provides a convenient, Bedrock-optimized interface to [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3). 
These routines return Bedrock objects (hashes/arrays) instead of raw Perl 
structures, making them easier to use in templates.

You can still access the raw [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3) object if you need deep magic:

    <null:s3_client $s3.get_s3()>
    <null:result $s3_client.list_bucket()>

# CONFIGURATION

See [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3) for details on credential handling. Bedrock supports standard
AWS environment variables or explicit config keys.

# METHODS

## add\_bucket

    add_bucket(bucket-name)

Creates a new bucket in the region specified by your configuration.

    my $s3 = $self->get_s3;
    $s3->add_bucket({ bucket => $bucket_name, ...});
    $self->bucket($bucket_name);

_NOTE: This does not set the new bucket as the current active bucket. Use `bucket()` to switch contexts._

## add\_key

    add_key(key, value, [ bucket ], metadata-key, metadata-value, ... )

Adds a new object to a bucket. 

Arguments:
\* `key`: The path/filename in S3.
\* `value`: The content string (file body).
\* `bucket`: (Optional) An Amazon::S3::Bucket object.
\* `metadata`: Any remaining arguments are treated as metadata key/value pairs.

Example:

    <null:readme $s3.get_key('README.md')>
    <null:html --markdown $readme.value>
    <null $s3.add_key('README.html', $html, 'content-type', 'text/html')>

## add\_key\_filename

    add_key_filename(key, filename, [ bucket ], metadata-key, metadata-value )

Same as ["add\_key"](#add_key), but the `value` argument is a local filesystem path.
The file will be read and uploaded to S3.

Example (Bedrock Shell):
 echo '&lt;null $s3.add\_key\_filename("README.md", "/tmp/README.md")>' | \\
    bedrock --config-var ABSOLUTE\_PATHS=yes

## bucket

    bucket(bucket-name)

Switch the active bucket for subsequent calls. If no name is provided, returns
the current bucket object.

## buckets

    buckets( [verify_region] )

Returns a Bedrock Array of bucket metadata hashes.

    <foreach $s3.buckets>
       Bucket: <var $_.bucket> (<var $_.region>)
    </foreach>

Fields returned:
\* `bucket`
\* `creation_date`
\* `region`

## copy\_object

    copy_object(source_key, dest_key, [headers])

Copies an object within the bucket. `headers` is an optional list of key/value pairs.

Example:
 &lt;null $s3.copy\_object('/resources/info.pdf', '/archive/info-2024.pdf')>

## create\_session\_file

    create_session_file(filename, content)

Helper method to save content to the current session's "directory" in S3.
Assuming your session storage is S3-backed, this creates a file at:
`session_id/filename`.

Returns the relative web path: `/session/filename`.

## delete\_keys

    delete_keys(key | [keys], [bucket])

Deletes one or more keys. Accepts a single string key or an array reference of keys.

Example:
 &lt;null:keylist $s3.list\_bucket('delimiter', '/', 'prefix', $session.session)>
 &lt;null $s3.delete\_keys($keylist.keys)>

## get\_key

    get_key(key, [ bucket ])

Retrieves an object. Returns a hash containing the body and metadata.

Returns:
\* `value`: The object content (body).
\* `etag`: The ETag of the object.
\* `content_length`: Size in bytes.
\* `content_type`: MIME type.
\* `MetaData`: A hash of metadata (x-amz-meta-\* stripped).

## get\_key\_value

    get_key_value(key, [ bucket ])

Convenience shortcut. Returns _only_ the body content (the `value` field) of the object.

    <var --markdown $s3.get_key_value('README.md')>

## list\_bucket

    list_bucket(args)

List objects in the bucket. Arguments are passed as key/value pairs.
See [Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3) for valid arguments (prefix, delimiter, max-keys, etc).

Example:
 &lt;null:list $s3.list\_bucket('delimiter', '/', 'prefix', 'images/', 'max-keys', 100)>

Returns a hash:
\* `keys`: Array of object metadata (key, etag, size, last\_modified).
\* `common_prefixes`: Array of "folders" (if delimiter is used).
\* `is_truncated`: Boolean.
\* `next_marker`: Pagination token.

## list\_bucket\_keys

    list_bucket_keys( [ bucket => bucket , raw => 1] )

Convenience wrapper around `list_bucket`. Returns a simple Bedrock Array of 
key strings, discarding the metadata.

    <foreach $s3.list_bucket_keys()>
      Found file: <var $_>
    </foreach>

## parse\_key

    parse_key(key)

Utility to parse an S3 key into filename components (similar to [File::Basename](https://metacpan.org/pod/File%3A%3ABasename)).

    <null:parts $s3.parse_key('foo/bar/baz.jpg')>
    
    Returns:
    * name:     baz
    * path:     foo/bar/
    * ext:      .jpg
    * filename: baz.jpg

## set\_bucket\_name

    set_bucket_name(bucket-name)

Sets the default bucket name for the plugin instance.

# METADATA

Amazon S3 expects metadata headers to be prefixed with `x-amz-meta-`.
This plugin handles that automatically. You can pass simple names (e.g., `account-id`)
and they will be converted.

**Writing:**
 &lt;null $s3.add\_key('report.pdf', $content, 'account-id', 123)>

**Reading:**
 &lt;null:obj $s3.get\_key('report.pdf')>
 Account ID: &lt;var $obj.MetaData.account\_id>

_Note that dashes ('-') in metadata names are converted to underscores ('\_')._

# SEE ALSO

[Amazon::S3](https://metacpan.org/pod/Amazon%3A%3AS3), [Bedrock::Application::Plugin](https://metacpan.org/pod/Bedrock%3A%3AApplication%3A%3APlugin)

# AUTHOR

Rob Lauer - <rlauer@treasurersbriefcase.com>
