# Hermod Signal - IRC - Telegram Gateway

[Hermod, or Hermóðr](https://en.wikipedia.org/wiki/Herm%C3%B3%C3%B0r) is a figure in Norse mythology,
often considered the messenger of the gods

These scripts act as a gateway between groups of several chat protocols:

- IRC
- Telegram
- Signal
- Matrix
- Mattermost
- Discord

## Preparations

### Used perl modules

Here is a list of perl modules needed for running these scripts:
```
Capture::Tiny
Capture::Tiny
CGI::Fast
DBI
JSON;
POE::Component::IRC
POE::Component::IRC::Plugin::FollowTail
POE::Component::Server::TCP
Text::Unidecode
Encode
TOML
URI::Escape
WWW::Curl::Easy
WWW::Curl::Form
Dancer
Mojo::Discord
IO::Socket::INET
```

The first thing to do is add bot accounts in the different channels or groups.

You can register a telegram bot with the **botfather**.
Then you can add the bot to the admins of the telegram channel you want to share with IRC. 
Note the telegram API token and find the telegram group chat\_id.

Reference: [Telegram Bot API](https://core.telegram.org/bots/api "Bot API")

Register a username/password with the IRC service of your choice.

Download sigal-cli from [Asamk's Github page](https://github.com/AsamK/signal-cli/releases) and register a phone number, see [Wiki Quickstart](https://github.com/AsamK/signal-cli/wiki/Quickstart)

You can register a matrix account at [element.io](https://app.element.io/). Refer to the [Matrix API docs](https://matrix.org/docs/guides/client-server-api) on how to obtain an access token.

You can register a mattermost account at [mattermost.com](https://customers.mattermost.com/cloud/signup). Refer to the [Mattermost API](https://api.mattermost.com/#tag/authentication) for how to obtain a bearer token.

## Configuration

Make a copy of the file hermod.toml.example to /etc/hermod.toml and change values
appropriately

For more detailed information on the various configuration options, consult the [Wiki](./wiki)

**signal-\>phone** is the phone number used by signal-cli. It has to be added to the group (**signal-\>gid**). **common-\>anon** is a string used to partly anonymize telephone numbers when relaying messages to the other channels. Then the phone number has to be registered with **signal-cli**

Refer to the [Telegram Bot API](https://core.telegram.org/bots/api) for details about **telegram-\>token** and **telegram-\>chat\_id**

**irc-\>node**, **irc-\>channel**, **irc-\>port**, **irc-\>nick** and **irc-\>password** relate to... IRC. Any value for **irc-\>UseSSL** other than 0 will cause the connection to be SSL enabled. Setting **irc-\>maxmsg** will break messages from telegram into chunks of **maxmsg** size.

**irc-\>infile** is the connection between the telegram webhook, the signalpoller and the IRC bot. Can be any file, as long as it is writeable by the webhook and signalpoller and readable by the bot.

The IRC bot and the webhook write to **signal-\>infile**. The poller will read it and send new content to the signal group

## Setting up the hooks

The gateway consists of daemon parts and webhooks. Place the
webhooks in an executable place of a webserver (like **https://webserver/cgi-bin/telegramhook**)

Next thing is to register the webhooks:

### Telegram

```bash
curl -F "url=https://webserver/cgi-bin/telegramhook" https://api.telegram.org/bot$TOKEN/setWebhook
```

Make sure the telegram bot you are using has privacy mode disabled. If not, the bot won't see any group messages by other users. You can review the **telegram-\>debug** file to get the chat\_id of the telegram group.

### Mattermost

The bridge to mattermost works with the Incoming and Outgoing webhooks that you can register in the mattermost interface.

For interacting with the API you should also login and get the bearer token.

```bash
curl -i -d '{"login_id":"gateway","password":"###########"}' https://mattermost.example.com/api/v4/users/login
HTTP/2 200 
server: nginx
date: Wed, 02 Dec 2020 18:50:49 GMT
content-type: application/json
content-length: 673
token: 767676zz76zz76z76z76z76z
vary: Accept-Encoding
x-ratelimit-limit: 101
....

```
Set the *bearer* variable in the mattermost section of the toml configuration file

## Setting up Signal

To connect with Signal, you'll need to install [signal-cli](https://github.com/AsamK/signal-cli)

To register the signal phone number you need to run these commands:
```bash
$ signal-cli -u +316xxxxxxxxxx register
$ signal-cli -u +316xxxxxxxxxx verify XXX-XXX
```
The XXX-XXX code you wil get in an SMS text message so you'll have to actually install the simcard in some telephone. This is the only time it's needed.

Set **signal**->**phone** to the number you just registered with **signal-cli**
Next is to add the phone number into a signal group. You can then start **signalpoller** and 
look at its output; when something is said in the signal group you will see output like this:

```text
{"envelope":{"source":"+316xxxxxxxx","sourceDevice":1,"relay":null,"timestamp":1566735523785,"isReceipt":false,"dataMessage":{"timestamp":1566735523785,"message":"Hello","expiresInSeconds":3600,"attachments":[],"groupInfo":{"groupId":"XXXXXXXXXXXXXXXXXXXXXX==","members":null,"name":null,"type":"DELIVER"}},"syncMessage":null,"callMessage":null}}
```
Update **signal**->**gid** in hermod.toml  with the **groupId** in this output.

## Directories for attachments and urls

The photo's and attachments send by people in telegram and signal groups are downloaded and placed in suitable directories. For Telegram, use the **telegram-\>attachments** configuration option. Make sure this directory is shared over a HTTP webserver like apache and it is writeable by the webserver. Configure **telegram-\>url** to point to this same directory.

The **signal-cli** program by default saves all attachments in a directory **~/.local/share/signal-cli/attachments**. The easiest way to handle this is to move this entire directory to somewhere below the documentroot of the webserver and symlink it.

## Start the IRC bot

Verify permissions on the **signal-\>infile** and **irc-\>infile** files. Both should be writable by the user running the scripts and also by the webserver that is executing the telegram webHook. Then you can start the bot.

```bash
$ ./ircbot
Establishing connection to [irc.freenode.net]
:weber.freenode.net NOTICE * :*** Looking up your hostname...
:weber.freenode.net NOTICE * :*** Checking Ident
:weber.freenode.net NOTICE * :*** Couldn't look up your hostname
:weber.freenode.net NOTICE * :*** No Ident response
:weber.freenode.net 001 telegram_gateway :Welcome to the freenode Internet Relay Chat Network telegram_gateway
...
...

```
that's all. You will see messages scrolling showing the login proces on IRC.

## Start the matrixpoller (optional)

## Start the discordbot (optional)

You probably want to run these in screen(1) from cron
```bash
@reboot /home/hermod/bin/hermod
@reboot screen -S ircbot -d -m while true; do /home/hermod/bin/ircbot; done
@reboot screen -S signal -d -m while true; do /home/hermod/bin/signalbot; done
@reboot screen -S matrix -d -m while true; do /home/hermod/bin/matrixpoller; done
@reboot screen -S discord -d -m while true; do /home/hermod/bin/discordbot; done
```
