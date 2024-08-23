# ddlogger

Quick and minimal logging interface.

Initially created for [Aliceserver](https://github.com/dd86k/aliceserver)
and inspired by log4net without hierarchies, since I do not like the implementation
of Phobo's `std.logger` module.

Currently includes these appenders:
- `ConsoleAppender`: Print in the error standard stream (stderr) with µs process uptime.
- `FileAppender`: Print in a file with system time.

Making your own appender:
```d
import ddlogger;

class CustomAppender : Appender
{
    // You can make your own constructors and functions here

    override
    void log(ref LogMessage message)
    {
	// Handle the message however you wish here
    }
}

void main(string[] args)
{
    CustomAppender cappender = new CustomAppender();
    
    logAddAppender(cappender); // Add your appender instance to the list
    
    logSetLevel(LogLevel.info); // Set log level to info for all appenders
    
    logInfo("Hello, my path is '%s'!", args[0]);
}
```
