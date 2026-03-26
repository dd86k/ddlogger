# ddlogger

Quick and minimal Log4Net/Log4j-like logging interface.

Features:
- Add as many appenders with their log levels.
- Implement custom appenders with `Appender`.
- Set level of all current appenders using `logSetLevel`.
- Module-specific filtering.

These appenders are included:
- `ConsoleAppender`: Print in the error standard stream (stderr) with µs process uptime.
- `FileAppender`: Print in a file with system time.

# Examples

## Making your own appender

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
    
    logInfo("Hello from '%s'!", args[0]); // printf formatting
}
```

## Module filtering

```d
import ddlogger;

class CountAppender : Appender
{
    int count;
    override void log(ref LogMessage message) { ++count; }
}

void main()
{
    // Module level filtering
    scope app = new CountAppender();
    
    app.setModuleLevel("myapp.rendering",        LogLevel.info);
    app.setModuleLevel("myapp.rendering.opengl", LogLevel.trace);
    
    assert(app.getEffectiveLevel("myapp.rendering.opengl") == LogLevel.trace);
    assert(app.getEffectiveLevel("myapp.rendering.vulkan") == LogLevel.info);
}
```
