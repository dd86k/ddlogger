# ddlogger

Quick and minimal logging interface.

Initially created for [https://github.com/dd86k/aliceserver](Aliceserver)
and inspired by log4net without hierarchies, since I do not like the implementation
of Phobo's `std.logger` module.

Currently includes these appenders:
- `ConsoleAppender`: Print in the error standard stream (stderr) with µs process uptime.
- `FileAppender`: Print in a file with system time.
