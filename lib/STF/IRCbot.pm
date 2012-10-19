package STF::IRCbot;
use Mouse;
use AnySan ();
use AnySan::Provider::IRC ();

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

    AnySan->register_listener(
        config => { cb => sub { $self->handle_config(@_) } },
        object => { cb => sub { $self->handle_object(@_) } },
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

    my $object_id;
    if ($message !~ /\D/) {
        $object_id = $message;
    } elsif ($message =~ m{^/([^/]+)/(.+)}) {
        # Parse the path into /<bucket>/<object_path
        my $bucket_name = $1;
        my $path        = $2;
        $bucket = $self->get('API::Bucket')->lookup_by_name($bucket_name);
        if ($bucket) {
            $object_id = $self->get('API::Object')->find_object_id($bucket->{id}, $path);
        }
    }

    my $object = $self->get('API::Object')->lookup($object_id);
    if (! $bucket) {
        $bucket = $self->get('API::Bucket')->lookup($object->{bucket_id});
    }

    if (! $object || ! $bucket) {
        $receive->send_reply( "Object '$object_id' not found" );
    }

    my $cluster = $self->get('API::StorageCluster')->load_for_object($object->{id});
    my $pubic_uri = $self->get('API::Config')->load_variable('stf.global.public_uri');
    $receive->send_reply($_) for (
        "Object '$message' is:",
        "  ID: $object->{id}",
        "  URI: $public_uri/$object->{name}",
        "  Bucket: $bucket->{name}",
        "  Cluster: @{[ $cluster ? $cluster->{id} : "N/A" ]}",
        "  Size: $object->{size}",
        "  Status: @{[ $object->{status} ? "Active" : "Inactive" ]}",
        "  Created: @{[ scalar $object->{created_at} ]}",
    );
}

1;
