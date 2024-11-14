# ddlogger

Quick and minimal Log4Net-like logging interface.

Features:
- Add as many appenders with their log levels.
- Implement custom appenders with `Appender`.
- Set level of all current appenders using `logSetLevel`.

These appenders are included:
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
    logAddAppender(new CustomAppender()); // Add your appender instance to the list
    logSetLevel(LogLevel.info); // Set log level to info for all appenders
                                // Or when creating your appender, call ".setLogLevel"
    
    logInfo("Hello from '%s'!", args[0]);
}
```
