# README

This is an IRC bot to view and control STF (https://github.com/stf-storage/stf)
You need the main STF library files to run this

## LIBRARY PATH

Don't forget to set the path to the required STF files (and the dependencies,
if need be). There are several ways to do this, but using PERL5OPT and/or
PERL5LIB is one way to do it:

    export PERL5OPT='-Mlib=/path/to/lib'
    # or export PERL5LIB=/path/to/lib:$PERL5LIB
    ./bin/stf-ircbot

## CONFIGURATION

Configuration data should be included in STF's main config file, under 'IRCbot'
seciont:

    IRCbot => {
        server => 'your.irc.server',
        nickname => 'stf-bot',
        channels => {
            '#your-stf-channel' => {}
        }
    }

Except for the "server" parameter, all parameters are passed directly to
AnySan. Please see AnySan::Provider::IRC's documentation (https://metacpan.org/module/AnySan::Provider::IRC)

## COMMANDS

All commands must be invoked by the bot's nickname prefixed with a "!":

    !stf-bot

If you named your bot "jimmy", you must use that (i.e. "!jimmy")

After the invokation, you must follow it with the main command name.
Here are some sample commands:

    !stf-bot object <$object_id>
    !stf-bot object repair <$object_id>
    !stf-bot entity <$object_id>

### config [show] <$config_name>

Displays config information.

### config set <$config_name> <$value>

Sets the config value.

### config rm <$config_name>

Delete config from table.

### object [show] <$object_id|$object_path>

Shows information about the object.

### object repair <$object_id|$object_path>

Sends the object to repair queue

### entity <$object_id|$object_path>

Shows the entities for object.
