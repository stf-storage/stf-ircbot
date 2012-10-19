package STF::IRCbot;
use Mouse;
use AnySan ();
use AnySan::Provider::IRC ();
use STF::Constants qw(:storage);
use feature 'state';

with 'STF::Trait::WithContainer';

has interval => (is => 'rw');
has key => (is => 'rw');
has nickname => (is => 'rw');
has password => (is => 'rw');
has port => (is => 'rw');
has receive_commands => (is => 'rw');
has server => (is => 'rw');
has wait_queue_size => (is => 'rw');
has on_connect => (is => 'rw');
has on_disconnect => (is => 'rw');
has channels => (is => 'rw');


sub run {
    my $self = shift;

    my $irc = AnySan::Provider::IRC::irc(
        $self->server,
        interval => $self->interval,
        key => $self->key,
        nickname => $self->nickname,
        password => $self->password,
        port => $self->port,
        receive_commands => $self->receive_commands,
        wait_queue_size => $self->wait_queue_size,
        on_connect => $self->on_connect,
        on_disconnect => $self->on_disconnect,
        channels => $self->channels,
    );

    AnySan->register_listener(@$_) for (
        [ config => { cb => sub { $self->handle_config(@_) } } ],
        [ object => { cb => sub { $self->handle_object(@_) } } ],
    );

    AnySan->run;
}

sub strip_command {
    my ($self, $cmd, $message) = @_;
    my $nickname = $self->nickname;

    if ($message !~ s/^!$nickname\s+$cmd\s*//) {
        return;
    }
    return $message;
}

sub load_object {
    my ($self, $object_id) = @_;

    my $bucket;
    if ($object_id !~ /\D/) {
        # nothing to
    } elsif ($object_id =~ m{^/([^/]+)/(.+)}) {
        # Parse the path into /<bucket>/<object_path
        my $bucket_name = $1;
        my $path        = $2;
        $bucket = $self->get('API::Bucket')->lookup_by_name($bucket_name);
        if ($bucket) {
            $object_id = $self->get('API::Object')->find_object_id({
                bucket_id => $bucket->{id},
                object_name => $path
            });
        }
    }

    my $object = $self->get('API::Object')->lookup($object_id);
    if (! $bucket) {
        $bucket = $self->get('API::Bucket')->lookup($object->{bucket_id});
    }

    return ($bucket, $object);
}

# !stf-bot config set KEY VAL
# !stf-bot config rm  KEY
# !stf-bot config     KEY
sub handle_config {
    my ($self, $receive) = @_;

    my $message = $self->strip_command("config", $receive->message);
    if (! defined $message) {
        return;
    }
    my ($subcmd, $varname, $varvalue) = split /\s+/, $message;

    if (! $subcmd) {
        $receive->send_reply( "config <KEY> | config rm <KEY> | config set <KEY> <VAL>" );
        return;
    }

    if ($subcmd eq 'set') {
        if (defined $varname && defined $varvalue) {
            $self->get('API::Config')->set($varname, $varvalue);
            $receive->send_reply( "set $varname '$varvalue'" );
        } else {
            $receive->send_reply( "usage: config set KEY VAL" );
        }
    } elsif ($subcmd eq 'rm') {
        if (defined $varname) {
            $self->get('API::Config')->remove($varname);
        } else {
            $receive->send_reply( "usage: config rm KEY" );
        }
    } elsif (! defined $varname && ! defined $varvalue) {
        if ($subcmd =~ s/\.\*$/.%/) {
            my $values = $self->get('API::Config')->load_variables_raw($subcmd);
            foreach $varname (keys %$values) {
                $receive->send_reply( "$varname is '$values->{$varname}'" );
            }
        } else {
            $varvalue = $self->get('API::Config')->load_variable($subcmd);
            $receive->send_reply( "$subcmd is '$varvalue'" );
        }
    }
}

# !stf-bot object <OBJECT_ID>
# !stf-bot object <OBJECT_PATH>

sub handle_object {
    my ($self, $receive) = @_;

    my $message = $self->strip_command("object", $receive->message);
    if (! defined $message) {
        return;
    }

    $message =~ s/\s+//g;

    if (! $message) {
        $receive->send_reply( "object <OBJECT_ID> | object <OBJECT_PATH>" );
        return;
    }

    my ($bucket, $object) = $self->load_object($message);
    if (! $object || ! $bucket) {
        $receive->send_reply( "Object '$object->{id}' not found" );
        return;
    }

    my $cluster = $self->get('API::StorageCluster')->load_for_object($object->{id});
    my $public_uri = $self->get('API::Config')->load_variable('stf.global.public_uri');
    $receive->send_reply($_) for (
        "Object '$message' is:",
        "  ID: $object->{id}",
        "  URI: $public_uri/$bucket->{name}/$object->{name}",
        "  Bucket: $bucket->{name}",
        "  Cluster: @{[ $cluster ? $cluster->{id} : 'N/A' ]}",
        "  Size: $object->{size}",
        "  Status: @{[ $object->{status} ? 'Active' : 'Inactive' ]}",
        "  Created: @{[ scalar localtime $object->{created_at} ]}",
    );
}

sub handle_entity {
    my ($self, $receive) = @_;

    my $message = $self->strip_command("entity", $receive->message);
    if (! defined $message) {
        return;
    }

    $message =~ s/\s+//g;

    if (! $message) {
        $receive->send_reply( "object <OBJECT_ID> | object <OBJECT_PATH>" );
        return;
    }

    my ($bucket, $object) = $self->load_object($message);
    if (! $object || ! $bucket) {
        $receive->send_reply( "Object '$object->{id}' not found" );
        return;
    }

    my @entities = $self->get('API::Entity')->search({
        object_id => $object->{id}
    });
    
    if (! @entities) {
        $receive->send_reply( "No entities found for '$message'" );
        return;
    }

    $receive->send_reply("Object '$message' has @{[ scalar @entities ]} entities (hold on, accessing them right now...)");
    my $storage_api = $self->get('API::Storage');
    my $furl        = $self->get('Furl');
    foreach my $entity (@entities) {
        my $storage = $storage_api->lookup($entity->{storage_id});
        my $mode    = fmt_storage_mode($storage->{mode});
        my $uri     = "$storage->{uri}/$object->{internal_name}";
        my $code    = 'N/A';
        if ($storage_api->is_readable($storage->{mode}, 1)){
            ($code) = $furl->head($uri);
        }

        $receive->send_reply( "[$storage->{id}][$mode] $uri ($code)" );
    }
}

sub fmt_storage_mode {
    state $modes = {
        STORAGE_MODE_CRASH_RECOVERED() => 'crashed (repair done)',
        STORAGE_MODE_CRASH_RECOVER_NOW() => 'crashed (repairing now)',
        STORAGE_MODE_CRASH() => 'crashed (need repair)',
        STORAGE_MODE_RETIRE() => 'retire',
        STORAGE_MODE_MIGRATE_NOW() => 'migrating',
        STORAGE_MODE_MIGRATED() => 'migrated',
        STORAGE_MODE_READ_WRITE() => 'rw',
        STORAGE_MODE_READ_ONLY() => 'ro',
        STORAGE_MODE_TEMPORARILY_DOWN() => 'down',
        STORAGE_MODE_REPAIR() => 'need repair',
        STORAGE_MODE_REPAIR_NOW() => 'repairing',
        STORAGE_MODE_REPAIR_DONE() => 'repair done',
    };
    $modes->{$_[0]} || "unknown ($_[0])";
}

1;
